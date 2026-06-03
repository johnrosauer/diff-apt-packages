# diff-apt-packages

A lightweight, robust Bash tool to compare currently installed APT packages with default Ubuntu packages for your release version. 

It helps system administrators and developers audit systems by identifying precisely what packages have been **added** or **removed** since the base system installation.

## Features

- **Automated Manifest Resolution:**
  - Automatically locates and downloads the official release or cloud manifest from Canonical mirrors based on your detected Ubuntu version, codename, architecture, and installation mode.
  - Caches downloaded manifests locally in `~/.cache/diff-apt-packages/` for 24 hours to avoid network delays, with automatic fallback to stale cache files in case of network timeouts or offline mode.
- **Smart Mode Auto-Detection:**
  - Auto-detects whether the machine is running a **Desktop** environment, a standard **Server**, a **WSL** (Windows Subsystem for Linux) instance, or a virtualised **Cloud Image** minimal system.
- **Version-Insensitive Normalisation:**
  - By default, ignores minor/patch version differences in package names (e.g. treats `linux-headers-6.17` and `linux-headers-7.0` as the same package) to prevent transient kernel update noise from bloating the audit results.
- **Redirection-Friendly (Quiet Mode):**
  - Includes a quiet option (`-q`/`--quiet`) that suppresses all headers and download logs, printing only the raw package list to standard output—perfect for script pipes and redirects.
- **Interactive Console Explorer:**
  - Features an interactive menu to explore added and removed packages in columns (with terminal width auto-wrapping, customisable column widths via `-w`/`--width`, and long-line padding).
- **Shell Auto-Completion:**
  - Includes a Bash completion script to auto-complete options and arguments (such as modes and paths) at the command line.

---

## Installation

You can install `diff-apt-packages`, its Unix man page, and bash completion automatically using the provided `Makefile`:

```bash
# Clone the repository
git clone https://github.com/yourusername/diff-apt-packages.git
cd diff-apt-packages

# Build/install to /usr/local
sudo make install
```

Alternatively, you can build a standard Debian (`.deb`) package to install it via your system package manager:

```bash
# Build the .deb package
make deb

# Install the generated package
sudo apt install ./diff-apt-packages_*.deb
```

Or you can build and install a Snap package:

```bash
# Build the snap package
make snap

# Install the generated snap package (requires classic confinement)
sudo snap install --classic ./diff-apt-packages_*.snap
```

To remove the installation:

- If installed via `make install`:
  ```bash
  sudo make uninstall
  ```
- If installed via `.deb` package:
  ```bash
  sudo apt remove diff-apt-packages
  ```
- If installed via snap package:
  ```bash
  sudo snap remove diff-apt-packages
  ```

---

## Usage

### 1. Interactive Audit Summary
Run the command without arguments to get a summary table and open an interactive prompt:
```bash
diff-apt-packages
```

### 2. Export Added Packages (Redirection-Friendly)
Retrieve the list of added packages directly into a file without status headers or download logs:
```bash
diff-apt-packages -q -a > added_packages.list
```

### 3. Compare Exact Versions
Disable the default version-grouping logic to perform an exact audit (e.g., matching compiler major version packages exactly):
```bash
diff-apt-packages -k
```

### 4. Audit a Manifest Locally
Compare currently installed packages against a specific local manifest file backup:
```bash
diff-apt-packages -d /path/to/backup-manifest.manifest
```

### 5. Customise Column Width
Adjust the column width of the interactive explorer layout to suit your terminal or to prevent package names from being truncated:
```bash
diff-apt-packages -w 50
```

### 6. Create a Pre-Upgrade Manifest Backup
Generate a snapshot of currently installed packages in the standard Ubuntu manifest format:
```bash
diff-apt-packages -i > pre-upgrade.manifest
```
After performing a system upgrade, you can perform a custom audit of the upgrade's additions and removals using this snapshot:
```bash
diff-apt-packages -d pre-upgrade.manifest
```

---

## CLI Options

```text
Usage: diff-apt-packages [OPTIONS]

Compare installed APT packages against the default ones for this Ubuntu release.

Options:
  -m, --mode MODE          Force installation mode: desktop, server, wsl, cloud, auto
                           (Default: auto-detect)
  -d, --default-file PATH  Use a local manifest file instead of downloading
  -o, --output-dir PATH    Save raw package lists and differences to this directory
  -w, --width WIDTH        Column width for interactive layout (Default: 35)
  -i, --installed-manifest Output currently installed packages in manifest format
                           (Package\tVersion) to stdout and exit
  -c, --no-cache           Do not read from cached manifest (force download)
  -a, --show-added         Print list of added packages to stdout
  -r, --show-removed       Print list of removed packages to stdout
  -k, --keep-versions      Do not ignore version numbers in package names (e.g. treat
                           linux-headers-6.17 and linux-headers-7.0 as different packages)
  -q, --quiet              Suppress all status messages and header outputs
  -y, --non-interactive    Run in non-interactive mode (auto-detect everything, no prompts)
  -v, --version            Print script version and exit
  -h, --help               Show help message and exit
```

---

## Authors

- **John Rosauer** - *Main Author* - [john.rosauer@gmail.com](mailto:john.rosauer@gmail.com)
- **Antigravity** - *Co-Author*

---

## Licence

This project is licensed under the MIT Licence - see the [LICENCE](LICENCE) file for details.

