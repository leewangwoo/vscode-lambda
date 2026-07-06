#!/usr/bin/env bash
#
# Download packages from PyPI and upload them to the devpi server.
#
# Must be run from a machine WITH internet access.
# The devpi server itself may be on the internal network as long as
# this machine can reach it.
#
# Usage:
#   ./sync-packages.sh <requirements-file> [devpi-url]
#
# Example:
#   ./sync-packages.sh requirements-common.txt http://100.252.201.200:3141

set -euo pipefail

REQUIREMENTS="${1:?Usage: sync-packages.sh <requirements-file> [devpi-url]}"
DEVPI_URL="${2:-http://100.252.201.200:3141}"
TMPDIR="${TMPDIR:-/tmp/devpi-sync}"

if [ ! -f "$REQUIREMENTS" ]; then
    echo "❌ Requirements file not found: $REQUIREMENTS"
    exit 1
fi

echo "============================================"
echo "  devpi Package Synchronizer"
echo "============================================"
echo "  Source:  PyPI (internet)"
echo "  Target:  $DEVPI_URL"
echo "  Packages: $REQUIREMENTS"
echo "============================================"
echo ""

# Ensure devpi-client is installed
if ! command -v devpi &>/dev/null; then
    echo "Installing devpi-client..."
    pip install devpi-client
fi

# Configure devpi
devpi use "$DEVPI_URL"
echo "Please enter devpi credentials:"
devpi login admin
devpi use admin/staging

# Create temp directory
mkdir -p "$TMPDIR"
cd "$TMPDIR"

# Download all packages from PyPI
echo ""
echo "📥 Downloading packages from PyPI..."
pip download -r "$REQUIREMENTS" -d "$TMPDIR/downloads" \
    --index-url https://pypi.org/simple/

# Upload all downloaded packages to devpi
echo ""
echo "📤 Uploading packages to devpi..."
cd "$TMPDIR/downloads"

UPLOADED=0
FAILED=0

for pkg in *.whl *.tar.gz *.zip; do
    [ -e "$pkg" ] || continue
    echo "  Uploading: $pkg"
    if devpi upload "$pkg" 2>/dev/null; then
        UPLOADED=$((UPLOADED + 1))
    else
        echo "    ⚠️  Failed (may already exist): $pkg"
        FAILED=$((FAILED + 1))
    fi
done

echo ""
echo "============================================"
echo "  Sync Complete"
echo "  Uploaded: $UPLOADED"
echo "  Skipped/Failed: $FAILED"
echo "============================================"

# Cleanup
cd /
rm -rf "$TMPDIR/downloads"
