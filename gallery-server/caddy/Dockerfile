FROM caddy:2-alpine

# openssl is needed to generate the self-signed certificate on first boot.
RUN apk add --no-cache openssl

# Caddy configuration + startup logic that generates a self-signed cert
# (airgapped networks cannot reach Let's Encrypt).
COPY Caddyfile /etc/caddy/Caddyfile
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Where the self-signed cert lives so clients can fetch it via /cert.
RUN mkdir -p /data/caddy/pki

ENTRYPOINT ["/entrypoint.sh"]
