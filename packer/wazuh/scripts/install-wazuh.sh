#!/usr/bin/env bash
# packer/wazuh/scripts/install-wazuh.sh — all-in-one Wazuh install.
#
# Pulls wazuh-install.sh from packages.wazuh.com (verified 2026-04-24)
# and runs with -a to install manager + indexer + dashboard on one host.
# All-in-one is Wazuh's recommended topology for up to 100 endpoints
# and 90 days of indexed alerts, which comfortably exceeds the lab's
# needs.

set -euo pipefail

VERSION="${SOCOOL_WAZUH_VERSION:-4.14}"
INSTALLER_URL="https://packages.wazuh.com/${VERSION}/wazuh-install.sh"
WORK_DIR="/root/wazuh-install"

echo "[install-wazuh] fetching ${INSTALLER_URL}..."
install -d -m 0700 "$WORK_DIR"
curl -fsSL --proto '=https' --tlsv1.2 -o "$WORK_DIR/wazuh-install.sh" "$INSTALLER_URL"
chmod 0700 "$WORK_DIR/wazuh-install.sh"

echo "[install-wazuh] running all-in-one install (this takes 15-30 minutes)..."
# -a = assisted all-in-one; -i = ignore health-check (our build VM may
# have less RAM than prod); -o = overwrite existing install files.
cd "$WORK_DIR"
./wazuh-install.sh -a -i

# The installer writes admin credentials into /root/wazuh-install-files/
# (specifically wazuh-install-files.tar). Preserve them for the
# rotate-credentials step to pick up and rotate.
if [[ -f /root/wazuh-install-files.tar ]]; then
    mkdir -p /root/wazuh-initial-creds
    tar -xf /root/wazuh-install-files.tar -C /root/wazuh-initial-creds
fi

echo "[install-wazuh] done."
