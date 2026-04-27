#!/usr/bin/env bash
# packer/thehive/scripts/rotate-credentials.sh
#
# Rotates the Linux vagrant account and stages a CSPRNG password for
# TheHive's default admin (admin@thehive.local / secret). TheHive
# stores user credentials in Cassandra, not on disk, so the rotation
# can only happen via TheHive's REST API after the stack is up.
#
# Pattern mirrors openvas: stage the password under /etc/socool/ and
# install a systemd oneshot unit that applies it on first boot once
# the API is reachable.

set -euo pipefail
umask 0077

VAGRANT_PASS="$(openssl rand -base64 32 | tr -d '=/+' | cut -c1-24)"
ADMIN_PASS="$(openssl rand -base64 32 | tr -d '=/+' | cut -c1-24)"

# ─── 1. Linux vagrant user ─────────────────────────────────────────
echo "[rotate-credentials] linux vagrant password..."
echo "vagrant:${VAGRANT_PASS}" | chpasswd

# ─── 2. Stage TheHive admin rotation for first boot ────────────────
install -d -m 0700 /etc/socool
install -m 0600 /dev/stdin /etc/socool/thehive-admin.env <<EOF
THEHIVE_ADMIN_USER=admin@thehive.local
THEHIVE_ADMIN_DEFAULT_PASS=secret
THEHIVE_ADMIN_PASS=${ADMIN_PASS}
THEHIVE_API_BASE=http://127.0.0.1:9000
EOF

cat > /etc/systemd/system/socool-thehive-firstboot.service <<'EOF'
[Unit]
Description=SOCool — rotate TheHive admin password on first boot
After=socool-thehive.service
Requires=socool-thehive.service
ConditionPathExists=!/var/lib/socool/thehive-firstboot.done

[Service]
Type=oneshot
RemainAfterExit=yes
EnvironmentFile=/etc/socool/thehive-admin.env
ExecStart=/bin/bash -c ' \
  set -e; \
  install -d -m 0755 /var/lib/socool; \
  for _ in $(seq 1 120); do \
    code="$(curl -fsS -o /dev/null -w "%{http_code}" "${THEHIVE_API_BASE}/api/v1/status" || true)"; \
    if [ "$code" = "200" ]; then break; fi; \
    sleep 5; \
  done; \
  uid="$(curl -fsS -u "${THEHIVE_ADMIN_USER}:${THEHIVE_ADMIN_DEFAULT_PASS}" \
        "${THEHIVE_API_BASE}/api/v1/user/current" | jq -r .login || echo "")"; \
  if [ -z "$uid" ]; then \
    echo "first-boot: default credentials no longer valid; assuming pre-rotated"; \
    touch /var/lib/socool/thehive-firstboot.done; \
    exit 0; \
  fi; \
  curl -fsS -u "${THEHIVE_ADMIN_USER}:${THEHIVE_ADMIN_DEFAULT_PASS}" \
       -H "Content-Type: application/json" \
       -X POST "${THEHIVE_API_BASE}/api/v1/user/${uid}/password/set" \
       -d "{\"password\":\"${THEHIVE_ADMIN_PASS}\"}"; \
  touch /var/lib/socool/thehive-firstboot.done'

[Install]
WantedBy=multi-user.target
EOF
systemctl enable socool-thehive-firstboot.service

# ─── 3. Manifest ──────────────────────────────────────────────────
MANIFEST="/tmp/socool-thehive-credentials.json"
cat > "$MANIFEST" <<EOF
{
  "vm": "thehive",
  "generated_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "accounts": [
    { "username": "vagrant",              "password": "${VAGRANT_PASS}", "scope": "SSH" },
    { "username": "admin@thehive.local",  "password": "${ADMIN_PASS}",   "scope": "TheHive web UI (https://10.42.20.30/) — applied by socool-thehive-firstboot.service on first vagrant up" }
  ],
  "notes": "TheHive 5.3+ runs in read-only mode without a Community license. Request one (free) at https://strangebee.com/community/ and paste it under Settings > License after first login. Cassandra + Elasticsearch start-up takes ~3 minutes on first boot before TheHive is reachable."
}
EOF
chmod 0600 "$MANIFEST"
echo "[rotate-credentials] manifest written."
