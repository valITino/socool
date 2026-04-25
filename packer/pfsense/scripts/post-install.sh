#!/bin/sh
# packer/pfsense/scripts/post-install.sh — FreeBSD /bin/sh
#
# Runs on the first SSH connection after the pfSense installer finishes
# and the box reboots. At this point:
#   - config-seed.xml is already at /cf/conf/config.xml (from installerconfig)
#   - pfSense has applied the seed and is running
#   - Root password is still the BUILD-ONLY default 'pfsense'
# This script does minor cleanup (pkg caches, log truncation) so the
# shipped box is as small as we can make it. Credential rotation is a
# separate script that runs after this one.

set -eu

echo "[post-install] trimming pkg cache..."
# pfSense uses pkg; clear its cache to save disk.
pkg clean -y || true
rm -rf /var/cache/pkg/*

echo "[post-install] truncating log files..."
find /var/log -type f -exec sh -c ':> "$1"' _ {} \;

echo "[post-install] zeroing empty disk for compression..."
dd if=/dev/zero of=/EMPTY bs=1m 2>/dev/null || true
rm -f /EMPTY
sync

echo "[post-install] done."
