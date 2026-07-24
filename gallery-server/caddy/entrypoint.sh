#!/bin/sh
# Generate a self-signed TLS certificate on first boot, then start Caddy.
#
# In an airgapped network there is no path to Let's Encrypt, so we mint our
# own CA. The cert is exposed at https://<host>:8443/cert so client PCs can
# download and trust it (see OFFLINE-GUIDE.md).

set -eu

CERT_DIR="/data/caddy/pki"
CERT="$CERT_DIR/cert.pem"
KEY="$CERT_DIR/key.pem"

mkdir -p "$CERT_DIR"

HOST="${GALLERY_HOST:-100.252.201.200}"

if [ ! -f "$CERT" ] || [ ! -f "$KEY" ]; then
    echo "[caddy] Generating self-signed TLS certificate for host: $HOST"
    openssl req -x509 -newkey rsa:4096 -nodes \
        -keyout "$KEY" \
        -out "$CERT" \
        -days 3650 \
        -subj "/CN=$HOST" \
        -addext "subjectAltName=IP:$HOST,DNS:$HOST,DNS:localhost,IP:127.0.0.1,IP:100.252.201.200"
    chmod 644 "$CERT"
    chmod 600 "$KEY"
    echo "[caddy] Certificate written to $CERT"
else
    echo "[caddy] Reusing existing certificate at $CERT"
fi

echo "[caddy] Starting Caddy on :8443 (TLS) -> code-marketplace:3001"
exec caddy run --config /etc/caddy/Caddyfile --adapter caddyfile
