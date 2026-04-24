#!/usr/bin/env bash
# scripts/preflight/checks/check-nested-virt.sh
# Verifies nested virtualization capability (required by the scanner VMs).
# Exit 0 on pass; exit 13 with a remediation sentence on fail.
#
# Nested virt is strictly required for Nessus / OpenVAS workloads. On
# hosts where it is not exposed, the check exports SOCOOL_HAS_NESTED_VIRT
# and exits 13; setup.* can let the user override by picking
# SOCOOL_SCANNER=none.
#
# Detection per platform:
#   Linux KVM: /sys/module/kvm_intel/parameters/nested is Y or 1
#              (or kvm_amd/parameters/nested equivalent)
#   Darwin:    Hypervisor Framework does not expose a nested-virt
#              control surface; we report "unknown" and fail-soft
#              via SOCOOL_HAS_NESTED_VIRT=unknown.

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

detect_host

_kvm_nested_enabled() {
    local f
    for f in /sys/module/kvm_intel/parameters/nested /sys/module/kvm_amd/parameters/nested; do
        [[ -r "$f" ]] || continue
        case "$(cat -- "$f" 2>/dev/null || true)" in
            Y|y|1) return 0 ;;
        esac
    done
    return 1
}

case "$SOCOOL_OS" in
    linux)
        if _kvm_nested_enabled; then
            log_info "nested-virt: enabled (KVM module parameter)"
            exit 0
        fi
        die 13 "nested virtualization is not enabled; the Nessus / OpenVAS VM requires it. Enable via: echo 'options kvm_intel nested=1' | sudo tee /etc/modprobe.d/kvm.conf && sudo modprobe -r kvm_intel && sudo modprobe kvm_intel (or kvm_amd on AMD hosts), or run with SOCOOL_SCANNER=none."
        ;;
    darwin)
        # Apple's Hypervisor Framework does not expose a nested-virt
        # toggle. The scanner VM is best-effort on macOS; we warn and
        # succeed, leaving the choice to the user.
        log_warn "nested-virt: cannot verify on macOS (Hypervisor Framework has no public nested probe); the scanner VM is best-effort. Set SOCOOL_SCANNER=none to skip if it fails to boot."
        exit 0
        ;;
    *)
        die 13 "check-nested-virt.sh should not run on os=$SOCOOL_OS; use check-nested-virt.ps1 on Windows."
        ;;
esac
