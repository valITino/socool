#!/usr/bin/env bash
# tests/run-all.sh — master test runner.
#
# Runs every test that can execute on the current host without a live
# hypervisor + lab. Tests that need a live lab (smoke, idempotency,
# destroy-recreate) auto-skip unless SOCOOL_LAB_UP=1.
#
# Exit 0 if everything that ran passed. Exit 1 if anything failed.
# Skipped tests (exit 77 inside a sub-runner) don't count as failures.

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

banner() { printf '\n━━━ %s ━━━\n' "$1"; }

overall_fail=0
summary=()

run() {
    local name="$1" cmd_name="$2"; shift 2
    banner "$name"
    local rc=0
    "$@" || rc=$?
    case "$rc" in
        0)  summary+=("✓ $name"); ;;
        77) summary+=("○ $name (skipped)"); ;;
        *)  summary+=("✗ $name (exit $rc)"); overall_fail=1 ;;
    esac
}

run "parity"     "parity"     bash "$REPO_ROOT/tests/parity/check-parity.sh"
run "preflight-dispatch" "preflight-dispatch" bash "$REPO_ROOT/tests/preflight/test-checks.sh"
run "preflight-mocked"   "preflight-mocked"   bash "$REPO_ROOT/tests/preflight/test-mocked.sh"
run "vagrantfile" "vagrantfile" ruby -W0 "$REPO_ROOT/tests/vagrant/test-vagrantfile.rb"

# Lab-requiring tests — auto-skip if SOCOOL_LAB_UP != 1.
run "smoke"       "smoke"       bash "$REPO_ROOT/tests/smoke/test-smoke.sh"
run "idempotency" "idempotency" bash "$REPO_ROOT/tests/idempotency/test-idempotency.sh" --compare 2>/dev/null || true

# Destroy-recreate is NEVER auto-run; operator must opt in twice.
if [[ "${SOCOOL_DESTROY_CONFIRM:-0}" == "1" && "${SOCOOL_LAB_UP:-0}" == "1" ]]; then
    run "destroy-recreate" "destroy-recreate" bash "$REPO_ROOT/tests/destroy-recreate/test-destroy-recreate.sh"
else
    summary+=("○ destroy-recreate (opt-in only — set SOCOOL_DESTROY_CONFIRM=1 + SOCOOL_LAB_UP=1)")
fi

banner "summary"
printf '%s\n' "${summary[@]}"

[[ "$overall_fail" == "0" ]] || { echo; echo "SOME TESTS FAILED"; exit 1; }
echo; echo "ALL RUN TESTS PASSED"
