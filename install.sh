#!/usr/bin/env bash
# =============================================================================
#  install.sh — Run this on your OFFLINE machine
#  Installs everything downloaded by download.sh, in the correct order.
#
#  Usage:
#    chmod +x install.sh
#    sudo ./install.sh              # Install everything
#    sudo ./install.sh --apt-only   # Install only APT packages
#    sudo ./install.sh --skip-snap  # Skip snap packages
#    sudo ./install.sh --dry-run    # Preview without installing
#    sudo ./install.sh --help
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

# ── Colour helpers ────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
header()  { echo -e "\n${BOLD}${BLUE}══════════════════════════════════════${RESET}"; \
             echo -e "${BOLD}${BLUE}  $*${RESET}"; \
             echo -e "${BOLD}${BLUE}══════════════════════════════════════${RESET}"; }
dry()     { echo -e "${YELLOW}[DRY-RUN]${RESET} $*"; }

# ── Argument parsing ─────────────────────────────────────────────────────────
DO_APT=true; DO_PIP=true; DO_NPM=true; DO_SNAP=true; DO_BINARIES=true
DRY_RUN=false

usage() {
    echo "Usage: sudo $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --apt-only       Install only APT packages"
    echo "  --skip-apt       Skip APT packages"
    echo "  --skip-pip       Skip Python/pip packages"
    echo "  --skip-npm       Skip NPM packages"
    echo "  --skip-snap      Skip Snap packages"
    echo "  --skip-binaries  Skip direct binaries"
    echo "  --dry-run        Show what would be done without doing it"
    echo "  --help           Show this help"
    exit 0
}

for arg in "$@"; do
    case $arg in
        --apt-only)      DO_PIP=false; DO_NPM=false; DO_SNAP=false; DO_BINARIES=false ;;
        --skip-apt)      DO_APT=false ;;
        --skip-pip)      DO_PIP=false ;;
        --skip-npm)      DO_NPM=false ;;
        --skip-snap)     DO_SNAP=false ;;
        --skip-binaries) DO_BINARIES=false ;;
        --dry-run)       DRY_RUN=true ;;
        --help)          usage ;;
        *) error "Unknown argument: $arg"; usage ;;
    esac
done

RUN() {
    if $DRY_RUN; then dry "$*"; else "$@"; fi
}

# ── Logging ───────────────────────────────────────────────────────────────────
mkdir -p "$DIR_LOGS"
LOG_FILE="$DIR_LOGS/install_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1
info "Logging to: $LOG_FILE"

# ── Pre-flight checks ─────────────────────────────────────────────────────────
preflight() {
    header "Pre-flight Checks"

    # Must be root (except dry-run)
    if ! $DRY_RUN && [ "$EUID" -ne 0 ]; then
        error "This script must be run as root. Use: sudo ./install.sh"
        exit 1
    fi

    info "Ubuntu codename : $UBUNTU_CODENAME"
    info "Architecture    : $ARCH"
    info "Toolkit dir     : $TOOLKIT_DIR"
    info "Dry-run mode    : $DRY_RUN"

    # Verify package directories exist
    local missing=false
    for dir in "$DIR_APT" "$DIR_PIP" "$DIR_NPM" "$DIR_SNAP" "$DIR_BINARIES"; do
        if [ ! -d "$dir" ]; then
            warn "Directory not found (will skip): $dir"
        fi
    done

    # Sanity: confirm this is an offline machine (warn only)
    if ping -c1 -W2 8.8.8.8 &>/dev/null 2>&1; then
        warn "Internet appears to be available — you are installing on an ONLINE machine."
        warn "That is fine, but this script is designed for offline use."
    else
        success "Confirmed: no internet connection (offline mode)"
    fi
}

