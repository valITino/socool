#!/usr/bin/env bash
# packer/kali/scripts/rotate-credentials.sh — replaces BUILD-ONLY
# defaults with CSPRNG-generated credentials, writes a manifest for
# setup.*'s final summary.
#
# The manifest file /tmp/socool-kali-credentials.json is pulled back to
# the host by the Packer `file` provisioner (direction=download) after
# this script finishes.

set -euo pipefail
umask 0077

ROOT_PASS="$(openssl rand -base64 32 | tr -d '=/+' | cut -c1-24)"
VAGRANT_PASS="$(openssl rand -base64 32 | tr -d '=/+' | cut -c1-24)"

echo "[rotate-credentials] rotating root + vagrant passwords..."
echo "root:${ROOT_PASS}" | chpasswd
echo "vagrant:${VAGRANT_PASS}" | chpasswd

# Regenerate the Vagrant keypair so the upstream insecure key is no
# longer trusted. Vagrant will detect this on first `vagrant up` and
# swap in its own per-user key, overwriting authorized_keys.
if command -v ssh-keygen >/dev/null 2>&1; then
    rm -f /home/vagrant/.ssh/socool_id_ed25519 /home/vagrant/.ssh/socool_id_ed25519.pub
    ssh-keygen -t ed25519 -N '' -f /home/vagrant/.ssh/socool_id_ed25519 -C "socool-kali-initial"
    SSH_FP="$(ssh-keygen -lf /home/vagrant/.ssh/socool_id_ed25519.pub | awk '{print $2}')"
    chown -R vagrant:vagrant /home/vagrant/.ssh
else
    SSH_FP="skipped (ssh-keygen missing at rotation time)"
fi

# Emit the manifest for the host to consume. No passwords in build logs
# (devsecops rule) — write to a restricted file only.
MANIFEST="/tmp/socool-kali-credentials.json"
cat > "$MANIFEST" <<EOF
{
  "vm": "kali",
  "generated_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "accounts": [
    { "username": "root",    "password": "${ROOT_PASS}" },
    { "username": "vagrant", "password": "${VAGRANT_PASS}" }
  ],
  "ssh_key_fingerprint": "${SSH_FP}",
  "notes": "Rotated during Packer build; upstream defaults are gone. Vagrant will overwrite authorized_keys with its own key on first 'vagrant up'."
}
EOF
chmod 0600 "$MANIFEST"

echo "[rotate-credentials] manifest written; no passwords printed to stdout."
