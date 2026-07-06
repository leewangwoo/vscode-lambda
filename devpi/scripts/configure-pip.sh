#!/usr/bin/env bash
#
# Configure pip to use the devpi private PyPI server (Linux/macOS).
#
# Usage:
#   ./configure-pip.sh [devpi-url] [index]
#
# Example:
#   ./configure-pip.sh http://100.252.201.200:3141
#   ./configure-pip.sh http://100.252.201.200:3141 admin/staging

set -euo pipefail

DEVPI_URL="${1:-http://100.252.201.200:3141}"
INDEX="${2:-root/pypi}"

DEVPI_URL="${DEVPI_URL%/}"
DEVPI_HOST=$(echo "$DEVPI_URL" | sed 's|https\?://||' | cut -d: -f1)
INDEX_URL="${DEVPI_URL}/${INDEX}/+simple/"
PIP_CONF_DIR="${HOME}/.pip"
PIP_CONF="${PIP_CONF_DIR}/pip.conf"

mkdir -p "$PIP_CONF_DIR"

cat > "$PIP_CONF" << EOF
[global]
index-url = ${INDEX_URL}
trusted-host = ${DEVPI_HOST}
timeout = 60

[install]
trusted-host = ${DEVPI_HOST}
EOF

echo "✅ pip configuration created: $PIP_CONF"
echo ""
echo "  index-url: ${INDEX_URL}"
echo "  trusted-host: ${DEVPI_HOST}"
echo ""
echo "You can now run: pip install <package-name>"
echo "It will use the devpi server at ${DEVPI_URL}"
