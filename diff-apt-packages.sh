#!/usr/bin/env bash
#
# diff-apt-packages.sh - Compare currently installed APT packages with default Ubuntu ones.
#
# Detects added and removed packages compared to the default installation of the running version.
# Reads local installer log if available, or downloads official manifests from Ubuntu servers.
#
# Created: 2026-05-29
# Authors: John Rosauer <john.rosauer@gmail.com> and Antigravity
#

# Exit on error, undefined vars, or pipeline failures
set -euo pipefail

# Style definitions for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Helper for conditional coloring (only if stdout is a terminal)
if [ ! -t 1 ]; then
    RED="" GREEN="" YELLOW="" BLUE="" BOLD="" NC=""
fi

# Temp file cleanup on exit
TMP_DIR=$(mktemp -d -t diff-apt-XXXXXXXX)
cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

# Version resolution with build-time substitution and runtime Git fallback
SCRIPT_VERSION="@VERSION@"
if [ "$SCRIPT_VERSION" = "@"VERSION"@" ]; then
    SCRIPT_VERSION=$(git -C "$(dirname "${BASH_SOURCE[0]}")" describe --tags --always --dirty 2>/dev/null || echo "dev")
fi

# Print usage info
usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Compare installed APT packages against the default ones for this Ubuntu release.

Options:
  -m, --mode MODE          Force installation mode: desktop, server, wsl, cloud, auto
                           (Default: auto-detect)
  -d, --default-file PATH  Use a local manifest file instead of downloading
  -o, --output-dir PATH    Save raw package lists and differences to this directory
  -w, --width WIDTH        Column width for interactive layout (Default: 35)
  -i, --installed-manifest Output currently installed packages in manifest format
                           (Package\tVersion) to stdout and exit
  -a, --show-added         Print list of added packages to stdout
  -r, --show-removed       Print list of removed packages to stdout
  -k, --keep-versions      Do not ignore version numbers in package names (e.g. treat
                           linux-headers-6.17 and linux-headers-7.0 as different packages)
  -q, --quiet              Suppress all status messages and header outputs
  -y, --non-interactive    Run in non-interactive mode (auto-detect everything, no prompts)
  -v, --version            Print script version and exit
  -h, --help               Show help message and exit

Description:
  This script compares packages installed on the system against the original set
  of packages that come with the corresponding Ubuntu installation.
  
  By default, it will detect the Ubuntu codename, fetch the official manifest
  from the Ubuntu releases or cloud-images servers, auto-detect the installation
  flavor (Desktop, Server, WSL, or Cloud Image), and compute the diff.
EOF
    exit 0
}

# Defaults
MODE="auto"
LOCAL_MANIFEST=""
OUTPUT_DIR=""
COLUMN_WIDTH=35
DUMP_MANIFEST=false
SHOW_ADDED=false
SHOW_REMOVED=false
KEEP_VERSIONS=false
QUIET=false
NON_INTERACTIVE=false

# Parse args
while [[ $# -gt 0 ]]; do
    case "$1" in
        -m|--mode)
            MODE="$2"
            shift 2
            ;;
        -d|--default-file)
            LOCAL_MANIFEST="$2"
            shift 2
            ;;
        -o|--output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -w|--width)
            COLUMN_WIDTH="$2"
            if ! [[ "$COLUMN_WIDTH" =~ ^[0-9]+$ ]] || [ "$COLUMN_WIDTH" -lt 5 ]; then
                echo -e "${RED}Error: Width must be an integer of at least 5.${NC}" >&2
                exit 1
            fi
            shift 2
            ;;
        -i|--installed-manifest)
            DUMP_MANIFEST=true
            shift 1
            ;;
        -a|--show-added)
            SHOW_ADDED=true
            shift 1
            ;;
        -r|--show-removed)
            SHOW_REMOVED=true
            shift 1
            ;;
        -k|--keep-versions)
            KEEP_VERSIONS=true
            shift 1
            ;;
        -q|--quiet)
            QUIET=true
            shift 1
            ;;
        -y|--non-interactive)
            NON_INTERACTIVE=true
            shift 1
            ;;
        -v|--version)
            echo "diff-apt-packages $SCRIPT_VERSION"
            exit 0
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo -e "${RED}Error: Unknown option '$1'${NC}" >&2
            echo "Run '$(basename "$0") --help' for details." >&2
            exit 1
            ;;
    esac
done

if [ "$DUMP_MANIFEST" = true ]; then
    dpkg-query -W -f='${db:Status-Status}\t${Package}\t${Version}\n' | tr -d '\r' | grep -vE '^(not-installed|config-files)[[:space:]]' | cut -f2-
    exit 0
