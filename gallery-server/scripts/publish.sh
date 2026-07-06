#!/usr/bin/env bash
#
# Publish a VSIX to the gallery server via HTTP upload.
#
# Usage:
#   ./publish.sh <vsix-file> [gallery-url]
#
# Examples:
#   ./publish.sh ../lambda-chat-deploy/copilot-chat-999.1.0.vsix
#   ./publish.sh ../copilot-chat-999.1.0.vsix http://gallery.internal:8080
#

set -euo pipefail

VSIX_FILE="${1:?Usage: publish.sh <vsix-file> [gallery-url]}"
GALLERY_URL="${2:-http://localhost:8000}"

if [ ! -f "$VSIX_FILE" ]; then
    echo "❌ File not found: $VSIX_FILE"
    exit 1
fi

echo "📤 Publishing $VSIX_FILE to $GALLERY_URL ..."

RESPONSE=$(curl -s -w "\n%{http_code}" \
    -X POST \
    -F "file=@${VSIX_FILE}" \
    "${GALLERY_URL}/api/upload")

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | head -n -1)

if [ "$HTTP_CODE" = "200" ]; then
    echo "✅ Published successfully"
    echo "$BODY" | python3 -m json.tool 2>/dev/null || echo "$BODY"
else
    echo "❌ Failed (HTTP $HTTP_CODE)"
    echo "$BODY"
    exit 1
fi
