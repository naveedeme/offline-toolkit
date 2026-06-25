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
├── README.md
├── logs/           ← Auto-created; timestamped log per run
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
chmod +x download.sh install.sh
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

---

## Adding New Packages

Open `config.sh` and add to the relevant array:

```bash
# APT package
APT_PRODUCTIVITY+=(htop ncdu)

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
- **Logs** are saved to `logs/download_YYYYMMDD_HHMMSS.log` and
  `logs/install_YYYYMMDD_HHMMSS.log` for troubleshooting.
- **After install**, run `exec $SHELL` or open a new terminal to pick up PATH
  changes.
- **Docker** needs to be started manually after install:
  `sudo systemctl enable --now docker`
