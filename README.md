# diff-apt-packages

A lightweight, robust Bash tool to compare currently installed APT packages with default Ubuntu packages for your release version. 

It helps system administrators and developers audit systems by identifying precisely what packages have been **added** or **removed** since the base system installation.

## Features

- **Automated Manifest Resolution:**
  - Automatically queries the local installer database (`/var/log/installer/initial-status.gz`) for an exact record of what was pre-installed on this machine.
  - Gracefully falls back to downloading the official release/cloud manifest from Canonical mirrors based on your detected Ubuntu version, codename, architecture, and installation mode.
- **Smart Mode Auto-Detection:**
  - Auto-detects whether the machine is running a **Desktop** environment, a standard **Server**, a **WSL** (Windows Subsystem for Linux) instance, or a virtualized **Cloud Image** minimal system.
- **Version-Insensitive Normalization:**
  - By default, ignores minor/patch version differences in package names (e.g. treats `linux-headers-6.17` and `linux-headers-7.0` as the same package) to prevent transient kernel update noise from bloating the audit results.
- **Redirection-Friendly (Quiet Mode):**
  - Includes a quiet option (`-q`/`--quiet`) that suppresses all headers and download logs, printing only the raw package list to standard output—perfect for script pipes and redirects.
- **Interactive Console Explorer:**
  - Features an interactive menu to explore added and removed packages in columns (with terminal width auto-wrapping and long-line padding).

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

To remove the installation:
```bash
sudo make uninstall
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
diff-apt-packages -q -s > added_packages.list
```

### 3. Compare Exact Versions
Disable the default version-grouping logic to perform an exact audit (e.g., matching compiler major version packages exactly):
```bash
diff-apt-packages -k
```

### 4. Audit a Manifest Locally
Compare currently installed packages against a specific local manifest file or `initial-status.gz` backup:
```bash
diff-apt-packages -d /path/to/backup-manifest.manifest
```

---

## CLI Options

```text
Usage: diff-apt-packages [OPTIONS]

Compare installed APT packages against the default ones for this Ubuntu release.

Options:
  -m, --mode MODE          Force installation mode: desktop, server, wsl, cloud, auto
                           (Default: auto-detect)
  -d, --default-file PATH  Use a local manifest file or initial-status.gz instead of downloading
  -o, --output-dir PATH    Save raw package lists and differences to this directory
  -s, --show-added         Print list of added packages to stdout
  -r, --show-removed       Print list of removed packages to stdout
  -k, --keep-versions      Do not ignore version numbers in package names (e.g. treat
                           linux-headers-6.17 and linux-headers-7.0 as different packages)
  -q, --quiet              Suppress all status messages and header outputs
  -y, --non-interactive    Run in non-interactive mode (auto-detect everything, no prompts)
  -h, --help               Show help message and exit
```

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
