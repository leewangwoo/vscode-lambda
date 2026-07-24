#!/usr/bin/env bash
#
# Load Docker images (exported as tar by build-offline-image.bat) on the
# airgapped internal server and start all services.
#
# Usage (on the internal server):
#   ./load-offline-images.sh [image-dir]
#
# Example:
#   ./load-offline-images.sh ./offline-images

set -euo pipefail

INPUT_DIR="${1:-./offline-images}"

echo "============================================================"
echo "  Offline Docker Image Load (Internal Network)"
echo "============================================================"
echo "  Input dir: $INPUT_DIR"
echo ""

if [ ! -d "$INPUT_DIR" ]; then
    echo "ERROR: directory not found: $INPUT_DIR"
    echo "       Point this at the folder produced by build-offline-image.bat."
    exit 1
fi

LOADED=0
FAILED=0

for tar_file in "$INPUT_DIR"/*.tar; do
    [ -e "$tar_file" ] || continue
    name=$(basename "$tar_file")
    echo "Loading: $name"
    if docker load -i "$tar_file"; then
        echo "  OK"
        LOADED=$((LOADED + 1))
    else
        echo "  FAIL"
        FAILED=$((FAILED + 1))
    fi
    echo ""
done

echo "============================================================"
echo "  Loaded images:"
echo "============================================================"
docker images | grep -E "code-marketplace|lambda-gallery|jonasal/devpi-server" || true
echo ""

echo "============================================================"
echo "  Done: $LOADED loaded, $FAILED failed"
echo "============================================================"
echo ""
echo "  Next steps:"
echo "  1. Start the gallery:"
echo "       cd gallery-server && docker compose up -d"
echo "  2. Start devpi:"
echo "       cd devpi && docker compose up -d"
echo "  3. Publish extensions with scripts/publish.bat (or .sh)"
echo ""
