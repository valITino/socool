#!/usr/bin/env bash
# scripts/preflight/checks/check-disk.sh
# Verifies host has enough free disk on the Packer box output volume
# for the non-optional lab VMs plus 20 GB for Packer cache & temp.
# Exit 0 on pass; exit 15 on fail.

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

detect_host

required_gb="$(python3 - "$socool_repo_root/config/lab.yml" <<'PY'
import sys, yaml
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)
print(sum(v['disk_gb'] for v in data.get('vms', []) if not v.get('optional', False)))
PY
)"

headroom_gb=20
threshold_gb=$(( required_gb + headroom_gb ))

# Target volume = SOCOOL_BOX_OUTPUT_DIR if set, else repo root. The box
# output dir may not exist yet; probe its intended parent so df reports
# the right filesystem.
target_dir="${SOCOOL_BOX_OUTPUT_DIR:-$socool_repo_root/.socool-cache}"
probe_dir="$target_dir"
while [[ ! -d "$probe_dir" ]]; do
    probe_dir="$(dirname -- "$probe_dir")"
    [[ "$probe_dir" == "/" ]] && break
done

# POSIX df prints KB when called with -k; awk extracts the Available
# column (4th). Works identically on Linux and macOS.
free_kb="$(df -Pk -- "$probe_dir" 2>/dev/null | awk 'NR==2 { print $4 }')"
if [[ -z "${free_kb:-}" ]]; then
    die 15 "unable to determine free disk on $probe_dir; verify the path exists and re-run."
fi
free_gb=$(( free_kb / 1024 / 1024 ))

if (( free_gb < threshold_gb )); then
    die 15 "insufficient free disk on $probe_dir: ${free_gb} GB free, lab needs ${required_gb} GB + ${headroom_gb} GB headroom = ${threshold_gb} GB. Free space, or set SOCOOL_BOX_OUTPUT_DIR to a larger volume."
fi

log_info "disk: ${free_gb} GB free on $probe_dir, needs ${threshold_gb} GB"
