#!/usr/bin/env bash
# =============================================================================
#  store.sh - Offline APT store for selected package installs
#
#  This script runs on the OFFLINE Ubuntu machine after download.sh has built
#  packages/apt. It lets you search, inspect, and install selected packages or
#  curated groups while letting apt resolve the individual dependency closure.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
header()  { echo -e "\n${BOLD}${BLUE}$*${RESET}"; }

usage() {
    cat <<EOF
Usage: $0 COMMAND [OPTIONS]

Commands:
  list                         List packages available in the local APT store
  search QUERY                 Search local package names and descriptions
  info PACKAGE                 Show package metadata from the local store
  version PACKAGE              Show exact local version for one package
  versions [QUERY]             List local package versions, optionally filtered
  deps PACKAGE                 Show recorded dependency closure for a package
  groups                       List curated install groups from config.sh
  doctor [PACKAGE ...]         Check local index, selected packages, and target
  install [OPTIONS] PACKAGE... Install selected packages from the local store

Install options:
  --group NAME                 Install a curated group from config.sh
  --all                        Install every package in APT_ALL
  --dry-run                    Show apt's install plan without changing system
  --with-recommends            Allow apt to install Recommended packages too

Examples:
  ./store.sh search docker
  ./store.sh info docker.io
  ./store.sh version docker.io
  ./store.sh versions python
  ./store.sh deps docker.io
  sudo ./store.sh install git curl htop
  sudo ./store.sh install --group python-dev
  sudo ./store.sh install --dry-run --group docker
EOF
}

packages_file() {
    if [ -f "$DIR_APT/Packages" ]; then
        printf '%s\n' "$DIR_APT/Packages"
    elif [ -f "$DIR_APT/Packages.gz" ]; then
        printf '%s\n' "$DIR_APT/Packages.gz"
    else
        return 1
    fi
}

read_packages() {
    local file
    file="$(packages_file)" || {
        error "No APT package index found in $DIR_APT"
        error "Run ./download.sh on the online machine first, then transfer the toolkit."
        return 1
    }

    if [[ "$file" == *.gz ]]; then
        gzip -dc "$file"
    else
        cat "$file"
    fi
}

ensure_packages_index() {
    mkdir -p "$DIR_APT"
    if [ -f "$DIR_APT/Packages" ] || [ -f "$DIR_APT/Packages.gz" ]; then
        return 0
    fi

    if ! command -v dpkg-scanpackages >/dev/null 2>&1; then
        error "Package index is missing and dpkg-scanpackages is not installed."
        error "Install dpkg-dev on the download machine or re-run ./download.sh."
        return 1
    fi

    info "Generating local APT package index..."
    (cd "$DIR_APT" && dpkg-scanpackages . 2>/dev/null > Packages)
    (cd "$DIR_APT" && gzip -k9c Packages > Packages.gz)
}

package_exists() {
    local package="$1"
    read_packages | awk -v package="$package" '
        BEGIN { RS=""; FS="\n"; found=0 }
        {
            for (i = 1; i <= NF; i++) {
                if ($i == "Package: " package) {
                    found=1
                    exit
                }
            }
        }
        END { exit found ? 0 : 1 }
    '
}

list_packages() {
    read_packages | awk -F': ' '/^Package: / { print $2 }' | sort -u
}

list_versions() {
    local query="${1:-}"

    read_packages | awk -v query="$query" '
        BEGIN { RS=""; FS="\n"; q=tolower(query) }
        {
            package=""; version=""; arch="";
            for (i = 1; i <= NF; i++) {
                if ($i ~ /^Package: /) package=substr($i, 10)
                else if ($i ~ /^Version: /) version=substr($i, 10)
                else if ($i ~ /^Architecture: /) arch=substr($i, 15)
            }
            if (package == "") next
            line=package " " version " " arch
            if (q == "" || index(tolower(line), q)) {
                printf "%-32s %-32s %s\n", package, version, arch
            }
        }
    ' | sort -u
}

show_version() {
    local package="$1"
    read_packages | awk -v package="$package" '
        BEGIN { RS=""; FS="\n"; found=0 }
        {
            name=""; version=""; arch="";
            for (i = 1; i <= NF; i++) {
                if ($i ~ /^Package: /) name=substr($i, 10)
                else if ($i ~ /^Version: /) version=substr($i, 10)
                else if ($i ~ /^Architecture: /) arch=substr($i, 15)
            }
            if (name == package) {
                printf "%s\t%s\t%s\n", name, version, arch
                found=1
            }
        }
        END { if (!found) exit 1 }
    ' || {
        error "Package not found in local store: $package"
        return 1
    }
}

search_packages() {
    local query="$1"
    read_packages | awk -v query="$query" '
        BEGIN { RS=""; FS="\n"; q=tolower(query) }
        {
            package=""; description="";
            for (i = 1; i <= NF; i++) {
                if ($i ~ /^Package: /) package=substr($i, 10)
                if ($i ~ /^Description: /) description=substr($i, 14)
            }
            if (index(tolower($0), q) && package != "") {
                printf "%-32s %s\n", package, description
            }
        }
    ' | sort -u
}

