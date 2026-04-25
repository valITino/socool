#!/usr/bin/env bash
# scripts/preflight/checks/check-os-arch.sh
# Verifies the host OS + architecture is in the supported set.
# Exit 0 on pass; exit 11 with a remediation sentence on fail.

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

# detect_host is idempotent; run it even if setup.sh already did so
# the check works standalone.
detect_host

case "$SOCOOL_OS:$SOCOOL_ARCH" in
    linux:x86_64|linux:aarch64|darwin:x86_64|darwin:aarch64)
        log_info "os-arch: $SOCOOL_OS:$SOCOOL_ARCH (supported)"
        exit 0
        ;;
    windows:*)
        die 11 "setup.sh does not support Windows hosts; use setup.ps1 from a PowerShell 7 prompt."
        ;;
    *)
        die 11 "unsupported host OS/arch '$SOCOOL_OS:$SOCOOL_ARCH'; see docs/adr/0002-hypervisor-matrix.md for the supported set."
        ;;
esac
