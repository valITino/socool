#!/usr/bin/env bash
# packer/thehive/scripts/vagrant-user.sh — idempotent vagrant user bootstrap.
set -euo pipefail

id -u vagrant >/dev/null 2>&1 || useradd -m -s /bin/bash vagrant

install -d -m 0755 /etc/sudoers.d
cat > /etc/sudoers.d/vagrant <<'EOF'
vagrant ALL=(ALL) NOPASSWD: ALL
Defaults:vagrant !requiretty
EOF
chmod 0440 /etc/sudoers.d/vagrant

install -o vagrant -g vagrant -m 0700 -d /home/vagrant/.ssh
if [[ ! -s /home/vagrant/.ssh/authorized_keys ]]; then
    curl -fsSL --proto '=https' --tlsv1.2 \
        https://raw.githubusercontent.com/hashicorp/vagrant/main/keys/vagrant.pub \
        -o /home/vagrant/.ssh/authorized_keys
fi
chown vagrant:vagrant /home/vagrant/.ssh/authorized_keys
chmod 0600 /home/vagrant/.ssh/authorized_keys

sed -i -E 's/^#?PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i -E 's/^#?PubkeyAuthentication .*/PubkeyAuthentication yes/'    /etc/ssh/sshd_config
systemctl reload ssh || systemctl restart ssh

echo "[vagrant-user] done."