show_info() {
    local package="$1"
    read_packages | awk -v package="$package" '
        BEGIN { RS=""; FS="\n"; found=0 }
        {
            matched=0
            for (i = 1; i <= NF; i++) {
                if ($i == "Package: " package) {
                    matched=1
                    found=1
                    break
                }
            }
            if (!matched) next

            keep_continuation=0
            for (i = 1; i <= NF; i++) {
                if ($i ~ /^(Package|Version|Architecture|Description|Depends|Pre-Depends|Recommends|Filename|Size): /) {
                    print $i
                    keep_continuation=($i ~ /^(Description|Depends|Pre-Depends|Recommends): /)
                } else if (keep_continuation && $i ~ /^ /) {
                    print $i
                } else {
                    keep_continuation=0
                }
            }
            exit
        }
        END { if (!found) exit 1 }
    ' || {
        error "Package not found in local store: $package"
        return 1
    }
}

show_deps() {
    local package="$1"
    local closure_file="$DIR_APT_CLOSURES/$package.txt"

    if [ ! -f "$closure_file" ]; then
        error "No recorded dependency closure for: $package"
        error "Run ./download.sh again on the matching online Ubuntu release."
        return 1
    fi

    cat "$closure_file"
}

list_groups() {
    local group packages count description
    for group in "${APT_STORE_GROUPS[@]}"; do
        packages="${APT_STORE_GROUP_PACKAGES[$group]:-}"
        description="${APT_STORE_GROUP_DESCRIPTIONS[$group]:-}"
        count=$(wc -w <<< "$packages" | tr -d ' ')
        printf "%-16s %3s packages  %s\n" "$group" "$count" "$description"
    done
}

dedupe_words() {
    awk '
        {
            for (i = 1; i <= NF; i++) {
                if (!seen[$i]++) print $i
            }
        }
    '
}

expand_selection() {
    local selected=()
    local group

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --group)
                shift
                [ "$#" -gt 0 ] || { error "--group needs a group name"; return 1; }
                group="$1"
                if [ -z "${APT_STORE_GROUP_PACKAGES[$group]+x}" ]; then
                    error "Unknown group: $group"
                    echo "Available groups:"
                    list_groups
                    return 1
                fi
                # shellcheck disable=SC2206
                selected+=( ${APT_STORE_GROUP_PACKAGES[$group]} )
                ;;
            --all)
                selected+=( "${APT_ALL[@]}" )
                ;;
            --dry-run|--with-recommends)
                ;;
            -*)
                error "Unknown option for selection: $1"
                return 1
                ;;
            *)
                selected+=( "$1" )
                ;;
        esac
        shift
    done

    if [ "${#selected[@]}" -eq 0 ]; then
        error "No packages selected. Use PACKAGE names, --group NAME, or --all."
        return 1
    fi

    printf '%s\n' "${selected[@]}" | dedupe_words
}

check_target() {
    local host_arch host_codename
    host_arch="$(dpkg --print-architecture 2>/dev/null || echo unknown)"
    host_codename="$(lsb_release -cs 2>/dev/null || echo unknown)"

    info "Host Ubuntu codename : $host_codename"
    info "Host architecture    : $host_arch"
    info "Config codename      : $UBUNTU_CODENAME"
    info "Config architecture  : $ARCH"

    if [ "$host_arch" != "$ARCH" ]; then
        warn "Architecture mismatch. This store was configured for $ARCH, host is $host_arch."
    fi

    if [ "$host_codename" != "$UBUNTU_CODENAME" ]; then
        warn "Ubuntu codename mismatch. Build one store per target release."
        warn "For Ubuntu 22.04 use jammy; for Ubuntu 26.04 use resolute."
    fi
}

check_selected_available() {
    local missing=()
    local package

    for package in "$@"; do
        if ! package_exists "$package"; then
            missing+=( "$package" )
        fi
    done

    if [ "${#missing[@]}" -gt 0 ]; then
        error "These selected packages are not in the local APT store:"
        printf '  - %s\n' "${missing[@]}" >&2
        error "Add them to config.sh and run ./download.sh again on the matching online Ubuntu release."
        return 1
    fi
}

check_recorded_closures() {
    local missing=()
    local package

    for package in "$@"; do
        if [ ! -s "$DIR_APT_CLOSURES/$package.txt" ]; then
            missing+=( "$package" )
        fi
    done

    if [ "${#missing[@]}" -gt 0 ]; then
        warn "No recorded dependency closure files for:"
        printf '  - %s\n' "${missing[@]}"
        warn "The APT simulation can still verify dependencies if the local repo is complete."
    fi
}

check_closure_packages_available() {
    local package dep closure_file
    local missing=()

    for package in "$@"; do
        closure_file="$DIR_APT_CLOSURES/$package.txt"
        [ -s "$closure_file" ] || continue

        while IFS= read -r dep; do
            [ -n "$dep" ] || continue
            if ! package_exists "$dep"; then
                missing+=( "$package -> $dep" )
            fi
        done < "$closure_file"
    done

    if [ "${#missing[@]}" -gt 0 ]; then
        error "Recorded dependency closures reference packages missing from the local store:"
        printf '  - %s\n' "${missing[@]}" >&2
        error "Re-run ./download.sh on the matching online Ubuntu release."
        return 1
    fi
}

