# Offline Ubuntu Toolkit

A clean, reusable system for downloading an entire development toolkit on an
online machine and installing it on an offline Ubuntu system.

---

## Files

```
offline-toolkit/
├── config.sh       ← EDIT THIS — all packages defined here
├── download.sh     ← Run on ONLINE machine
├── install.sh      ← Run on OFFLINE machine
├── store.sh        ← Offline search/info/selected APT installs
├── README.md
├── logs/           ← Auto-created; timestamped log per run
├── catalog/
│   └── apt/
│       └── closures/ ← One dependency closure file per configured APT package
└── packages/
    ├── apt/        ← .deb files + local APT index
    ├── pip/        ← Python wheels + requirements.txt
    ├── npm/        ← NPM tarballs
    ├── snap/       ← .snap + .assert pairs
    └── binaries/   ← Direct binary downloads (terraform, kubectl, etc.)
```

---

## Quick Start

### Step 1 — Customise (both machines need same Ubuntu version)

Edit `config.sh` to add or remove packages. That file is the only one you
need to touch for day-to-day maintenance.

### Step 2 — Download (online machine)

```bash
chmod +x download.sh install.sh store.sh
./download.sh
```

### Step 3 — Transfer

```bash
# USB / external drive
cp -r offline-toolkit/ /media/usb/

# Or over a temporary network connection
rsync -avz offline-toolkit/ user@offline-host:/home/user/offline-toolkit/

# Or zip it
tar -czf offline-toolkit.tar.gz offline-toolkit/
```

### Step 4 — Install (offline machine)

```bash
cd offline-toolkit/
sudo ./install.sh
```

Or use the offline store to install only selected APT packages:

```bash
cd offline-toolkit/
./store.sh search docker
./store.sh info docker.io
./store.sh version docker.io
./store.sh versions python
./store.sh deps docker.io
sudo ./store.sh install docker.io
sudo ./store.sh install git curl htop
sudo ./store.sh install --group python-dev
```

The store uses the local APT repository in `packages/apt` and asks `apt` to
resolve the selected package's dependencies. Before installing, it runs an APT
simulation against only the local store. If one selected package is missing a
dependency, the install stops before changing the system.

During download, the toolkit also writes one dependency closure file per APT
package under `catalog/apt/closures/`. For example:

```bash
./store.sh deps docker.io
cat catalog/apt/closures/docker.io.txt
```

---

## Command-Line Options

Both scripts support the same flags:

| Flag              | Effect                              |
|-------------------|-------------------------------------|
| `--apt-only`      | Only process APT packages           |
| `--skip-apt`      | Skip APT packages                   |
| `--skip-pip`      | Skip Python packages                |
| `--skip-npm`      | Skip NPM packages                   |
| `--skip-snap`     | Skip Snap packages                  |
| `--skip-binaries` | Skip direct binary downloads        |
| `--dry-run`       | (install only) preview without run  |
| `--help`          | Show usage                          |

Examples:
```bash
./download.sh --skip-snap --skip-binaries
sudo ./install.sh --dry-run
sudo ./install.sh --apt-only
```

`store.sh` commands:

| Command                         | Effect                                      |
|---------------------------------|---------------------------------------------|
| `./store.sh list`               | List local APT packages                     |
| `./store.sh search QUERY`       | Search local package names/descriptions     |
| `./store.sh info PACKAGE`       | Show version, arch, description, deps       |
| `./store.sh version PACKAGE`    | Show exact local package version            |
| `./store.sh versions [QUERY]`   | List exact local versions                   |
| `./store.sh deps PACKAGE`       | Show recorded dependency closure            |
| `./store.sh groups`             | Show curated groups from `config.sh`        |
| `./store.sh doctor PACKAGE...`  | Check selected packages and closures locally |
| `sudo ./store.sh install ...`   | Install selected packages only              |

Selected install examples:

```bash
sudo ./store.sh install --dry-run docker.io
sudo ./store.sh install --group dev-core
sudo ./store.sh install --group docker
sudo ./store.sh install --all
```

Version catalogs are also written during release builds:

```bash
cat catalog/apt/requested.tsv   # configured top-level packages
cat catalog/apt/packages.tsv    # every .deb in the local APT store
```

---

## Adding New Packages

Open `config.sh` and add to the relevant array:

```bash
# APT package
APT_PRODUCTIVITY+=(htop ncdu)

# APT offline store group
APT_STORE_GROUP_PACKAGES[my-tools]="git curl htop jq"
APT_STORE_GROUP_DESCRIPTIONS[my-tools]="My personal CLI tools"
APT_STORE_GROUPS+=(my-tools)

# Python package
PIP_PACKAGES+=(boto3)

# NPM package
NPM_PACKAGES+=(commitizen)

# Direct binary
BINARY_DOWNLOADS+=("helm|https://get.helm.sh/helm-v3.14.3-linux-amd64.tar.gz|helm.tar.gz")
```

Then re-run `./download.sh` — it will add the new files to the packages/ folder.

---

## Updating Existing Packages

Just re-run `./download.sh`. Newer `.deb` / `.whl` files will overwrite older
ones in the packages/ directories.

---

## Tips

- **Ubuntu version must match** between online and offline machines (e.g., both
  on 22.04 Jammy). Same architecture too (both `amd64`).
- **Build a separate toolkit per target Ubuntu release.** Ubuntu 22.04 uses
  `jammy`; Ubuntu 26.04 uses `resolute`. Do not use one APT bundle for both.
- **For selected installs, prefer `store.sh` over `dpkg -i`.** It lets APT
  calculate the exact dependency closure for each package from the local repo.
- **Logs** are saved to `logs/download_YYYYMMDD_HHMMSS.log` and
  `logs/install_YYYYMMDD_HHMMSS.log` for troubleshooting.
- **After install**, run `exec $SHELL` or open a new terminal to pick up PATH
  changes.
- **Docker** needs to be started manually after install:
  `sudo systemctl enable --now docker`
