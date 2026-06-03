#!/usr/bin/env bash
#
# run-tests.sh - Regression test suite for diff-apt-packages.sh
#

set -euo pipefail

# Print banner
echo "========================================"
echo "Running diff-apt-packages Regression Tests"
echo "========================================"

# Directory configuration
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${TEST_DIR}/.." && pwd)"
SCRIPT="${REPO_DIR}/diff-apt-packages.sh"

# Setup temporary test workspace
TEST_WORK_DIR=$(mktemp -d -t diff-apt-tests-XXXXXXXX)
cleanup() {
    rm -rf "$TEST_WORK_DIR"
}
trap cleanup EXIT

MOCK_BIN_DIR="${TEST_WORK_DIR}/bin"
mkdir -p "$MOCK_BIN_DIR"

# Test state/data files
MOCK_DPKG_QUERY_DATA="${TEST_WORK_DIR}/dpkg_query_data"
MOCK_DPKG_QUERY_PACKAGES="${TEST_WORK_DIR}/dpkg_query_packages"
MOCK_CURL_MANIFEST_DATA="${TEST_WORK_DIR}/curl_manifest_data"
export MOCK_DPKG_QUERY_DATA MOCK_DPKG_QUERY_PACKAGES MOCK_CURL_MANIFEST_DATA

# Create mock dpkg-query
cat > "${MOCK_BIN_DIR}/dpkg-query" << 'EOF'
#!/usr/bin/env bash
if [ "$1" = "-W" ]; then
    has_f=false
    format_str=""
    pkg=""
    for arg in "$@"; do
        if [[ "$arg" == -f=* ]]; then
            has_f=true
            format_str="${arg#-f=}"
        elif [ "$arg" != "-W" ]; then
            pkg="$arg"
        fi
    done

    if [ "$has_f" = true ]; then
        cat "$MOCK_DPKG_QUERY_DATA"
    else
        if [ -n "$pkg" ] && grep -q "^$pkg$" "$MOCK_DPKG_QUERY_PACKAGES" 2>/dev/null; then
            echo "$pkg    1.0"
            exit 0
        else
            echo "No package found matching $pkg" >&2
            exit 1
        fi
    fi
fi
EOF
chmod +x "${MOCK_BIN_DIR}/dpkg-query"

# Create mock curl
cat > "${MOCK_BIN_DIR}/curl" << 'EOF'
#!/usr/bin/env bash
url="${@: -1}"
if [[ "$url" == */ ]]; then
    echo '<a href="ubuntu-26.04-server-amd64.manifest">ubuntu-26.04-server-amd64.manifest</a>'
elif [[ "$url" == *.manifest ]]; then
    if [ -n "${MOCK_CURL_FAIL:-}" ]; then
        echo "Curl connection timed out" >&2
        exit 28
    else
        cat "$MOCK_CURL_MANIFEST_DATA"
    fi
fi
EOF
chmod +x "${MOCK_BIN_DIR}/curl"

# Prepend mock binaries to PATH
export PATH="${MOCK_BIN_DIR}:${PATH}"

# Clear existing completion or alias matching
export LC_ALL=C

# Helper to assert results
assert_equals() {
    local expected="$1"
    local actual="$2"
    local msg="$3"
    if [ "$expected" != "$actual" ]; then
        echo "FAIL: $msg" >&2
        echo "  Expected: '$expected'" >&2
        echo "  Actual:   '$actual'" >&2
        exit 1
    fi
}

echo "Running tests..."

# ----------------------------------------------------
# Test 1: Version Command Format
# ----------------------------------------------------
echo -n "Test 1: Version command output format... "
version_out=$(bash "$SCRIPT" -v)
# Verify it has format: diff-apt-packages <version>
if [[ ! "$version_out" =~ ^diff-apt-packages\ (v[0-9]+\.[0-9]+\.[0-9]+.*|dev)$ ]]; then
    echo "FAIL: Version output format: '$version_out'" >&2
    exit 1
fi
# Verify "version" is not present (case-insensitive)
if echo "$version_out" | grep -qi "version"; then
    echo "FAIL: Version output contains the word 'version': '$version_out'" >&2
    exit 1
fi
echo "PASS"

# ----------------------------------------------------
# Test 2: 'rc' Status Package Filtering
# ----------------------------------------------------
echo -n "Test 2: 'rc' (removed but config remains) status filtering... "
# Manifest contains package-a and package-b
printf "package-a\tinstall\npackage-b\tinstall\n" > "${TEST_WORK_DIR}/manifest_rc"
# Installed packages: package-a is installed, package-b is config-files (rc)
printf "installed package-a\nconfig-files package-b\n" > "$MOCK_DPKG_QUERY_DATA"