write_temp_source() {
    local source_file="$1"
    printf 'deb [trusted=yes] file://%s ./\n' "$DIR_APT" > "$source_file"
}

apt_local_opts() {
    local source_file="$1"
    local lists_dir="$2"
    printf '%s\n' \
        -o "Dir::Etc::sourcelist=$source_file" \
        -o "Dir::Etc::sourceparts=-" \
        -o "Dir::State::Lists=$lists_dir" \
        -o "APT::Get::List-Cleanup=0"
}

install_selected() {
    local dry_run=false
    local recommends_flag="--no-install-recommends"
    local arg
    local selection_text
    local -a selected
    local -a APT_OPTS

    for arg in "$@"; do
        case "$arg" in
            --dry-run) dry_run=true ;;
            --with-recommends) recommends_flag="" ;;
        esac
    done

    selection_text="$(expand_selection "$@")" || return 1
    mapfile -t selected <<< "$selection_text"
    check_selected_available "${selected[@]}"

    if [ "$EUID" -ne 0 ]; then
        error "Install needs root so apt can register and use the local repo."
        error "Run: sudo $0 install ${selected[*]}"
        return 1
    fi

    local source_file lists_dir
    source_file="$(mktemp /tmp/offline-store-source.XXXXXX)"
    lists_dir="$(mktemp -d /tmp/offline-store-lists.XXXXXX)"
    mkdir -p "$lists_dir/partial"
    write_temp_source "$source_file"

    cleanup() {
        rm -f "$source_file"
        rm -rf "$lists_dir"
    }
    trap cleanup RETURN

    mapfile -t APT_OPTS < <(apt_local_opts "$source_file" "$lists_dir")

    header "Refreshing Local APT Store"
    apt-get update "${APT_OPTS[@]}" -qq

    header "Dependency Plan"
    info "Selected packages: ${selected[*]}"
    if [ -n "$recommends_flag" ]; then
        info "Recommends: disabled"
    else
        info "Recommends: enabled"
    fi

    if ! env DEBIAN_FRONTEND=noninteractive apt-get install -s -y \
        ${recommends_flag:+$recommends_flag} \
        "${APT_OPTS[@]}" \
        "${selected[@]}"; then
        error "apt could not resolve this selection from the local store."
        error "The missing package/dependency named above must be downloaded into packages/apt."
        return 1
    fi

    if $dry_run; then
        success "Dry-run complete. No packages were installed."
        return 0
    fi

    header "Installing Selected Packages"
    env DEBIAN_FRONTEND=noninteractive apt-get install -y \
        ${recommends_flag:+$recommends_flag} \
        "${APT_OPTS[@]}" \
        "${selected[@]}"
    success "Selected APT packages installed."
}

doctor() {
    ensure_packages_index
    check_target

    local count
    count=$(list_packages | wc -l | tr -d ' ')
    info "Local APT packages : $count"

    if [ "$#" -gt 0 ]; then
        local selection_text
        local -a selected
        selection_text="$(expand_selection "$@")" || return 1
        mapfile -t selected <<< "$selection_text"
        check_selected_available "${selected[@]}"
        check_recorded_closures "${selected[@]}"
        check_closure_packages_available "${selected[@]}"
        success "Selected packages are present in the local store."
        success "Recorded dependency closure packages are present in the local store."
        warn "Run 'sudo ./store.sh install --dry-run ...' to verify the full dependency closure with apt."
    else
        success "Store index is readable. Pass package names to doctor for selection checks."
    fi
}

main() {
    local command="${1:-}"
    if [ -z "$command" ] || [ "$command" = "--help" ] || [ "$command" = "-h" ]; then
        usage
        return 0
    fi
    shift

    case "$command" in
        list)
            ensure_packages_index
            list_packages
            ;;
        search)
            [ "$#" -gt 0 ] || { error "search needs a query"; return 1; }
            ensure_packages_index
            search_packages "$*"
            ;;
        info)
            [ "$#" -eq 1 ] || { error "info needs exactly one package"; return 1; }
            ensure_packages_index
            show_info "$1"
            ;;
        version)
            [ "$#" -eq 1 ] || { error "version needs exactly one package"; return 1; }
            ensure_packages_index
            show_version "$1"
            ;;
        versions)
            [ "$#" -le 1 ] || { error "versions accepts zero or one query"; return 1; }
            ensure_packages_index
            list_versions "${1:-}"
            ;;
        deps)
            [ "$#" -eq 1 ] || { error "deps needs exactly one package"; return 1; }
            show_deps "$1"
            ;;
        groups)
            list_groups
            ;;
        doctor)
            doctor "$@"
            ;;
        install)
            ensure_packages_index
            install_selected "$@"
            ;;
        *)
            error "Unknown command: $command"
            usage
            return 1
            ;;
    esac
}

main "$@"
