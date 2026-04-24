#!/usr/bin/env bash
# packer/wazuh/scripts/cleanup.sh — shrink the image + drop build residue.
set -euo pipefail

echo "[cleanup] apt cache..."
apt-get -y autoremove --purge || true
apt-get -y clean
rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*.deb

echo "[cleanup] wazuh installer scratch..."
rm -rf /root/wazuh-install /root/wazuh-install-files* /root/wazuh-initial-creds

echo "[cleanup] machine-id + SSH host keys regenerate-on-first-boot..."
:> /etc/machine-id
rm -f /etc/ssh/ssh_host_*
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

echo "[cleanup] shell history + logs..."
rm -f /root/.bash_history /home/vagrant/.bash_history
find /var/log -type f -name '*.log' -exec truncate -s 0 {} +
:> /var/log/wtmp || true
:> /var/log/btmp || true

echo "[cleanup] zero free space..."
dd if=/dev/zero of=/EMPTY bs=1M status=none || true
rm -f /EMPTY
sync

echo "[cleanup] done."
