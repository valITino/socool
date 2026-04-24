#!/usr/bin/env bash
# scripts/preflight/checks/check-cpu-virt.sh
# Verifies hardware CPU virtualization (VT-x / AMD-V / hv_support)
# is available and enabled on the host.
# Exit 0 on pass; exit 12 with a remediation sentence on fail.
#
# Detection per platform:
#   Linux:  /proc/cpuinfo contains 'vmx' (Intel) or 'svm' (AMD)
#   Darwin: sysctl kern.hv_support returns 1 (works on both Intel &
#           Apple Silicon; the underlying API differs but the flag is
#           the documented detection mechanism, per Apple's Hypervisor
#           Framework docs)

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

detect_host

case "$SOCOOL_OS" in
    linux)
        if [[ ! -r /proc/cpuinfo ]]; then
            die 12 "/proc/cpuinfo is not readable; cannot verify CPU virtualization. Run on a Linux host with a standard proc mount."
        fi
        if grep -Eq '(^|[[:space:]])(vmx|svm)([[:space:]]|$)' /proc/cpuinfo; then
            local flag
            flag="$(grep -Eo '(vmx|svm)' /proc/cpuinfo | sort -u | tr '\n' ',' | sed 's/,$//')"
            log_info "cpu-virt: enabled ($flag)"
            exit 0
        fi
        die 12 "CPU virtualization (VT-x/AMD-V) is not enabled; enable Intel VT-x or AMD-V in your BIOS/UEFI firmware and reboot."
        ;;
    darwin)
        local out
        out="$(sysctl -n kern.hv_support 2>/dev/null || printf '0')"
        if [[ "$out" == "1" ]]; then
            log_info "cpu-virt: enabled (kern.hv_support=1)"
            exit 0
        fi
        die 12 "macOS hypervisor framework is not available (kern.hv_support=$out); the Mac model or its firmware does not expose virtualization. SOCool cannot run here."
        ;;
    *)
        die 12 "check-cpu-virt.sh should not run on os=$SOCOOL_OS; use check-cpu-virt.ps1 on Windows."
        ;;
esac
