#!/bin/sh
# packer/pfsense/scripts/rotate-credentials.sh — FreeBSD /bin/sh
#
# Rotates the BUILD-ONLY root + admin passwords to CSPRNG values, writes
# /tmp/socool-pfsense-credentials.json, which the Packer file provisioner
# pulls back to the host. pfSense stores the webConfigurator admin
# password as bcrypt in /cf/conf/config.xml; we hash with openssl.

set -eu
umask 0077

ROOT_PASS=$(/usr/bin/openssl rand -base64 32 | tr -d '=/+' | cut -c1-24)
ADMIN_PASS=$(/usr/bin/openssl rand -base64 32 | tr -d '=/+' | cut -c1-24)

# Root: set via `pw usermod`. pfSense's shell-access root uses the
# FreeBSD /etc/master.passwd.
echo "[rotate-credentials] rotating root..."
echo "${ROOT_PASS}" | pw usermod root -h 0

# webConfigurator admin: update config.xml. pfSense uses bcrypt $2y$
# (cost 10). We shell out to openssl passwd; if bcrypt support isn't
# present in the shipped openssl we fall back to pfSense's rc.initial.php
# helper which will re-hash on next boot.
ADMIN_HASH=$(/usr/bin/openssl passwd -5 "${ADMIN_PASS}" 2>/dev/null || printf '')
if [ -z "${ADMIN_HASH}" ]; then
    # pfSense internal helper; keeps the admin password rotation in-band.
    echo "[rotate-credentials] using pfSense helper for admin hash..."
    /usr/local/bin/php -r "
        require_once '/etc/inc/auth.inc';
        \$cfg = parse_config(true);
        foreach (\$cfg['system']['user'] as &\$u) {
            if (\$u['name'] === 'admin') {
                \$u['password'] = password_hash('${ADMIN_PASS}', PASSWORD_BCRYPT);
            }
        }
        write_config('SOCool: rotate admin password');
    "
else
    # Fallback path: substitute the hash into config.xml.
    sed -i.bak -e "s|<password>\$2y\\\$10\\\$BUILDONLY[A-Za-z0-9./]*</password>|<password>${ADMIN_HASH}</password>|" /cf/conf/config.xml
fi

MANIFEST="/tmp/socool-pfsense-credentials.json"
cat > "${MANIFEST}" <<EOF
{
  "vm": "pfsense",
  "generated_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "accounts": [
    { "username": "root",  "password": "${ROOT_PASS}",  "scope": "ssh + console" },
    { "username": "admin", "password": "${ADMIN_PASS}", "scope": "webConfigurator https://10.42.20.1/" }
  ],
  "notes": "Rotated during Packer build; upstream defaults (root:pfsense, admin:pfsense) are gone."
}
EOF
chmod 0600 "${MANIFEST}"
echo "[rotate-credentials] manifest written."
