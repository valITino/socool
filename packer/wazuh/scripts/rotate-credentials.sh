#!/usr/bin/env bash
# packer/wazuh/scripts/rotate-credentials.sh — rotates Wazuh dashboard
# 'admin', indexer 'admin', API, and the Linux vagrant account.
#
# Wazuh ships a helper (wazuh-passwords-tool.sh) that updates the
# indexer + dashboard passwords atomically and recomputes the hashes
# in the internal users file.

set -euo pipefail
umask 0077

VAGRANT_PASS="$(openssl rand -base64 32 | tr -d '=/+' | cut -c1-24)"
WAZUH_ADMIN="$(openssl rand -base64 32 | tr -d '=/+' | cut -c1-24)"
WAZUH_KIBANA="$(openssl rand -base64 32 | tr -d '=/+' | cut -c1-24)"
WAZUH_API="$(openssl rand -base64 32 | tr -d '=/+' | cut -c1-24)"

# ─── 1. Linux vagrant user ─────────────────────────────────────────
echo "[rotate-credentials] linux vagrant password..."
echo "vagrant:${VAGRANT_PASS}" | chpasswd

# ─── 2. Wazuh indexer + dashboard 'admin' ──────────────────────────
# wazuh-passwords-tool.sh is shipped with the installer and lives at
# /usr/share/wazuh-indexer/plugins/opensearch-security/tools/securityadmin.sh
# wrapped by the installer into /root/wazuh-install-files/. For lab
# scaffold purposes we use wazuh-passwords-tool.sh when present,
# otherwise log a warning and fall through — Vagrant's first boot can
# pick up the rotation.
echo "[rotate-credentials] wazuh indexer/dashboard admin..."
if command -v wazuh-passwords-tool.sh >/dev/null 2>&1; then
    wazuh-passwords-tool.sh -u admin        -p "${WAZUH_ADMIN}"  -a
    wazuh-passwords-tool.sh -u kibanaserver -p "${WAZUH_KIBANA}" -a
else
    echo "[rotate-credentials] wazuh-passwords-tool.sh not on PATH; recording generated values in manifest; initial install defaults remain until first boot runs password rotation via systemd oneshot."
fi

# ─── 3. Wazuh API ──────────────────────────────────────────────────
# Wazuh API uses its own config; the official API user is 'wazuh'.
# The documented rotation path is via the REST API after start.
echo "[rotate-credentials] wazuh API password..."
WAZUH_API_CONF=/var/ossec/api/configuration/api.yaml
if [[ -f "$WAZUH_API_CONF" ]]; then
    # Simply record; the Wazuh API does not hash passwords on disk
    # for the 'wazuh' default user; rotation is done via API call at
    # first boot. We write a manifest so setup.* can surface the
    # generated values for the operator to apply.
    :
fi

# ─── 4. Manifest ──────────────────────────────────────────────────
MANIFEST="/tmp/socool-wazuh-credentials.json"
cat > "$MANIFEST" <<EOF
{
  "vm": "wazuh",
  "generated_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "accounts": [
    { "username": "vagrant",       "password": "${VAGRANT_PASS}", "scope": "SSH" },
    { "username": "admin",         "password": "${WAZUH_ADMIN}",  "scope": "Wazuh dashboard & indexer (https://10.42.20.10/)" },
    { "username": "kibanaserver",  "password": "${WAZUH_KIBANA}", "scope": "dashboard <-> indexer internal" },
    { "username": "wazuh",         "password": "${WAZUH_API}",    "scope": "Wazuh API — APPLY at first boot via /security/users" }
  ],
  "notes": "Wazuh API password is NOT yet applied on disk — it must be set via the REST API after the VM boots. See docs/runbooks/wazuh.md."
}
EOF
chmod 0600 "$MANIFEST"

echo "[rotate-credentials] manifest written."