# ── APT packages ──────────────────────────────────────────────────────────────
install_apt() {
    header "Installing APT Packages"

    if [ ! -d "$DIR_APT" ]; then
        warn "APT package directory not found: $DIR_APT — skipping"
        return
    fi

    local deb_count
    deb_count=$(find "$DIR_APT" -name '*.deb' | wc -l)
    info "Found $deb_count .deb files in $DIR_APT"

    if [ "$deb_count" -eq 0 ]; then
        warn "No .deb files found — skipping APT install"
        return
    fi

    # Register the local folder as an apt source
    local sources_file="/etc/apt/sources.list.d/offline-toolkit.list"
    info "Registering local APT repository..."
    RUN bash -c "echo 'deb [trusted=yes] file://$DIR_APT ./' > $sources_file"

    # Make sure Packages index exists
    if [ ! -f "$DIR_APT/Packages" ]; then
        info "Generating package index..."
        RUN bash -c "cd '$DIR_APT' && dpkg-scanpackages . 2>/dev/null > Packages"
        RUN bash -c "cd '$DIR_APT' && gzip -k9c Packages > Packages.gz"
    fi

    RUN apt-get update -o Dir::Etc::sourcelist="$sources_file" \
                       -o Dir::Etc::sourcelistd="" \
                       -o APT::Get::List-Cleanup="0" -qq || true

    # Install all in one shot (apt resolves order)
    info "Installing all APT packages..."
    RUN env DEBIAN_FRONTEND=noninteractive \
        apt-get install -y \
        --no-install-recommends \
        -o Dir::Etc::sourcelist="$sources_file" \
        -o Dir::Etc::sourcelistd="" \
        -o APT::Get::List-Cleanup="0" \
        "${APT_ALL[@]}" 2>&1 || {
            warn "Some packages failed via apt — falling back to dpkg..."
            RUN dpkg -i --force-depends "$DIR_APT"/*.deb 2>&1 || true
            RUN apt-get install -f -y 2>&1 || true
        }

    # Clean up the temporary apt source
    RUN rm -f "$sources_file"
    RUN apt-get update -qq 2>/dev/null || true

    success "APT packages installed"
}

# ── PIP packages ──────────────────────────────────────────────────────────────
install_pip() {
    header "Installing Python / pip Packages"

    if [ ! -d "$DIR_PIP" ]; then
        warn "PIP directory not found: $DIR_PIP — skipping"
        return
    fi

    local req_file="$DIR_PIP/requirements.txt"
    if [ ! -f "$req_file" ]; then
        warn "requirements.txt not found in $DIR_PIP — skipping"
        return
    fi

    info "Installing pip packages from local wheels..."
    RUN pip3 install \
        --no-index \
        --find-links "$DIR_PIP" \
        --requirement "$req_file" \
        --prefer-binary \
        2>&1 || warn "Some pip packages may have failed"

    success "Python packages installed"
}

# ── NPM packages ──────────────────────────────────────────────────────────────
install_npm() {
    header "Installing NPM Packages"

    if [ ! -d "$DIR_NPM" ]; then
        warn "NPM directory not found: $DIR_NPM — skipping"
        return
    fi

    if ! command -v npm &>/dev/null; then
        warn "npm not found — APT step may not have run yet, or nodejs is missing"
        return
    fi

    local tgz_count
    tgz_count=$(find "$DIR_NPM" -name '*.tgz' | wc -l)
    info "Found $tgz_count NPM tarballs"

    for tgz in "$DIR_NPM"/*.tgz; do
        [ -f "$tgz" ] || continue
        local pkg_name
        pkg_name=$(basename "$tgz" .tgz)
        info "Installing: $pkg_name"
        RUN npm install -g "$tgz" 2>&1 && \
            echo -e "  ${GREEN}✓ $pkg_name${RESET}" || \
            warn "Failed: $pkg_name"
    done

    success "NPM packages installed"
}

# ── Snap packages ─────────────────────────────────────────────────────────────
install_snap() {
    header "Installing Snap Packages"

    if [ ! -d "$DIR_SNAP" ]; then
        warn "Snap directory not found: $DIR_SNAP — skipping"
        return
    fi

    if ! command -v snap &>/dev/null; then
        warn "snap not available — skipping"
        return
    fi

    # Each snap download produces a .snap + .assert pair
    for assert_file in "$DIR_SNAP"/*.assert; do
        [ -f "$assert_file" ] || continue
        local snap_file="${assert_file%.assert}.snap"
        local pkg_name
        pkg_name=$(basename "$assert_file" .assert)

        if [ ! -f "$snap_file" ]; then
            warn "Missing .snap file for $pkg_name — skipping"
            continue
        fi

        info "Installing snap: $pkg_name"
        RUN snap ack "$assert_file" 2>&1 || true
        RUN snap install "$snap_file" --dangerous 2>&1 && \
            echo -e "  ${GREEN}✓ $pkg_name${RESET}" || \
            warn "Failed: $pkg_name"
    done

    success "Snap packages installed"
}

# ── Direct binaries ───────────────────────────────────────────────────────────
install_binaries() {
    header "Installing Direct Binaries"

    if [ ! -d "$DIR_BINARIES" ]; then
        warn "Binaries directory not found: $DIR_BINARIES — skipping"
        return
    fi

    local install_dir="/usr/local/bin"

    for entry in "${BINARY_DOWNLOADS[@]}"; do
        IFS='|' read -r name url filename <<< "$entry"
        local filepath="$DIR_BINARIES/$filename"

        if [ ! -f "$filepath" ]; then
            warn "Binary not found: $filepath — skipping $name"
            continue
        fi

        info "Installing: $name"

        # Handle zip files
        if [[ "$filename" == *.zip ]]; then
            local tmpdir
            tmpdir=$(mktemp -d)
            RUN unzip -q "$filepath" -d "$tmpdir"
            local binary
            binary=$(find "$tmpdir" -type f -name "$name" | head -1)
            if [ -n "$binary" ]; then
                RUN install -m 755 "$binary" "$install_dir/$name"
            else
                warn "Could not find binary named '$name' inside zip"
            fi
            RUN rm -rf "$tmpdir"
        else
            # Plain binary
            RUN install -m 755 "$filepath" "$install_dir/$name"
        fi

        # Verify
        if $DRY_RUN || command -v "$name" &>/dev/null; then
            echo -e "  ${GREEN}✓ $name → $install_dir/$name${RESET}"
        else
            warn "$name was installed but not found in PATH"
        fi
    done

    success "Direct binaries installed"
}

# ── Post-install verification ─────────────────────────────────────────────────
verify() {
    header "Verifying Installation"

    local pass=0; local fail=0

    # Key binaries to spot-check
    local checks=(
        git curl wget vim python3 pip3
        node npm gcc make openssl
        docker jq rsync tmux
    )

    for cmd in "${checks[@]}"; do
        if command -v "$cmd" &>/dev/null; then
            echo -e "  ${GREEN}✓${RESET} $cmd  $(command -v "$cmd")"
            pass=$((pass + 1))
        else
            echo -e "  ${RED}✗${RESET} $cmd  (not found)"
            fail=$((fail + 1))
        fi
    done

    echo ""
    success "Verification complete — ${pass} found, ${fail} missing"
    if [ "$fail" -gt 0 ]; then
        warn "Missing tools may not have been in the downloaded packages, or may need PATH refresh."
        warn "Try: source ~/.bashrc  or  exec \$SHELL"
    fi
}

# ── Summary ───────────────────────────────────────────────────────────────────
print_summary() {
    header "Installation Complete"
    echo -e "  ${BOLD}Log file:${RESET} $LOG_FILE"
    echo ""
    echo -e "  ${BOLD}Recommended next steps:${RESET}"
    echo -e "  1. Reload your shell:  ${CYAN}exec \$SHELL${RESET}"
    echo -e "  2. Verify docker:      ${CYAN}sudo systemctl enable --now docker${RESET}"
    echo -e "  3. Check versions:     ${CYAN}python3 --version && node --version && git --version${RESET}"
    echo ""
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
    echo -e "${BOLD}${GREEN}"
    echo "  ╔══════════════════════════════════════════╗"
    echo "  ║     Offline Toolkit — INSTALL MODE       ║"
    echo "  ╚══════════════════════════════════════════╝"
    echo -e "${RESET}"

    $DRY_RUN && warn "DRY-RUN mode — no changes will be made\n"

    preflight

    $DO_APT      && install_apt
    $DO_PIP      && install_pip
    $DO_NPM      && install_npm
    $DO_SNAP     && install_snap
    $DO_BINARIES && install_binaries

    verify
    print_summary
}

main "$@"
