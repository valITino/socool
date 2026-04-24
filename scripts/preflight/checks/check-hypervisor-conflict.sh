#!/usr/bin/env bash
# scripts/preflight/checks/check-hypervisor-conflict.sh
# Linux: verifies the KVM modules are usable (if user will choose libvirt).
# macOS: no conflict surface; exits 0.
# Windows: handled by the .ps1 twin.
# Exit 0 on pass; exit 16 on fail.

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

detect_host

case "$SOCOOL_OS" in
    linux)
        # If the user is going to pick libvirt (default on aarch64,
        # fallback on x86_64), KVM modules must be loadable. We don't
        # fail when the user hasn't chosen yet — they may pick
        # VirtualBox. We only fail if libvirt is explicitly selected
        # but KVM is unavailable.
        if [[ "${SOCOOL_HYPERVISOR:-}" == "libvirt" ]] || [[ "$SOCOOL_ARCH" == "aarch64" ]]; then
            if [[ -e /sys/module/kvm_intel/parameters/nested ]] || [[ -e /sys/module/kvm_amd/parameters/nested ]]; then
                log_info "hypervisor-conflict: KVM modules present"
                exit 0
            fi
            # Modules absent — try to probe whether /dev/kvm is even a thing.
            if [[ -c /dev/kvm ]]; then
                log_info "hypervisor-conflict: /dev/kvm present (KVM built-in)"
                exit 0
            fi
            die 16 "libvirt/QEMU selected but KVM is not available; load modules with 'sudo modprobe kvm_intel' (or kvm_amd) and verify /dev/kvm exists, or pick SOCOOL_HYPERVISOR=virtualbox on x86_64."
        fi
        log_info "hypervisor-conflict: no conflict (VirtualBox path on linux:$SOCOOL_ARCH)"
        exit 0
        ;;
    darwin)
        log_info "hypervisor-conflict: n/a on macOS"
        exit 0
        ;;
    *)
        die 16 "check-hypervisor-conflict.sh should not run on os=$SOCOOL_OS; use check-hypervisor-conflict.ps1 on Windows."
        ;;
esac
