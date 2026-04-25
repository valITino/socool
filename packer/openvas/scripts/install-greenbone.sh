#!/usr/bin/env bash
# packer/openvas/scripts/install-greenbone.sh — Greenbone Community
# Containers install (docker-compose stack).

set -euo pipefail

COMPOSE_URL="${SOCOOL_GREENBONE_COMPOSE_URL:?compose url required}"
GREENBONE_DIR="/opt/greenbone"

# ─── Docker Engine (Debian/Ubuntu official repo) ───────────────────
echo "[install-greenbone] installing Docker..."
apt-get update
apt-get install -y ca-certificates curl gnupg
install -d -m 0755 /etc/apt/keyrings
curl -fsSL --proto '=https' --tlsv1.2 https://download.docker.com/linux/ubuntu/gpg | \
    gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" > /etc/apt/sources.list.d/docker.list
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable docker

# ─── Fetch Greenbone compose manifest + pre-pull images ───────────
echo "[install-greenbone] fetching compose manifest..."
install -d -m 0755 "$GREENBONE_DIR"
curl -fsSL --proto '=https' --tlsv1.2 -o "$GREENBONE_DIR/docker-compose.yml" "$COMPOSE_URL"

# Pre-pull so first vagrant-up boot is fast rather than downloading
# ~2 GB of container images over the lab's NAT.
echo "[install-greenbone] pulling images (this is ~2 GB)..."
( cd "$GREENBONE_DIR" && docker compose -f docker-compose.yml pull --ignore-pull-failures )

# Systemd unit — bring the stack up at boot, keep it up. Vagrant's
# first `vagrant up` triggers this on the target host.
cat > /etc/systemd/system/socool-greenbone.service <<EOF
[Unit]
Description=SOCool Greenbone Community Containers
After=docker.service network-online.target
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=${GREENBONE_DIR}
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down

[Install]
WantedBy=multi-user.target
EOF
systemctl enable socool-greenbone.service

echo "[install-greenbone] done."
