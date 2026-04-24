#!/usr/bin/env bash
set -euo pipefail
apt-get -y autoremove --purge || true
apt-get -y clean
rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*.deb
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
rm -f /root/.bash_history /home/vagrant/.bash_history
find /var/log -type f -name '*.log' -exec truncate -s 0 {} +
:> /var/log/wtmp || true
:> /var/log/btmp || true
dd if=/dev/zero of=/EMPTY bs=1M status=none || true
rm -f /EMPTY
sync