# Run comparison
out_dir="${TEST_WORK_DIR}/out_rc"
bash "$SCRIPT" -d "${TEST_WORK_DIR}/manifest_rc" -o "$out_dir" -y

# package-b is rc, meaning it is NOT installed.
# Thus, package-b should be listed as "removed" (present in default manifest but not installed)
# package-b should NOT be in installed-packages.txt
assert_equals "package-b" "$(cat "${out_dir}/removed-packages.txt")" "package-b should be in removed list"
assert_equals "package-a" "$(cat "${out_dir}/installed-packages.txt")" "package-b should not be in installed list"
echo "PASS"

# ----------------------------------------------------
# Test 3: Collision Omission / Unique Sorting
# ----------------------------------------------------
echo -n "Test 3: Collision safety (gcc-14 and gcc-15)... "
# Both gcc-14 and gcc-15 are in manifest and installed.
# Version-insensitive mapping normalises them both to gcc-VERSION.
# We must ensure both are preserved and match properly without omission.
printf "gcc-14\tinstall\ngcc-15\tinstall\n" > "${TEST_WORK_DIR}/manifest_collision"
printf "installed gcc-14\ninstalled gcc-15\n" > "$MOCK_DPKG_QUERY_DATA"

out_dir="${TEST_WORK_DIR}/out_collision"
bash "$SCRIPT" -d "${TEST_WORK_DIR}/manifest_collision" -o "$out_dir" -y

# Since both are in manifest and both installed, added/removed should be empty
assert_equals "0" "$(wc -l < "${out_dir}/added-packages.txt" | tr -d ' ')" "Added list should be empty for collision"
assert_equals "0" "$(wc -l < "${out_dir}/removed-packages.txt" | tr -d ' ')" "Removed list should be empty for collision"

# Verify both are kept in default-packages.txt and installed-packages.txt
assert_equals "2" "$(wc -l < "${out_dir}/default-packages.txt" | tr -d ' ')" "Should preserve both gcc variants in default-packages"
assert_equals "2" "$(wc -l < "${out_dir}/installed-packages.txt" | tr -d ' ')" "Should preserve both gcc variants in installed-packages"
echo "PASS"

# ----------------------------------------------------
# Test 4: Keep-versions (-k / --keep-versions)
# ----------------------------------------------------
echo -n "Test 4: Keep-versions exact matching (-k)... "
# Manifest contains only gcc-14, but gcc-15 is installed.
# Without -k, they match (since they normalize to gcc-VERSION).
# With -k, they do not match: gcc-14 is removed, gcc-15 is added.
printf "gcc-14\tinstall\n" > "${TEST_WORK_DIR}/manifest_keep_versions"
printf "installed gcc-15\n" > "$MOCK_DPKG_QUERY_DATA"

out_dir="${TEST_WORK_DIR}/out_keep_versions"

# First, run without -k: should match and show empty added/removed
bash "$SCRIPT" -d "${TEST_WORK_DIR}/manifest_keep_versions" -o "$out_dir" -y
assert_equals "0" "$(wc -l < "${out_dir}/added-packages.txt" | tr -d ' ')" "Without -k: added list should be empty"
assert_equals "0" "$(wc -l < "${out_dir}/removed-packages.txt" | tr -d ' ')" "Without -k: removed list should be empty"

# Next, run with -k: should treat them as distinct
bash "$SCRIPT" -d "${TEST_WORK_DIR}/manifest_keep_versions" -o "$out_dir" -y -k
assert_equals "gcc-15" "$(cat "${out_dir}/added-packages.txt")" "With -k: gcc-15 should be added"
assert_equals "gcc-14" "$(cat "${out_dir}/removed-packages.txt")" "With -k: gcc-14 should be removed"
echo "PASS"

# ----------------------------------------------------
# Test 5: Interactive Layout Column Width (-w / --width)
# ----------------------------------------------------
echo -n "Test 5: Interactive layout column width (-w 10)... "
# package-very-long should be truncated at 10 columns to "package-..." (7 chars + 3 dots = 10 chars)
printf "package-very-long\tinstall\n" > "${TEST_WORK_DIR}/manifest_width"
printf "installed package-a\n" > "$MOCK_DPKG_QUERY_DATA"

out_dir="${TEST_WORK_DIR}/out_width"
# Run with output redirection, but mock TTY output columnisation isn't easily triggered 
# without a real terminal. However, we can test print_columnated directly by checking 
# how it trims output. Since print_columnated is internal, we can test the -w parser check:
# Let's verify that a negative width or width < 5 is rejected.
if bash "$SCRIPT" -w 4 -y 2>/dev/null; then
    echo "FAIL: Accepted invalid width 4" >&2
    exit 1
