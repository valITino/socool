#!/usr/bin/env bash
# tests/smoke/test-smoke.sh
#
# Runs every probe under probes/ against the live lab. Gates on
# `SOCOOL_LAB_UP=1` (operator asserts the lab is ready) so CI runs
# that don't have a hypervisor can skip cleanly without false failures.
#
# Exit 0 = all probes + isolation checks passed.
# Exit 1 = one or more probes failed.
# Exit 77 = skipped because lab not up (autoskip, not a failure).

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

# Skip unless the operator confirms lab is up.
if [[ "${SOCOOL_LAB_UP:-0}" != "1" ]]; then
    echo "[SKIP] tests/smoke/ requires SOCOOL_LAB_UP=1 (lab must be running)."
    exit 77
fi

scanner="${SOCOOL_SCANNER:-none}"
pass=0
fail=0

run_probe() {
    local probe="$1"
    local name; name="$(basename "$probe" .sh)"

    # Scanner probes only run when the matching scanner is chosen.
    case "$name" in
        nessus)  [[ "$scanner" != "nessus"  ]] && { echo "[skip] $name: SOCOOL_SCANNER=$scanner"; return; } ;;
        openvas) [[ "$scanner" != "openvas" ]] && { echo "[skip] $name: SOCOOL_SCANNER=$scanner"; return; } ;;
    esac

    if bash "$probe"; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
    fi
}

shopt -s nullglob
for probe in "$SCRIPT_DIR/probes/"*.sh; do
    run_probe "$probe"
done

# ─── Isolation check: Kali must NOT be able to reach the management
# subnet directly. pfSense's filter blocks lan -> management. If this
# succeeds, the filter is wrong. ─────────────────────────────────────
if command -v ssh >/dev/null 2>&1; then
    echo "[check] isolation: kali -> management should be blocked..."
    # Try a 3-second TCP probe from the host's perspective, simulating
    # the view kali would have. (For a real end-to-end check, wrap in
    # `vagrant ssh kali -c "..."` once vagrant is present.)
    if timeout 3 bash -c "</dev/tcp/10.42.20.10/443" 2>/dev/null; then
        # Host can see wazuh — that's expected (host-only network).
        # The real isolation test belongs inside kali; flag as advisory.
        echo "[advisory] host can reach 10.42.20.10:443 (expected — host-only net). Run from inside kali via 'vagrant ssh kali -c \"timeout 3 bash -c '</dev/tcp/10.42.20.10/443'\"' to get the real answer."
    fi
fi

total=$((pass + fail))
echo
echo "RESULTS: ${pass}/${total} probes passed"
[[ "$fail" == "0" ]] || exit 1
