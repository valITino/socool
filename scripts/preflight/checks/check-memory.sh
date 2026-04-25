#!/usr/bin/env bash
# scripts/preflight/checks/check-memory.sh
# Verifies host has enough free RAM for the non-optional lab VMs plus
# a 4 GB headroom for host OS + tooling.
# Exit 0 on pass; exit 14 on fail.

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

detect_host

# Required lab RAM = sum of ram_mb for non-optional VMs. Python does
# the sum because it already safe-loads the YAML.
required_mb="$(python3 - "$socool_repo_root/config/lab.yml" <<'PY'
import sys, yaml
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)
total = sum(v['ram_mb'] for v in data.get('vms', []) if not v.get('optional', False))
print(total)
PY
)"

# Host headroom reserved for OS + Packer build transients.
headroom_mb=4096
threshold_mb=$(( required_mb + headroom_mb ))

# Host free memory — available, not total. MemAvailable on Linux is
# the figure that actually reflects what a new process can allocate
# without swapping. Darwin has no direct equivalent; we approximate
# via free pages × page size, ignoring inactive which the kernel can
# reclaim.
free_mb=0
case "$SOCOOL_OS" in
    linux)
        if [[ -r /proc/meminfo ]]; then
            free_mb="$(awk '/^MemAvailable:/ { printf "%d\n", $2 / 1024 }' /proc/meminfo)"
        fi
        ;;
    darwin)
        # Not `local`: we're in a case arm at script top-level, not
        # inside a function, so `local` would be a runtime error.
        page_size="$(sysctl -n hw.pagesize 2>/dev/null || printf '4096')"
        free_pages="$(vm_stat 2>/dev/null | awk '/^Pages free:/ { gsub(/\./,""); print $3 }')"
        if [[ -n "${free_pages:-}" ]]; then
            free_mb=$(( free_pages * page_size / 1024 / 1024 ))
        fi
        ;;
    *)
        die 14 "check-memory.sh should not run on os=$SOCOOL_OS."
        ;;
esac

if [[ -z "$free_mb" || "$free_mb" == "0" ]]; then
    die 14 "unable to determine free RAM on $SOCOOL_OS; close other apps and re-run, or override with SOCOOL_SKIP_PREFLIGHT=1 (not yet implemented)."
fi

if (( free_mb < threshold_mb )); then
    die 14 "insufficient free RAM: host has ${free_mb} MB free, lab needs ${required_mb} MB + ${headroom_mb} MB headroom = ${threshold_mb} MB. Close other applications, or edit config/lab.yml to reduce per-VM ram_mb."
fi

log_info "memory: ${free_mb} MB free, needs ${threshold_mb} MB (required ${required_mb} MB + ${headroom_mb} MB headroom)"