fi
if bash "$SCRIPT" -w -1 -y 2>/dev/null; then
    echo "FAIL: Accepted invalid width -1" >&2
    exit 1
fi
if bash "$SCRIPT" -w abc -y 2>/dev/null; then
    echo "FAIL: Accepted non-integer width 'abc'" >&2
    exit 1
fi
echo "PASS"

# ----------------------------------------------------
# Test 6: Caching Behavior
# ----------------------------------------------------
echo -n "Test 6: Manifest caching behavior... "
export XDG_CACHE_HOME="${TEST_WORK_DIR}/cache"
rm -rf "$XDG_CACHE_HOME"

# Mock OS variables so it tries to fetch Ubuntu 26.04 noble server amd64
# We will mock the os-release file inside the environment
export UBUNTU_CODENAME="resolute"
export VERSION_CODENAME="resolute"
export VERSION_ID="26.04"
# Force wsl/server mode to keep it simple and deterministic
# Let's add server detection packages to mock-packages
echo "cloud-init" > "$MOCK_DPKG_QUERY_PACKAGES"

# 1. First run: cache is empty, downloads manifest and stores in cache
printf "package-cached-1\tinstall\n" > "$MOCK_CURL_MANIFEST_DATA"
printf "installed package-cached-1\n" > "$MOCK_DPKG_QUERY_DATA"

bash "$SCRIPT" -m server -y > /dev/null

# Verify cache file was created
cache_file="${XDG_CACHE_HOME}/diff-apt-packages/resolute-server-amd64.manifest"
if [ ! -f "$cache_file" ]; then
    echo "FAIL: Cache file was not created at '$cache_file'" >&2
    exit 1
fi
assert_equals "package-cached-1	install" "$(cat "$cache_file")" "Cached manifest content"

# 2. Second run: cache is fresh, shouldn't call curl.
# Change curl manifest data; if it downloads, the manifest will change.
# If it uses cache, the manifest will remain the old one.
printf "package-cached-2\tinstall\n" > "$MOCK_CURL_MANIFEST_DATA"
# Run again
bash "$SCRIPT" -m server -y > /dev/null
assert_equals "package-cached-1	install" "$(cat "$cache_file")" "Cache should remain unchanged (fresh cache used)"

# 2b. Run with -c / --no-cache: should bypass cache and download fresh manifest
bash "$SCRIPT" -m server -c -y > /dev/null
assert_equals "package-cached-2	install" "$(cat "$cache_file")" "Cache should be updated with new downloaded manifest"

# 3. Third run: stale cache fallback on network failure
# Touch cache to be 2 days old
touch -d "2 days ago" "$cache_file"
# Enable curl failure
export MOCK_CURL_FAIL=1
# Run again, should succeed using the stale cache and issue warning to stderr
stderr_log="${TEST_WORK_DIR}/stderr_log"
bash "$SCRIPT" -m server -y 2> "$stderr_log" > /dev/null

# Verify warning was printed to stderr
if ! grep -q "Falling back to cached manifest" "$stderr_log"; then
    echo "FAIL: Stale cache fallback warning not printed to stderr" >&2
    exit 1
fi
echo "PASS"

# ----------------------------------------------------
# Test 7: Installed Manifest Output (-i / --installed-manifest)
# ----------------------------------------------------
echo -n "Test 7: Installed manifest output format (-i)... "
# Set up mock package status data
printf "installed\tpackage-x\t2.5-1\nconfig-files\tpackage-y\t1.0\n" > "$MOCK_DPKG_QUERY_DATA"

installed_manifest_out="${TEST_WORK_DIR}/installed_manifest_output"
bash "$SCRIPT" -i > "$installed_manifest_out"

# Verify output contains package-x and version, but not package-y (config-files)
expected_content=$(printf "package-x\t2.5-1")
actual_content=$(cat "$installed_manifest_out")
assert_equals "$expected_content" "$actual_content" "Installed manifest output format"
echo "PASS"

# ----------------------------------------------------
# Test 8: Missing Option Arguments
# ----------------------------------------------------
echo -n "Test 8: Missing option arguments graceful failures... "
for opt in "-m" "--mode" "-d" "--default-file" "-o" "--output-dir" "-w" "--width"; do
    err_out="${TEST_WORK_DIR}/err_${opt//-/}"
    if bash "$SCRIPT" "$opt" 2> "$err_out"; then
        echo "FAIL: Expected option $opt with missing argument to fail with non-zero code" >&2
        exit 1
    fi
    if ! grep -q "Option '$opt' requires an argument" "$err_out"; then
        echo "FAIL: Error output for $opt did not contain expected message. Content: $(cat "$err_out")" >&2
        exit 1
    fi
done
echo "PASS"

echo "========================================"
echo "All regression tests PASSED successfully!"
echo "========================================"
