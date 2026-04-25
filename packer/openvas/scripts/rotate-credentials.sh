#!/usr/bin/env bash
# packer/openvas/scripts/rotate-credentials.sh
#
# Rotates the Linux vagrant account and records the generated
# Greenbone admin password for first-boot application. The Greenbone
# stack's `gvmd` creates the initial admin at first start via
# docker exec; our systemd unit kicks that off on the target host.
# We stage the rotated admin password in an env file read by the
# socool-greenbone-firstboot.service unit below.

set -euo pipefail
umask 0077

VAGRANT_PASS="$(openssl rand -base64 32 | tr -d '=/+' | cut -c1-24)"
ADMIN_PASS="$(openssl rand -base64 32 | tr -d '=/+' | cut -c1-24)"

echo "vagrant:${VAGRANT_PASS}" | chpasswd

# Stage the admin password for a first-boot systemd unit to apply.
install -d -m 0700 /etc/socool
install -m 0600 /dev/stdin /etc/socool/greenbone-admin.env <<EOF
GREENBONE_ADMIN_USER=admin
GREENBONE_ADMIN_PASS=${ADMIN_PASS}
EOF

cat > /etc/systemd/system/socool-greenbone-firstboot.service <<'EOF'
[Unit]
Description=SOCool — apply Greenbone admin password on first boot
After=socool-greenbone.service
Requires=socool-greenbone.service
ConditionPathExists=!/var/lib/socool/greenbone-firstboot.done

[Service]
Type=oneshot
RemainAfterExit=yes
EnvironmentFile=/etc/socool/greenbone-admin.env
ExecStart=/bin/bash -c ' \
  set -e; \
  install -d -m 0755 /var/lib/socool; \
  for _ in $(seq 1 60); do \
    if docker compose -f /opt/greenbone/docker-compose.yml ps --status running | grep -q gvmd; then break; fi; \
    sleep 5; \
  done; \
  docker compose -f /opt/greenbone/docker-compose.yml exec -T gvmd \
    gvmd --create-user="${GREENBONE_ADMIN_USER}" --password="${GREENBONE_ADMIN_PASS}" || \
  docker compose -f /opt/greenbone/docker-compose.yml exec -T gvmd \
    gvmd --user="${GREENBONE_ADMIN_USER}" --new-password="${GREENBONE_ADMIN_PASS}"; \
  touch /var/lib/socool/greenbone-firstboot.done'

[Install]
WantedBy=multi-user.target
EOF
systemctl enable socool-greenbone-firstboot.service

MANIFEST="/tmp/socool-openvas-credentials.json"
cat > "$MANIFEST" <<EOF
{
  "vm": "openvas",
  "generated_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "accounts": [
    { "username": "vagrant", "password": "${VAGRANT_PASS}", "scope": "SSH" },
    { "username": "admin",   "password": "${ADMIN_PASS}",   "scope": "Greenbone web UI (https://10.42.20.20/); applied by socool-greenbone-firstboot.service on first vagrant up" }
  ],
  "notes": "Greenbone feed sync on first boot is long (30-90 minutes). The UI is responsive well before the feed finishes — the first few scans just have fewer plugins."
}
EOF
chmod 0600 "$MANIFEST"
echo "[rotate-credentials] manifest written."
