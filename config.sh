#!/usr/bin/env bash
# =============================================================================
#  config.sh — Single source of truth for offline toolkit
#  Edit this file to add or remove any packages.
#  Both download.sh and install.sh source this file automatically.
# =============================================================================

# --- APT PACKAGES ------------------------------------------------------------
# Core system utilities
APT_SYSTEM=(
    curl wget git vim nano htop tree
    unzip zip tar gzip bzip2 xz-utils
    ca-certificates gnupg lsb-release
    software-properties-common apt-transport-https
    build-essential make cmake pkg-config
    openssh-client openssh-server
    net-tools iputils-ping nmap traceroute
    rsync screen tmux
)

# Development languages & runtimes
APT_DEV=(
    python3 python3-pip python3-venv python3-dev
    python3-setuptools python3-wheel
    nodejs npm
    default-jdk default-jre
    ruby ruby-dev
    golang-go
    gcc g++ gfortran
    libssl-dev libffi-dev zlib1g-dev
    sqlite3 libsqlite3-dev
)

# Networking & security tools
APT_NETWORK=(
    ufw iptables
    tcpdump wireshark-common tshark
    netcat-openbsd socat
    fail2ban
    openssl
)

# Docker & containers
APT_DOCKER=(
    docker.io docker-compose
    containerd
)

# Data & databases
APT_DATA=(
    jq xmlstarlet
    postgresql postgresql-client
    mysql-client
    redis-tools
)

# Productivity & text processing
APT_PRODUCTIVITY=(
    git-lfs
    shellcheck
    cloc
    ripgrep fd-find bat
    fzf
    ncdu
    moreutils
    parallel
)

# Combine all APT groups into one master list
APT_ALL=(
    "${APT_SYSTEM[@]}"
    "${APT_DEV[@]}"
    "${APT_NETWORK[@]}"
    "${APT_DOCKER[@]}"
    "${APT_DATA[@]}"
    "${APT_PRODUCTIVITY[@]}"
)

# --- OFFLINE STORE GROUPS ----------------------------------------------------
# These groups are used by store.sh for selected offline installs.
# Keep package names here in APT_ALL too, so download.sh brings their .deb files
# and dependency closure into packages/apt.
APT_STORE_GROUPS=(
    dev-core
    python-dev
    node-dev
    docker
    network
    databases
    productivity
    full
)

declare -A APT_STORE_GROUP_DESCRIPTIONS=(
    [dev-core]="Core shell, build, Git, editor, and archive tools"
    [python-dev]="Python runtime, pip, virtualenv, headers, and common build pieces"
    [node-dev]="Node.js, npm, and JavaScript tooling base packages"
    [docker]="Docker engine, compose, and container runtime packages"
    [network]="Network troubleshooting, SSH, firewall, packet, and scan tools"
    [databases]="Database clients, PostgreSQL, SQLite, Redis tools, and JSON/XML helpers"
    [productivity]="CLI productivity tools such as ripgrep, fzf, shellcheck, and ncdu"
    [full]="Everything listed in APT_ALL"
)

declare -A APT_STORE_GROUP_PACKAGES=(
    [dev-core]="curl wget git vim nano htop tree unzip zip tar gzip bzip2 xz-utils ca-certificates gnupg lsb-release software-properties-common apt-transport-https build-essential make cmake pkg-config openssh-client openssh-server rsync screen tmux"
    [python-dev]="python3 python3-pip python3-venv python3-dev python3-setuptools python3-wheel build-essential pkg-config libssl-dev libffi-dev zlib1g-dev sqlite3 libsqlite3-dev"
    [node-dev]="nodejs npm build-essential git curl"
    [docker]="docker.io docker-compose containerd iptables"
    [network]="ufw iptables tcpdump wireshark-common tshark netcat-openbsd socat fail2ban openssl net-tools iputils-ping nmap traceroute openssh-client openssh-server"
    [databases]="jq xmlstarlet postgresql postgresql-client mysql-client redis-tools sqlite3 libsqlite3-dev"
    [productivity]="git-lfs shellcheck cloc ripgrep fd-find bat fzf ncdu moreutils parallel"
)
APT_STORE_GROUP_PACKAGES[full]="${APT_ALL[*]}"

# --- PIP PACKAGES (Python) ---------------------------------------------------
PIP_PACKAGES=(
    # CLI & utilities
    httpie
    tldr
    rich
    # Dev tools
    black isort flake8 mypy
    pytest
    ipython
    jupyter
    # Data
    pandas numpy scipy matplotlib
    requests
    pyyaml toml
    # Infra / automation
    ansible
    fabric
    paramiko
)

# --- SNAP PACKAGES -----------------------------------------------------------
# Format: "package_name --channel=stable"  (or just "package_name")
SNAP_PACKAGES=(
    "code --classic"
    "go --classic"
    "kubectl --classic"
    "helm --classic"
)

# --- NPM GLOBAL PACKAGES -----------------------------------------------------
NPM_PACKAGES=(
    yarn
    typescript
    ts-node
    eslint
    prettier
    nodemon
    http-server
    pm2
)

# --- DIRECT BINARY DOWNLOADS -------------------------------------------------
# Format: "name|url|install_path"
# These are downloaded as-is and placed into bin/
BINARY_DOWNLOADS=(
    "terraform|https://releases.hashicorp.com/terraform/1.7.5/terraform_1.7.5_linux_amd64.zip|terraform.zip"
    "kubectl|https://dl.k8s.io/release/v1.29.3/bin/linux/amd64/kubectl|kubectl"
)

# --- DIRECTORIES -------------------------------------------------------------
# Output directory structure (used by download.sh and install.sh)
TOOLKIT_DIR="${TOOLKIT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
DIR_APT="$TOOLKIT_DIR/packages/apt"
DIR_PIP="$TOOLKIT_DIR/packages/pip"
DIR_NPM="$TOOLKIT_DIR/packages/npm"
DIR_SNAP="$TOOLKIT_DIR/packages/snap"
DIR_BINARIES="$TOOLKIT_DIR/packages/binaries"
DIR_CATALOG="$TOOLKIT_DIR/catalog"
DIR_APT_CLOSURES="$DIR_CATALOG/apt/closures"
DIR_LOGS="$TOOLKIT_DIR/logs"

# --- SETTINGS ----------------------------------------------------------------
UBUNTU_CODENAME="${UBUNTU_CODENAME:-$(lsb_release -cs 2>/dev/null || echo "jammy")}"
ARCH="${ARCH:-$(dpkg --print-architecture 2>/dev/null || echo "amd64")}"
PYTHON_VERSION="${PYTHON_VERSION:-python3}"
