#!/usr/bin/env bash
# =============================================================================
#  download.sh — Run this on your ONLINE machine
#  Downloads all packages defined in config.sh into organized folders.
#  Transfer the entire toolkit/ folder to your offline machine when done.
#
#  Usage:
#    chmod +x download.sh
#    ./download.sh              # Download everything
#    ./download.sh --apt-only   # Download only APT packages
#    ./download.sh --skip-snap  # Skip snap packages
#    ./download.sh --help
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

# ── Argument parsing ─────────────────────────────────────────────────────────
DO_APT=true; DO_PIP=true; DO_NPM=true; DO_SNAP=true; DO_BINARIES=true

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --apt-only       Download only APT packages"
    echo "  --skip-apt       Skip APT packages"
    echo "  --skip-pip       Skip Python/pip packages"
    echo "  --skip-npm       Skip NPM packages"
    echo "  --skip-snap      Skip Snap packages"
    echo "  --skip-binaries  Skip direct binary downloads"
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
        --help)          usage ;;
        *) error "Unknown argument: $arg"; usage ;;
    esac
done

# ── Logging ───────────────────────────────────────────────────────────────────
mkdir -p "$DIR_LOGS"
LOG_FILE="$DIR_LOGS/download_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1
info "Logging to: $LOG_FILE"

# ── Pre-flight checks ─────────────────────────────────────────────────────────
preflight() {
    header "Pre-flight Checks"
    info "Ubuntu codename : $UBUNTU_CODENAME"
    info "Architecture    : $ARCH"
    info "Output directory: $TOOLKIT_DIR"

    # ping is blocked on GitHub Actions runners — use curl instead
    if ! curl -fsSL --max-time 5 https://archive.ubuntu.com &>/dev/null && \
       ! curl -fsSL --max-time 5 https://google.com &>/dev/null; then
        error "No internet connection detected. This script requires an online machine."
        exit 1
    fi
    success "Internet connection confirmed"

    for cmd in apt-get dpkg wget curl; do
        command -v "$cmd" &>/dev/null || { error "Required command not found: $cmd"; exit 1; }
    done
    success "Required commands present"

    sudo apt-get update -qq
    success "APT index refreshed"
}

# ── APT packages ──────────────────────────────────────────────────────────────
apt_dependency_closure() {
    local pkg="$1"

    if command -v apt-rdepends &>/dev/null; then
        apt-rdepends "$pkg" 2>/dev/null \
            | grep -v '^ ' \
            | grep -v '^debconf-2' \
            | sort -u
    else
        apt-cache depends --recurse \
            --no-recommends \
            --no-suggests \
            --no-conflicts \
            --no-breaks \
            --no-replaces \
            --no-enhances \
            "$pkg" 2>/dev/null \
            | awk '/^[[:alnum:]][[:alnum:].+:-]*$/ { print $1 }' \
            | sort -u
    fi
}

write_apt_version_catalogs() {
    mkdir -p "$DIR_CATALOG/apt"

    local package_index="$DIR_APT/Packages"
    if [ ! -f "$package_index" ]; then
        warn "APT package index missing; skipping version catalog"
        return
    fi

    awk '
        BEGIN {
            RS="";
            FS="\n";
            OFS="\t";
            print "package", "version", "architecture", "filename", "description";
        }
        {
            package=""; version=""; arch=""; filename=""; description="";
            for (i = 1; i <= NF; i++) {
                if ($i ~ /^Package: /) package=substr($i, 10);
                else if ($i ~ /^Version: /) version=substr($i, 10);
                else if ($i ~ /^Architecture: /) arch=substr($i, 15);
                else if ($i ~ /^Filename: /) filename=substr($i, 11);
                else if ($i ~ /^Description: /) description=substr($i, 14);
            }
            if (package != "") print package, version, arch, filename, description;
        }
    ' "$package_index" > "$DIR_CATALOG/apt/packages.tsv"

    {
        printf 'package\tversion\tarchitecture\tstatus\n'
        local pkg
        for pkg in "${APT_ALL[@]}"; do
            awk -v pkg="$pkg" '
                BEGIN { RS=""; FS="\n"; found=0 }
                {
                    package=""; version=""; arch="";
                    for (i = 1; i <= NF; i++) {
                        if ($i ~ /^Package: /) package=substr($i, 10);
                        else if ($i ~ /^Version: /) version=substr($i, 10);
                        else if ($i ~ /^Architecture: /) arch=substr($i, 15);
                    }
                    if (package == pkg && !found) {
                        print package "\t" version "\t" arch "\tpresent";
                        found=1;
                    }
                }
                END {
                    if (!found) print pkg "\t\t\tmissing";
                }
            ' "$package_index"
        done
    } > "$DIR_CATALOG/apt/requested.tsv"

    success "APT version catalog written to: $DIR_CATALOG/apt/packages.tsv"
    success "Requested package versions written to: $DIR_CATALOG/apt/requested.tsv"
}

