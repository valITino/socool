#!/usr/bin/env bash
# packer/nessus/scripts/install-nessus.sh
#
# Downloads (or receives) the Nessus Essentials .deb, installs it,
# starts nessusd, registers with the user-supplied activation code.

set -euo pipefail

: "${SOCOOL_NESSUS_DEB_URL:?SOCOOL_NESSUS_DEB_URL must be set (Tenable session-gated)}"
: "${SOCOOL_NESSUS_ACTIVATION_CODE:?SOCOOL_NESSUS_ACTIVATION_CODE must be set (emailed by Tenable)}"

umask 0022

DEB_FILE="/root/nessus.deb"
echo "[install-nessus] fetching .deb..."
case "$SOCOOL_NESSUS_DEB_URL" in
    file://*)
        cp -f "${SOCOOL_NESSUS_DEB_URL#file://}" "$DEB_FILE"
        ;;
    https://*)
        curl -fsSL --proto '=https' --tlsv1.2 -o "$DEB_FILE" "$SOCOOL_NESSUS_DEB_URL"
        ;;
    *)
        echo "SOCOOL_NESSUS_DEB_URL must be https:// or file:// — got '$SOCOOL_NESSUS_DEB_URL'" >&2
        exit 1
        ;;
esac

echo "[install-nessus] dpkg -i..."
apt-get update
apt-get install -y -f
dpkg -i "$DEB_FILE" || apt-get install -y -f

systemctl enable nessusd
systemctl start nessusd

echo "[install-nessus] waiting for nessusd to accept CLI connections..."
for _ in $(seq 1 30); do
    if /opt/nessus/sbin/nessuscli fix --list >/dev/null 2>&1; then
        break
    fi
    sleep 5
done

echo "[install-nessus] registering activation code..."
# The activation code value is passed via env for safety (not a CLI
# arg that appears in /proc). We still use the CLI form because
# nessuscli expects a positional arg; the value hits /proc briefly.
# This is acceptable — the VM is a fresh build with only the vagrant
# user and root logged in.
/opt/nessus/sbin/nessuscli fetch --register "${SOCOOL_NESSUS_ACTIVATION_CODE}"

echo "[install-nessus] plugin fetch can take a long time — not waiting for completion in the build."
rm -f "$DEB_FILE"
echo "[install-nessus] done."
