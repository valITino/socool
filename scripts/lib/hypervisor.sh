#!/usr/bin/env bash
# scripts/lib/hypervisor.sh — hypervisor detection and resolution.
#
# Implements the algorithm from docs/adr/0002-hypervisor-matrix.md.
# Public ABI:
#   resolve_hypervisor   -> prints 'virtualbox' or 'libvirt' on stdout, or
#                           exits with 30..39 on conflict.
#
# Must be sourced AFTER scripts/lib/common.sh and AFTER detect_host ran
# so SOCOOL_OS and SOCOOL_ARCH are populated.

set -euo pipefail

if [[ "${_SOCOOL_HYPERVISOR_LOADED:-}" == "1" ]]; then
    return 0
fi
_SOCOOL_HYPERVISOR_LOADED=1

# ────────────────────────────────────────────────────────────────────────
# Conflict probes
# ────────────────────────────────────────────────────────────────────────

# _kvm_available — returns 0 if KVM modules loaded, 1 otherwise. Linux only.
_kvm_available() {
    [[ -e /sys/module/kvm_intel/parameters/nested ]] && return 0
    [[ -e /sys/module/kvm_amd/parameters/nested   ]] && return 0
    return 1
}

# _vboxmanage_available — returns 0 if VBoxManage on PATH.
_vboxmanage_available() {
    command -v VBoxManage >/dev/null 2>&1
}

# _qemu_available — returns 0 if a qemu-system-* binary is on PATH.
_qemu_available() {
    command -v qemu-system-x86_64 >/dev/null 2>&1 && return 0
    command -v qemu-system-aarch64 >/dev/null 2>&1 && return 0
    return 1
}

# ────────────────────────────────────────────────────────────────────────
# Matrix-driven resolution
# ────────────────────────────────────────────────────────────────────────

# _resolve_from_env_or_flag — honour SOCOOL_HYPERVISOR if set. Echoes the
# chosen hypervisor and returns 0; returns 1 if env var is unset.
_resolve_from_env_or_flag() {
    local v="${SOCOOL_HYPERVISOR:-}"
    case "$v" in
        "")                 return 1 ;;
        virtualbox|libvirt) printf '%s' "$v"; return 0 ;;
        *)                  die 2 "invalid SOCOOL_HYPERVISOR='$v' (expected virtualbox or libvirt)" ;;
    esac
}

# _validate_choice <hypervisor>
# Verifies the chosen hypervisor is compatible with SOCOOL_OS/SOCOOL_ARCH.
# Exits 30 on conflict.
_validate_choice() {
    local choice="$1"
    case "$SOCOOL_OS:$SOCOOL_ARCH:$choice" in
        linux:x86_64:virtualbox)   return 0 ;;
        linux:x86_64:libvirt)      return 0 ;;
        linux:aarch64:libvirt)     return 0 ;;
        linux:aarch64:virtualbox)  die 30 "VirtualBox does not support aarch64 Linux hosts. Use SOCOOL_HYPERVISOR=libvirt." ;;
        darwin:x86_64:virtualbox)  return 0 ;;
        darwin:x86_64:libvirt)     return 0 ;;
        darwin:aarch64:libvirt)    return 0 ;;
        darwin:aarch64:virtualbox) die 30 "VirtualBox support on Apple Silicon is limited and not supported by SOCool. Use SOCOOL_HYPERVISOR=libvirt (runs QEMU under the hood on macOS)." ;;
        windows:*:*)               die 30 "setup.sh is not supported on Windows hosts -- use setup.ps1 from a PowerShell 7 prompt." ;;
        *) die 30 "unsupported host/hypervisor combination: os=$SOCOOL_OS arch=$SOCOOL_ARCH choice=$choice" ;;
    esac
}

