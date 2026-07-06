#!/usr/bin/env bash
#
# Download VS Code extensions from the public marketplace and publish
# them to the private gallery server.
#
# Must be run from a machine WITH internet access.
#
# Usage:
#   ./fetch-vscode-extensions.sh [gallery-url]
#
# Example:
#   ./fetch-vscode-extensions.sh http://100.252.201.200:8080

set -euo pipefail

GALLERY_URL="${1:-http://100.252.201.200:8080}"
TMPDIR="${TMPDIR:-/tmp/vsix-download}"

# Extensions to download (publisher.name)
EXTENSIONS=(
    "ms-python.python"
    "ms-python.vscode-pylance"
    "ms-python.debugpy"
    "ms-python.black-formatter"
    "ms-python.isort"
    "ms-vscode.powershell"
    "redhat.vscode-yaml"
    "ms-azuretools.vscode-docker"
    "ms-vscode-remote.remote-ssh"
)

echo "============================================"
echo "  VS Code Extension Downloader"
echo "============================================"
echo "  Source: marketplace.visualstudio.com"
echo "  Target: $GALLERY_URL"
echo "  Extensions: ${#EXTENSIONS[@]}"
echo "============================================"
echo ""

mkdir -p "$TMPDIR"
cd "$TMPDIR"

DOWNLOADED=0
FAILED=0

for ext in "${EXTENSIONS[@]}"; do
    publisher="${ext%%.*}"
    name="${ext#*.}"

    echo "📥 Downloading: $ext"

    # Download VSIX from marketplace
    url="https://marketplace.visualstudio.com/_apis/public/gallery/publishers/${publisher}/vsextensions/${name}/latest/vspackage"

    if curl -sL "$url" --output "${ext}.vsix.gz" --max-time 60; then
        # Decompress if gzipped
        if file "${ext}.vsix.gz" | grep -q "gzip"; then
            mv "${ext}.vsix.gz" "${ext}.vsix.gz.tmp"
            gzip -d -c "${ext}.vsix.gz.tmp" > "${ext}.vsix"
            rm "${ext}.vsix.gz.tmp"
        else
            mv "${ext}.vsix.gz" "${ext}.vsix"
        fi

        if [ -s "${ext}.vsix" ]; then
            echo "   ✅ Downloaded: $(du -h "${ext}.vsix" | cut -f1)"

            # Upload to gallery
            echo "   📤 Uploading to gallery..."
            response=$(curl -s -w "\n%{http_code}" \
                -X POST \
                -F "file=@${ext}.vsix" \
                "${GALLERY_URL}/api/upload")
            http_code=$(echo "$response" | tail -1)

            if [ "$http_code" = "200" ]; then
                echo "   ✅ Published to gallery"
                DOWNLOADED=$((DOWNLOADED + 1))
            else
                echo "   ⚠️  Upload failed (HTTP $http_code)"
                FAILED=$((FAILED + 1))
            fi
        else
            echo "   ⚠️  Empty file"
            FAILED=$((FAILED + 1))
        fi
    else
        echo "   ⚠️  Download failed"
        FAILED=$((FAILED + 1))
    fi
    echo ""
done

echo "============================================"
echo "  Complete: $DOWNLOADED downloaded, $FAILED failed"
echo "============================================"

# Cleanup
cd /
rm -rf "$TMPDIR"