fi

# Detect environment: desktop, wsl, cloud, server
detect_environment() {
    # 1. Check for WSL
    if grep -qi microsoft /proc/version 2>/dev/null; then
        echo "wsl"
        return
    fi
    # 2. Check for Desktop (graphical packages installed)
    local pkg
    for pkg in gnome-shell ubuntu-desktop lightdm gdm3 xorg; do
        if dpkg-query -W "$pkg" >/dev/null 2>&1; then
            echo "desktop"
            return
        fi
    done
    # 3. Check for Cloud
    if dpkg-query -W cloud-init >/dev/null 2>&1; then
        echo "cloud"
        return
    fi
    # Default to server
    echo "server"
}

# Look up manifest URL online
find_online_manifest_url() {
    local version="$1"
    local codename="$2"
    local mode="$3"
    local arch="$4"

    local urls=()
    urls+=("https://releases.ubuntu.com/${version}/")
    urls+=("https://releases.ubuntu.com/${codename}/")
    urls+=("https://cloud-images.ubuntu.com/${codename}/current/")
    urls+=("https://cloud-images.ubuntu.com/releases/${codename}/release/")

    local fallback_manifest=""
    local fallback_base_url=""

    for base_url in "${urls[@]}"; do
        # Fetch the HTML index with timeouts to prevent hanging
        local html
        if ! html=$(curl -sfL --max-time 10 --connect-timeout 5 "$base_url" 2>/dev/null); then
            continue
        fi

        # Find manifests from hrefs
        local manifests
        manifests=$(echo "$html" | grep -oE 'href="[^"]+\.manifest"' | cut -d'"' -f2 || true)

        if [ -z "$manifests" ]; then
            continue
        fi

        # Filter by architecture
        local arch_manifests
        arch_manifests=$(echo "$manifests" | grep "$arch" || true)
        if [ -z "$arch_manifests" ]; then
            continue
        fi

        # Match by mode
        local target_manifest=""
        if [ "$mode" = "desktop" ]; then
            target_manifest=$(echo "$arch_manifests" | grep "desktop" | head -n 1 || true)
        elif [ "$mode" = "wsl" ]; then
            target_manifest=$(echo "$arch_manifests" | grep "wsl" | head -n 1 || true)
        elif [ "$mode" = "cloud" ]; then
            target_manifest=$(echo "$arch_manifests" | grep -E "cloudimg|minimal" | head -n 1 || true)
        else
            # server
            target_manifest=$(echo "$arch_manifests" | grep -E "server|live-server" | head -n 1 || true)
        fi

        if [ -n "$target_manifest" ]; then
            # Resolve relative URL if needed
            if [[ "$target_manifest" =~ ^https?:// ]]; then
                echo "$target_manifest"
            else
                echo "${base_url%/}/${target_manifest#/}"
            fi
            return 0
        fi

        # Keep track of the first available architecture manifest as a fallback
        if [ -z "$fallback_manifest" ]; then
            fallback_manifest=$(echo "$arch_manifests" | head -n 1)
            fallback_base_url="$base_url"
        fi
    done

    # If no mode-specific manifest was found, use the fallback
    if [ -n "$fallback_manifest" ]; then
        if [[ "$fallback_manifest" =~ ^https?:// ]]; then
            echo "$fallback_manifest"
        else
            echo "${fallback_base_url%/}/${fallback_manifest#/}"
        fi
        return 0
    fi

    return 1
}

# Step 1: Detect OS information
if [ -f /etc/os-release ]; then
    . /etc/os-release
else
    echo -e "${RED}Error: /etc/os-release not found. This script only supports Debian/Ubuntu-based systems.${NC}" >&2
    exit 1
fi

if [ "$ID" != "ubuntu" ] && [ "${ID_LIKE:-}" != "ubuntu" ]; then
    echo -e "${YELLOW}Warning: This system does not appear to be Ubuntu. Proceeding with caution...${NC}" >&2
fi

CODENAME="${UBUNTU_CODENAME:-$VERSION_CODENAME}"
VERSION="${VERSION_ID:-}"
ARCH=$(dpkg --print-architecture)

# Resolve mode and default package source type before printing
DETECTED_MODE=""
if [ -n "$LOCAL_MANIFEST" ]; then
    SELECTED_MODE="local file ($LOCAL_MANIFEST)"
else
    if [ "$MODE" = "auto" ]; then
        DETECTED_MODE=$(detect_environment)
        SELECTED_MODE="$DETECTED_MODE (auto-detected)"
    else
        DETECTED_MODE="$MODE"
        SELECTED_MODE="$DETECTED_MODE (forced)"
    fi
fi

if [ "$QUIET" = false ]; then
    echo -e "${BLUE}OS Release:${NC} ${BOLD}Ubuntu ${VERSION:-(unknown)} (${CODENAME:-(unknown)})${NC}" >&2
    echo -e "${BLUE}Architecture:${NC} ${BOLD}${ARCH}${NC}" >&2
    echo -e "${BLUE}Selected Mode:${NC} ${BOLD}${SELECTED_MODE}${NC}" >&2
fi

# Step 2: Establish original package source
DEFAULT_SOURCE=""
DEFAULT_LIST_FILE="${TMP_DIR}/defaults.txt"

# Try user-supplied file first
if [ -n "$LOCAL_MANIFEST" ]; then
    if [ ! -f "$LOCAL_MANIFEST" ]; then
        echo -e "${RED}Error: Specified file '$LOCAL_MANIFEST' does not exist.${NC}" >&2
        exit 1
    fi
    if [ ! -r "$LOCAL_MANIFEST" ]; then
        echo -e "${RED}Error: Specified file '$LOCAL_MANIFEST' is not readable.${NC}" >&2
        exit 1
    fi
    
    # Parse local manifest file (supports gzipped files)
    if [[ "$LOCAL_MANIFEST" =~ \.gz$ ]]; then
        gzip -dc "$LOCAL_MANIFEST" | tr -d '\r' | awk '{print $1}' | sed -E 's/:[a-zA-Z0-9_-]+$//' | LC_ALL=C sort -u > "$DEFAULT_LIST_FILE"
    else
        tr -d '\r' < "$LOCAL_MANIFEST" | awk '{print $1}' | sed -E 's/:[a-zA-Z0-9_-]+$//' | LC_ALL=C sort -u > "$DEFAULT_LIST_FILE"
    fi
    DEFAULT_SOURCE="Local file: $LOCAL_MANIFEST"
fi

# Download manifest if no source found yet
if [ -z "$DEFAULT_SOURCE" ]; then
    # Determine local cache path (respects XDG Base Directory Specification)
    CACHE_DIR=""
    if [ -n "${XDG_CACHE_HOME:-}" ]; then
        CACHE_DIR="$XDG_CACHE_HOME/diff-apt-packages"
    elif [ -n "${HOME:-}" ]; then
        CACHE_DIR="$HOME/.cache/diff-apt-packages"
    else
        CACHE_DIR="/tmp/diff-apt-packages-cache"
    fi
    
    # Construct standard cache filename based on release metadata (e.g., resolute-desktop-amd64.manifest)
    CACHE_FILE="${CACHE_DIR}/${CODENAME}-${DETECTED_MODE}-${ARCH}.manifest"
    
    USE_CACHE=false
    if [ -f "$CACHE_FILE" ]; then
        # Check if the cache is older than 24 hours (1440 minutes)
        if [ -z "$(find "$CACHE_FILE" -mmin +1440 2>/dev/null)" ]; then
            USE_CACHE=true
        fi
    fi

    if [ "$USE_CACHE" = true ]; then
        if [ "$QUIET" = false ]; then
            echo -e "${BLUE}Using cached manifest:${NC} ${BOLD}$CACHE_FILE${NC}" >&2
        fi
        cp "$CACHE_FILE" "${TMP_DIR}/manifest.raw"
        DEFAULT_SOURCE="Cached online manifest ($CACHE_FILE)"
    else
        # Locate manifest URL (only if cache is missing/expired)
        if [ "$QUIET" = false ]; then
            echo -e "${BLUE}Locating online manifest file...${NC}" >&2
        fi
        MANIFEST_URL=$(find_online_manifest_url "$VERSION" "$CODENAME" "$DETECTED_MODE" "$ARCH")

        if [ -z "$MANIFEST_URL" ]; then
            # If search fails, check if we have a stale cache file to fall back to
            if [ -f "$CACHE_FILE" ]; then
                if [ "$QUIET" = false ]; then
                    echo -e "${YELLOW}Warning: Could not locate online manifest URL. Falling back to cached manifest.${NC}" >&2
                fi
                cp "$CACHE_FILE" "${TMP_DIR}/manifest.raw"
                DEFAULT_SOURCE="Cached online manifest ($CACHE_FILE)"
            else
                echo -e "${RED}Error: Could not locate a default manifest file for Ubuntu $VERSION ($CODENAME) / $DETECTED_MODE / $ARCH.${NC}" >&2
                echo "Please specify a manifest manually using the -d/--default-file option." >&2
                exit 1
            fi
        else
            if [ "$QUIET" = false ]; then
                echo -e "${BLUE}Downloading manifest:${NC} ${BOLD}$MANIFEST_URL${NC}" >&2
            fi
            if ! curl -sfL --max-time 30 "$MANIFEST_URL" > "${TMP_DIR}/manifest.raw"; then
                # If download fails, check if we have a stale cache file to fall back to
                if [ -f "$CACHE_FILE" ]; then
                    if [ "$QUIET" = false ]; then
                        echo -e "${YELLOW}Warning: Download failed. Falling back to cached manifest.${NC}" >&2
                    fi
                    cp "$CACHE_FILE" "${TMP_DIR}/manifest.raw"
                    DEFAULT_SOURCE="Cached online manifest ($CACHE_FILE)"
                else
                    echo -e "${RED}Error: Failed to download manifest from $MANIFEST_URL${NC}" >&2
                    exit 1
                fi
            else
                # Save downloaded manifest to cache
                mkdir -p "$CACHE_DIR"
                cp "${TMP_DIR}/manifest.raw" "$CACHE_FILE"
                DEFAULT_SOURCE="Online manifest ($MANIFEST_URL)"
            fi
        fi
    fi

    tr -d '\r' < "${TMP_DIR}/manifest.raw" | awk '{print $1}' | sed -E 's/:[a-zA-Z0-9_-]+$//' | LC_ALL=C sort -u > "$DEFAULT_LIST_FILE"
fi

# Step 3: Extract current packages
CURRENT_LIST_FILE="${TMP_DIR}/current.txt"
dpkg-query -W -f='${db:Status-Status} ${Package}\n' | tr -d '\r' | grep -vE '^(not-installed|config-files) ' | cut -d' ' -f2 | sed -E 's/:[a-zA-Z0-9_-]+$//' | LC_ALL=C sort -u > "$CURRENT_LIST_FILE"

# Step 4: Compare lists
ADDED_FILE="${TMP_DIR}/added.txt"
REMOVED_FILE="${TMP_DIR}/removed.txt"

if [ "$KEEP_VERSIONS" = true ]; then
    # Simple architecture-stripped comparison (exact package names)
    LC_ALL=C comm -23 "$CURRENT_LIST_FILE" "$DEFAULT_LIST_FILE" > "$ADDED_FILE"
    LC_ALL=C comm -13 "$CURRENT_LIST_FILE" "$DEFAULT_LIST_FILE" > "$REMOVED_FILE"
else
    # Version-insensitive comparison:
    # 1. Normalize version numbers to -VERSION in temp files
    # 2. Paste normalized name and original name: <norm> <orig>
    # 3. Sort by normalized name for join
    
    normalize_and_map() {
        local src="$1"
        local dest_mapped="$2"
        local dest_names="$3"
        local suffix
        suffix=$(basename "$src")
        local norm_tmp="${TMP_DIR}/norm_${suffix}.txt"
        
        # Replace versions using sed
        tr -d '\r' < "$src" | sed -E '
            s/-[0-9]+\.[0-9]+\.[0-9]+-[0-9]+-generic\b/-VERSION-generic/g;
            s/-[0-9]+\.[0-9]+\.[0-9]+-[0-9]+\b/-VERSION/g;
            s/-[0-9]+(\.[0-9]+)?-(dev|generic|common|base|doc|docs|dbg|utils|libs)\b/-VERSION-\2/g;
            s/-[0-9]+(\.[0-9]+)?$/-VERSION/g
        ' > "$norm_tmp"
        
        paste -d' ' "$norm_tmp" "$src" | LC_ALL=C sort -k1,1 > "$dest_mapped"
        awk '{print $1}' "$dest_mapped" | LC_ALL=C sort -u > "$dest_names"
    }
    
    normalize_and_map "$DEFAULT_LIST_FILE" "${TMP_DIR}/def_mapped.txt" "${TMP_DIR}/def_names.txt"
    normalize_and_map "$CURRENT_LIST_FILE" "${TMP_DIR}/cur_mapped.txt" "${TMP_DIR}/cur_names.txt"
    
    # Compare normalized names
    LC_ALL=C comm -23 "${TMP_DIR}/cur_names.txt" "${TMP_DIR}/def_names.txt" > "${TMP_DIR}/add_names.txt"
    LC_ALL=C comm -13 "${TMP_DIR}/cur_names.txt" "${TMP_DIR}/def_names.txt" > "${TMP_DIR}/rem_names.txt"
    
    # Map back to original package names using join
    LC_ALL=C join -o 1.2 "${TMP_DIR}/cur_mapped.txt" "${TMP_DIR}/add_names.txt" | LC_ALL=C sort -u > "$ADDED_FILE"
    LC_ALL=C join -o 1.2 "${TMP_DIR}/def_mapped.txt" "${TMP_DIR}/rem_names.txt" | LC_ALL=C sort -u > "$REMOVED_FILE"
fi

# Count statistics
NUM_DEFAULT=$(wc -l < "$DEFAULT_LIST_FILE")
NUM_CURRENT=$(wc -l < "$CURRENT_LIST_FILE")
NUM_ADDED=$(wc -l < "$ADDED_FILE")
NUM_REMOVED=$(wc -l < "$REMOVED_FILE")

# Handle output formats
if [ "$SHOW_ADDED" = true ] && [ "$SHOW_REMOVED" = true ]; then
    # Output both lists simply
    cat "$ADDED_FILE"
    cat "$REMOVED_FILE"
    exit 0
elif [ "$SHOW_ADDED" = true ]; then
    cat "$ADDED_FILE"
    exit 0
elif [ "$SHOW_REMOVED" = true ]; then
    cat "$REMOVED_FILE"
    exit 0
fi

# Print human-readable summary
if [ "$QUIET" = false ]; then
    echo -e "\n${BOLD}=== Package Difference Summary ===${NC}"
    echo -e "${BLUE}Default Source:${NC}  $DEFAULT_SOURCE"
    echo -e "${BLUE}Default Packages:${NC} $NUM_DEFAULT"
    echo -e "${BLUE}Current Packages:${NC} $NUM_CURRENT"
    echo -e "${GREEN}Added Packages:${NC}   $NUM_ADDED"
    echo -e "${RED}Removed Packages:${NC} $NUM_REMOVED"
    echo -e "${BOLD}==================================${NC}\n"
fi

# Output files if requested
if [ -n "$OUTPUT_DIR" ]; then
    mkdir -p "$OUTPUT_DIR"
    cp "$DEFAULT_LIST_FILE" "${OUTPUT_DIR}/default-packages.txt"
    cp "$CURRENT_LIST_FILE" "${OUTPUT_DIR}/installed-packages.txt"
    cp "$ADDED_FILE" "${OUTPUT_DIR}/added-packages.txt"
    cp "$REMOVED_FILE" "${OUTPUT_DIR}/removed-packages.txt"
    if [ "$QUIET" = false ]; then
        echo -e "${BLUE}Saved package lists and differences to:${NC} ${BOLD}$OUTPUT_DIR/${NC}"
        echo -e "  - ${BOLD}default-packages.txt${NC} (original packages)"
        echo -e "  - ${BOLD}installed-packages.txt${NC} (currently installed packages)"
        echo -e "  - ${BOLD}added-packages.txt${NC} (packages that were added)"
        echo -e "  - ${BOLD}removed-packages.txt${NC} (packages that were removed)"
    fi
fi

# Helper to print lists in columns, truncating extremely long names for formatting
print_columnated() {
    local file="$1"
    # If the file has entries, format it in columns only if stdout is a TTY (terminal)
    if [ -s "$file" ]; then
        if [ -t 1 ]; then
            awk -v w="$COLUMN_WIDTH" '{ if (length($0) > w) print substr($0, 1, w - 3) "..."; else print $0 }' "$file" | column || cat "$file"
        else
            cat "$file"
        fi
    fi
}

# Interactive review
if [ "$NON_INTERACTIVE" = false ] && [ -t 0 ]; then
    while true; do
        echo -n -e "Would you like to list the details? [a]dded, [r]emoved, [b]oth, or [q]uit: "
        read -r choice
        case "$choice" in
            a|added)
                echo -e "\n${GREEN}--- Added Packages ($NUM_ADDED) ---${NC}"
                print_columnated "$ADDED_FILE"
                echo ""
                ;;
            r|removed)
                echo -e "\n${RED}--- Removed Packages ($NUM_REMOVED) ---${NC}"
                print_columnated "$REMOVED_FILE"
                echo ""
                ;;
            b|both)
                echo -e "\n${GREEN}--- Added Packages ($NUM_ADDED) ---${NC}"
                print_columnated "$ADDED_FILE"
                echo -e "\n${RED}--- Removed Packages ($NUM_REMOVED) ---${NC}"
                print_columnated "$REMOVED_FILE"
                echo ""
                ;;
            q|quit|exit)
                break
                ;;
            *)
                echo "Invalid choice. Please select 'a', 'r', 'b', or 'q'."
                ;;
        esac
    done
fi
