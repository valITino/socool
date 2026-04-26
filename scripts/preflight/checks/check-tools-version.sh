#!/usr/bin/env bash
# scripts/preflight/checks/check-tools-version.sh
# Verifies every required host tool that is ALREADY INSTALLED meets
# its minimum version. A missing tool is NOT an error here — deps.sh
# will install it after preflight. We only fail when a tool is present
# but too old.
# Exit 0 on pass; exit 17 on fail.
#
# Minimums (verified 2026-04-24):
#   bash         >= 4.0   (macOS /bin/bash is 3.2; use homebrew bash)
#   git          >= 2.30  (default on all supported distros as of 2024)
#   python3      >= 3.8   (PyYAML wheel availability)
#   packer       >= 1.10  (HCL2 required_plugins block)
#   vagrant      >= 2.3   (libvirt plugin + Ruby 3 compat)
#   VirtualBox   >= 7.0   (modern API; only probed if present)
#   qemu-system  >= 6.0   (only probed if present)

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

detect_host

# _vercmp a b  => prints -1, 0, or 1 (bash-native, avoids dpkg/sort -V
# dependencies which aren't on every host).
_vercmp() {
    local a="$1" b="$2"
    if [[ "$a" == "$b" ]]; then printf '0'; return; fi
    local IFS_SAVE="$IFS"; IFS=.
    # shellcheck disable=SC2206 # word-split is intentional on dots
    local aa=($a) bb=($b)
    IFS="$IFS_SAVE"
    local i max=$(( ${#aa[@]} > ${#bb[@]} ? ${#aa[@]} : ${#bb[@]} ))
    for (( i = 0; i < max; i++ )); do
        local ai="${aa[$i]:-0}" bi="${bb[$i]:-0}"
        # Strip non-digits (e.g. "1.10.3-rc1" -> "1", "10", "3")
        ai="${ai%%[!0-9]*}"
        bi="${bi%%[!0-9]*}"
        ai="${ai:-0}"
        bi="${bi:-0}"
        if (( 10#$ai > 10#$bi )); then printf '1'; return; fi
        if (( 10#$ai < 10#$bi )); then printf -- '-1'; return; fi
    done
    printf '0'
}

_check_min() {
    local name="$1" min="$2" actual="$3"
    if [[ "$(_vercmp "$actual" "$min")" == "-1" ]]; then
        die 17 "$name version $actual is older than the minimum $min; upgrade via your package manager and re-run."
    fi
    log_info "$name: $actual (>= $min)"
}

# 1. bash — already running, but standalone runs still need the check.
_bash_ver="${BASH_VERSION%%[^0-9.]*}"
_check_min bash 4.0 "$_bash_ver"

# 2. git
if command -v git >/dev/null 2>&1; then
    ver="$(git --version 2>/dev/null | awk '{print $3}')"
    _check_min git 2.30 "$ver"
fi

# 3. python3
if command -v python3 >/dev/null 2>&1; then
    ver="$(python3 --version 2>&1 | awk '{print $2}')"
    _check_min python3 3.8 "$ver"
fi

# 4. packer
if command -v packer >/dev/null 2>&1; then
    # `packer --version` may print multiple lines (release notes); we
    # capture the full output first to avoid SIGPIPE on `cmd | head -1`
    # under `set -o pipefail`.
    _packer_out="$(packer --version 2>/dev/null || true)"
    ver="$(printf '%s\n' "$_packer_out" | head -n1 | sed 's/^v//')"
    _check_min packer 1.10 "$ver"
fi

# 5. vagrant
if command -v vagrant >/dev/null 2>&1; then
    ver="$(vagrant --version 2>/dev/null | awk '{print $2}')"
    _check_min vagrant 2.3 "$ver"
fi

# 6. VirtualBox
if command -v VBoxManage >/dev/null 2>&1; then
    # `VBoxManage --version` → "7.1.4r165100"
    ver="$(VBoxManage --version 2>/dev/null | sed 's/r.*$//')"
    _check_min VirtualBox 7.0 "$ver"
fi

# 7. qemu-system-* — extract the first X.Y or X.Y.Z pattern from the
# first line of --version output. QEMU on Debian prints
# "QEMU emulator version 8.2.2 (Debian 1:8.2.2+ds-0ubuntu1.16)"
# where field-N parsing is fragile; a regex pull of the upstream
# version is sturdier.
for _qemu in qemu-system-x86_64 qemu-system-aarch64; do
    if command -v "$_qemu" >/dev/null 2>&1; then
        # Capture full output before piping into `head` — qemu prints
        # several lines (version, copyright, license) and `head -1` would
        # SIGPIPE the producer under `set -o pipefail`.
        _qemu_out="$("$_qemu" --version 2>/dev/null || true)"
        ver="$(printf '%s\n' "$_qemu_out" | head -n1 \
            | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n1 || true)"
        [[ -z "$ver" ]] && continue
        _check_min "$_qemu" 6.0 "$ver"
    fi
done

log_info "tools-version: all installed tools meet their minimums"