download_apt() {
    header "Downloading APT Packages"
    mkdir -p "$DIR_APT" "$DIR_CATALOG/apt" "$DIR_APT_CLOSURES"

    # Install apt-rdepends for deep dependency resolution
    sudo apt-get install -y -qq apt-rdepends 2>/dev/null || true

    local failed=()
    local missing=()
    local total=${#APT_ALL[@]}
    local count=0

    for pkg in "${APT_ALL[@]}"; do
        count=$((count + 1))
        printf "${CYAN}[%3d/%3d]${RESET} Downloading %-35s" "$count" "$total" "$pkg..."

        # Check if package exists
        if ! apt-cache show "$pkg" &>/dev/null; then
            warn "Not found — skipping $pkg"
            failed+=("$pkg")
            missing+=("$pkg")
            continue
        fi

        local closure_file="$DIR_APT_CLOSURES/$pkg.txt"
        apt_dependency_closure "$pkg" > "$closure_file"

        if [ ! -s "$closure_file" ]; then
            printf '%s\n' "$pkg" > "$closure_file"
            warn "Dependency closure was empty — using package only for $pkg"
        fi

        # Download package + its per-package dependency closure into DIR_APT.
        (cd "$DIR_APT" && xargs -r apt-get download < "$closure_file" 2>/dev/null) || \
        (cd "$DIR_APT" && apt-get download "$pkg" 2>/dev/null) || {
            warn "Failed to download $pkg"
            failed+=("$pkg")
            continue
        }

        echo -e " ${GREEN}✓${RESET}"
    done

    # Build local repo index for apt to use on the offline machine
    info "Building APT package index..."
    (cd "$DIR_APT" && dpkg-scanpackages . 2>/dev/null | gzip -9c > Packages.gz)
    (cd "$DIR_APT" && dpkg-scanpackages . 2>/dev/null > Packages)
    write_apt_version_catalogs

    success "APT packages saved to: $DIR_APT"
    success "Total .deb files: $(find "$DIR_APT" -name '*.deb' | wc -l)"
    success "Dependency closures saved to: $DIR_APT_CLOSURES"

    if [ ${#failed[@]} -gt 0 ]; then
        warn "The following packages were not found and were skipped:"
        printf '  - %s\n' "${failed[@]}"
    fi

    {
        printf '%s\n' "# Missing APT packages"
        printf '%s\n' "${missing[@]:-}"
    } > "$DIR_CATALOG/apt/missing.txt"

    {
        printf '%s\n' "# Failed APT package downloads"
        printf '%s\n' "${failed[@]:-}"
    } > "$DIR_CATALOG/apt/failed-downloads.txt"
}

# ── PIP packages ──────────────────────────────────────────────────────────────
download_pip() {
    header "Downloading Python / pip Packages"
    mkdir -p "$DIR_PIP"

    # Ensure pip is available
    sudo apt-get install -y -qq python3-pip &>/dev/null

    # Write a requirements.txt from config
    local req_file="$DIR_PIP/requirements.txt"
    printf '%s\n' "${PIP_PACKAGES[@]}" > "$req_file"
    info "requirements.txt written with ${#PIP_PACKAGES[@]} packages"

    # Download wheels for the current platform
    pip3 download \
        --dest "$DIR_PIP" \
        --requirement "$req_file" \
        --prefer-binary \
        2>&1 | grep -E '(Collecting|Downloading|Saved|error)' || true

    success "PIP wheels saved to: $DIR_PIP"
    success "Total files: $(find "$DIR_PIP" -name '*.whl' -o -name '*.tar.gz' | wc -l)"
}

# ── NPM packages ──────────────────────────────────────────────────────────────
download_npm() {
    header "Downloading NPM Packages"
    mkdir -p "$DIR_NPM"

    if ! command -v npm &>/dev/null; then
        sudo apt-get install -y -qq nodejs npm &>/dev/null
    fi

    for pkg in "${NPM_PACKAGES[@]}"; do
        info "Packing: $pkg"
        # npm pack downloads the tarball locally
        (cd "$DIR_NPM" && npm pack "$pkg" 2>/dev/null) && \
            echo -e "  ${GREEN}✓ $pkg${RESET}" || \
            warn "Failed to pack $pkg"
    done

    success "NPM tarballs saved to: $DIR_NPM"
    success "Total .tgz files: $(find "$DIR_NPM" -name '*.tgz' | wc -l)"
}

# ── Snap packages ─────────────────────────────────────────────────────────────
download_snap() {
    header "Downloading Snap Packages"
    mkdir -p "$DIR_SNAP"

    if ! command -v snap &>/dev/null; then
        warn "snap not available — skipping snap downloads"
        return
    fi

    for entry in "${SNAP_PACKAGES[@]}"; do
        local pkg_name="${entry%% *}"   # first word is the package name
        info "Downloading snap: $pkg_name"
        (cd "$DIR_SNAP" && snap download $entry 2>/dev/null) && \
            echo -e "  ${GREEN}✓ $pkg_name${RESET}" || \
            warn "Failed to download snap: $pkg_name"
    done

    success "Snap packages saved to: $DIR_SNAP"
}

# ── Direct binaries ───────────────────────────────────────────────────────────
download_binaries() {
    header "Downloading Direct Binaries"
    mkdir -p "$DIR_BINARIES"

    for entry in "${BINARY_DOWNLOADS[@]}"; do
        IFS='|' read -r name url filename <<< "$entry"
        info "Downloading: $name  →  $filename"
        wget -q --show-progress -O "$DIR_BINARIES/$filename" "$url" && \
            echo -e "  ${GREEN}✓ $name${RESET}" || \
            warn "Failed to download $name from $url"
    done

    success "Binaries saved to: $DIR_BINARIES"
}

# ── Write manifest ────────────────────────────────────────────────────────────
write_manifest() {
    header "Writing Manifest"
    local manifest="$TOOLKIT_DIR/MANIFEST.txt"
    {
        echo "# Offline Toolkit Manifest"
        echo "# Generated: $(date)"
        echo "# Ubuntu: $UBUNTU_CODENAME  |  Arch: $ARCH"
        echo ""
        echo "## APT Packages (${#APT_ALL[@]})"
        printf '  %s\n' "${APT_ALL[@]}"
        echo ""
        echo "## APT Dependency Closures"
        echo "  Directory: $DIR_APT_CLOSURES"
        echo "  Files    : $(find "$DIR_APT_CLOSURES" -name '*.txt' 2>/dev/null | wc -l)"
        echo "  Versions : $DIR_CATALOG/apt/packages.tsv"
        echo "  Requested: $DIR_CATALOG/apt/requested.tsv"
        echo ""
        echo "## Python Packages (${#PIP_PACKAGES[@]})"
        printf '  %s\n' "${PIP_PACKAGES[@]}"
        echo ""
        echo "## NPM Packages (${#NPM_PACKAGES[@]})"
        printf '  %s\n' "${NPM_PACKAGES[@]}"
        echo ""
        echo "## Snap Packages (${#SNAP_PACKAGES[@]})"
        printf '  %s\n' "${SNAP_PACKAGES[@]}"
        echo ""
        echo "## Direct Binaries"
        for e in "${BINARY_DOWNLOADS[@]}"; do IFS='|' read -r n u f <<< "$e"; echo "  $n ($f)"; done
        echo ""
        echo "## File Counts"
        echo "  APT  : $(find "$DIR_APT"      -name '*.deb'             2>/dev/null | wc -l) .deb files"
        echo "  PIP  : $(find "$DIR_PIP"      -name '*.whl' -o -name '*.tar.gz' 2>/dev/null | wc -l) wheels"
        echo "  NPM  : $(find "$DIR_NPM"      -name '*.tgz'             2>/dev/null | wc -l) tarballs"
        echo "  SNAP : $(find "$DIR_SNAP"     -name '*.snap'            2>/dev/null | wc -l) snaps"
        echo "  BINS : $(find "$DIR_BINARIES" -type f                   2>/dev/null | wc -l) files"
    } > "$manifest"
    success "Manifest written: $manifest"
}

# ── Summary ───────────────────────────────────────────────────────────────────
print_summary() {
    header "Download Complete"
    local total_size
    total_size=$(du -sh "$TOOLKIT_DIR/packages" 2>/dev/null | cut -f1)
    echo -e "  ${BOLD}Total size:${RESET} $total_size"
    echo -e "  ${BOLD}Location:${RESET}   $TOOLKIT_DIR"
    echo ""
    echo -e "  ${BOLD}Next steps:${RESET}"
    echo -e "  1. Transfer the entire ${CYAN}$(basename "$TOOLKIT_DIR")/${RESET} folder to your offline machine"
    echo -e "     ${YELLOW}rsync -avz offline-toolkit/ user@offline-machine:/home/user/offline-toolkit/${RESET}"
    echo -e "     ${YELLOW}# or copy to USB, zip, scp, etc.${RESET}"
    echo -e "  2. On the offline machine, run:"
    echo -e "     ${GREEN}cd offline-toolkit && chmod +x install.sh && sudo ./install.sh${RESET}"
    echo ""
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
    echo -e "${BOLD}${BLUE}"
    echo "  ╔══════════════════════════════════════════╗"
    echo "  ║     Offline Toolkit — DOWNLOAD MODE      ║"
    echo "  ╚══════════════════════════════════════════╝"
    echo -e "${RESET}"

    preflight

    $DO_APT      && download_apt
    $DO_PIP      && download_pip
    $DO_NPM      && download_npm
    $DO_SNAP     && download_snap
    $DO_BINARIES && download_binaries

    write_manifest
    print_summary
}

main "$@"