# _matrix_primary_fallback — echoes "<primary> <fallback>" (fallback may be
# empty). Exits 30 on an unsupported host combination.
_matrix_primary_fallback() {
    case "$SOCOOL_OS:$SOCOOL_ARCH" in
        linux:x86_64)   printf 'virtualbox libvirt' ;;
        linux:aarch64)  printf 'libvirt ' ;;
        darwin:x86_64)  printf 'virtualbox libvirt' ;;
        darwin:aarch64) printf 'libvirt ' ;;
        windows:*)      die 30 "setup.sh on Windows is not supported; use setup.ps1." ;;
        *)              die 30 "unsupported host: os=$SOCOOL_OS arch=$SOCOOL_ARCH" ;;
    esac
}

# resolve_hypervisor — public entry point. Echoes 'virtualbox' or 'libvirt'
# on stdout. All logging goes to stderr.
resolve_hypervisor() {
    # 1. Explicit override from env (CLI flag sets this before calling).
    local chosen
    if chosen="$(_resolve_from_env_or_flag)"; then
        _validate_choice "$chosen"
        log_info "hypervisor: $chosen (from SOCOOL_HYPERVISOR)"
        printf '%s' "$chosen"
        return 0
    fi

    # 2. Matrix walk.
    local pair primary fallback
    pair="$(_matrix_primary_fallback)"
    primary="${pair%% *}"
    fallback="${pair##* }"
    [[ "$primary" == "$fallback" ]] && fallback=""

    # 3. Detection.
    local have_primary=0 have_fallback=0
    case "$primary" in
        virtualbox) _vboxmanage_available && have_primary=1 ;;
        libvirt)    [[ "$SOCOOL_OS" == "linux" ]] && _kvm_available || true
                    _qemu_available && have_primary=1 ;;
    esac
    if [[ -n "$fallback" ]]; then
        case "$fallback" in
            virtualbox) _vboxmanage_available && have_fallback=1 ;;
            libvirt)    _qemu_available && have_fallback=1 ;;
        esac
    fi

    # Linux/libvirt: require KVM modules even if qemu is present. Fall
    # through to the prompt / fallback if the kernel isn't configured.
    if [[ "$primary" == "libvirt" && "$SOCOOL_OS" == "linux" ]] && ! _kvm_available; then
        have_primary=0
    fi
    if [[ "$fallback" == "libvirt" && "$SOCOOL_OS" == "linux" ]] && ! _kvm_available; then
        have_fallback=0
    fi

    # 4. Both present -> prompt (ambiguous). Only possible on
    # linux:x86_64 and darwin:x86_64 with both stacks installed.
    if [[ "$have_primary" == "1" && "$have_fallback" == "1" ]]; then
        prompt_action \
            "Choose hypervisor" \
            "Both $primary and $fallback are installed. Pick one." \
            "<no external resource>" \
            "virtualbox or libvirt" \
            "SOCOOL_HYPERVISOR"
        chosen="$(prompt_with_default 'hypervisor' "Hypervisor" "$primary" "SOCOOL_HYPERVISOR")"
        case "$chosen" in
            virtualbox|libvirt) ;;
            *) die 2 "invalid choice: '$chosen'" ;;
        esac
        _validate_choice "$chosen"
        log_info "hypervisor: $chosen (chosen)"
        printf '%s' "$chosen"
        return 0
    fi

    # 5. Single present -> use it.
    if [[ "$have_primary" == "1" ]]; then
        _validate_choice "$primary"
        log_info "hypervisor: $primary (primary, detected)"
        printf '%s' "$primary"
        return 0
    fi
    if [[ "$have_fallback" == "1" ]]; then
        _validate_choice "$fallback"
        log_warn "primary hypervisor '$primary' not detected; using fallback '$fallback'"
        printf '%s' "$fallback"
        return 0
    fi

    # 6. Nothing present -> deps layer must install. Return the primary
    # choice; deps.sh will install it and the next run succeeds.
    _validate_choice "$primary"
    log_warn "no hypervisor detected; will install $primary"
    printf '%s' "$primary"
}
