#!/usr/bin/env bash
# scripts/preflight/run-all.sh — runs every check under checks/.
#
# Each check is its own script in scripts/preflight/checks/<name>.sh,
# executable, and exits with a code in 10..19 on failure. A check prints
# a one-line remediation sentence on failure.
#
# Exit codes:
#   0  — all checks passed
#   10 — at least one check failed (with its own code in 10..19 logged)
#   11..19 — reserved for individual check codes (see README.md)

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

checks_dir="$SCRIPT_DIR/checks"

if [[ ! -d "$checks_dir" ]]; then
    die 10 "preflight checks directory missing: $checks_dir"
fi

shopt -s nullglob
checks=("$checks_dir"/*.sh)
shopt -u nullglob

if [[ "${#checks[@]}" -eq 0 ]]; then
    # Step 4 has not landed yet. Report clearly and let the caller decide.
    log_warn "no preflight checks installed (scripts/preflight/checks/ is empty; Step 4 pending)"
    log_warn "proceeding without preflight. Set SOCOOL_STRICT_PREFLIGHT=1 to fail-fast instead."
    if [[ "${SOCOOL_STRICT_PREFLIGHT:-0}" == "1" ]]; then
        die 10 "no preflight checks installed and SOCOOL_STRICT_PREFLIGHT=1"
    fi
    exit 0
fi

log_info "running ${#checks[@]} preflight check(s)"
failed=()
for check in "${checks[@]}"; do
    name="$(basename -- "$check" .sh)"
    log_debug "preflight: $name"
    if ! bash -- "$check"; then
        rc=$?
        failed+=("$name ($rc)")
    fi
done

if [[ "${#failed[@]}" -gt 0 ]]; then
    for f in "${failed[@]}"; do
        log_error "preflight failed: $f"
    done
    die 10 "${#failed[@]} preflight check(s) failed; see messages above and docs/troubleshooting.md"
fi

log_info "all preflight checks passed"
