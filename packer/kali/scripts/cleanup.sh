#!/usr/bin/env bash
# packer/kali/scripts/cleanup.sh — shrink the image and remove build
# residue. Runs last so rotate-credentials' manifest is still retrievable.

set -euo pipefail

echo "[cleanup] apt caches..."
apt-get -y autoremove --purge || true
apt-get -y clean
rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*.deb

echo "[cleanup] machine-id + SSH host keys (regenerated on first boot)..."
# Zero the machine-id so clones don't share DHCP / DBus identity.
:> /etc/machine-id
:> /var/lib/dbus/machine-id || true

rm -f /etc/ssh/ssh_host_*
systemctl enable ssh-keygen.service 2>/dev/null || true
# Fallback: generate at next boot via rc.local if the service is absent.
cat > /etc/systemd/system/socool-regenerate-sshkeys.service <<'EOF'
[Unit]
Description=SOCool — regenerate SSH host keys on first boot
ConditionPathExistsGlob=!/etc/ssh/ssh_host_*_key
Before=ssh.service

[Service]
Type=oneshot
ExecStart=/usr/bin/ssh-keygen -A
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
systemctl enable socool-regenerate-sshkeys.service

echo "[cleanup] shell history / logs..."
rm -f /root/.bash_history /home/vagrant/.bash_history
:> /var/log/wtmp || true
:> /var/log/btmp || true
find /var/log -type f -name '*.log' -exec truncate -s 0 {} +

echo "[cleanup] zero free disk for image compression..."
dd if=/dev/zero of=/EMPTY bs=1M status=none || true
rm -f /EMPTY
sync

echo "[cleanup] done."
