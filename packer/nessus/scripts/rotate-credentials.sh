#!/usr/bin/env bash
# packer/nessus/scripts/rotate-credentials.sh
#
# Rotates vagrant + the Nessus web UI admin account. Nessus creates
# its initial admin user at first login; rotate-credentials.sh records
# the generated password to the manifest and creates the admin user
# via `nessuscli adduser`.

set -euo pipefail
umask 0077

VAGRANT_PASS="$(openssl rand -base64 32 | tr -d '=/+' | cut -c1-24)"
ADMIN_PASS="$(openssl rand -base64 32 | tr -d '=/+' | cut -c1-24)"

echo "vagrant:${VAGRANT_PASS}" | chpasswd

# nessuscli adduser expects an interactive password prompt by default;
# use the `--password` stdin mode through expect-style heredoc. If
# nessuscli isn't yet ready we defer to a systemd oneshot at first boot.
if command -v /opt/nessus/sbin/nessuscli >/dev/null 2>&1; then
    printf '%s\n%s\n' "${ADMIN_PASS}" "${ADMIN_PASS}" | \
        /opt/nessus/sbin/nessuscli adduser admin --admin --non-interactive 2>/dev/null || \
        /opt/nessus/sbin/nessuscli adduser admin --admin < <(printf '%s\n%s\n' "${ADMIN_PASS}" "${ADMIN_PASS}") || \
        echo "[rotate-credentials] nessuscli adduser failed; deferring to first-boot init"
fi

MANIFEST="/tmp/socool-nessus-credentials.json"
cat > "$MANIFEST" <<EOF
{
  "vm": "nessus",
  "generated_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "accounts": [
    { "username": "vagrant", "password": "${VAGRANT_PASS}", "scope": "SSH" },
    { "username": "admin",   "password": "${ADMIN_PASS}",   "scope": "Nessus web UI (https://10.42.20.20:8834/)" }
  ],
  "notes": "Nessus plugin download continues in the background after boot; the web UI may be slow for 20-60 minutes post-first-boot as plugins load."
}
EOF
chmod 0600 "$MANIFEST"
echo "[rotate-credentials] manifest written."
