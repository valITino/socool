#!/usr/bin/env bash
# tests/destroy-recreate/test-destroy-recreate.sh
#
# Destructive integration test: full teardown + rebuild + smoke.
# Gated on both SOCOOL_LAB_UP=1 AND SOCOOL_DESTROY_CONFIRM=1 so that a
# casual `run-all.sh` cannot accidentally trigger it.
#
# Exit 0 on success; 1 on any assertion failure; 77 on skip.

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

if [[ "${SOCOOL_LAB_UP:-0}" != "1" ]]; then
    echo "[SKIP] destroy-recreate test requires SOCOOL_LAB_UP=1."
    exit 77
fi
if [[ "${SOCOOL_DESTROY_CONFIRM:-0}" != "1" ]]; then
    echo "[SKIP] destroy-recreate test requires SOCOOL_DESTROY_CONFIRM=1 (destructive test)."
    exit 77
fi

banner() { printf '\n━━━ %s ━━━\n' "$1" >&2; }

banner "Phase 1: teardown"
( cd "$REPO_ROOT/vagrant" && vagrant destroy -f )

# Assert no VMs left.
if ( cd "$REPO_ROOT/vagrant" && vagrant status --machine-readable 2>/dev/null | grep -Eq ',state,(running|saved|poweroff|aborted)' ); then
    echo "[FAIL] vagrant status still shows defined VMs after destroy -f" >&2
    exit 1
fi

banner "Phase 2: rebuild"
(
    cd "$REPO_ROOT"
    # SOCOOL_YES=1 to avoid interactive prompts during the rebuild.
    # Every other var must already be in the environment (SOCOOL_HYPERVISOR,
    # SOCOOL_SCANNER, SOCOOL_WINDOWS_SOURCE, etc.) or in .env.
    SOCOOL_YES=1 ./setup.sh
)

banner "Phase 3: smoke"
SOCOOL_LAB_UP=1 SOCOOL_SCANNER="${SOCOOL_SCANNER:-none}" \
    bash "$REPO_ROOT/tests/smoke/test-smoke.sh"

banner "Phase 4: manifest comparison"
# We expect Packer manifests to match bit-for-bit when inputs are
# unchanged (same ISOs, same checksums). Credentials manifests are
# expected to differ (fresh CSPRNG rotation per build).
fail=0
for m in "$REPO_ROOT"/packer/*/artifacts/manifest.json; do
    [[ -f "$m" ]] || continue
    vm="$(basename "$(dirname "$(dirname "$m")")")"
    backup="$REPO_ROOT/.socool-cache/destroy-recreate/packer-$vm.json"
    if [[ ! -f "$backup" ]]; then
        mkdir -p "$(dirname "$backup")"
        cp "$m" "$backup"
        echo "  first run: captured baseline for $vm"
        continue
    fi
    # Strip timestamps before diffing.
    norm() {
        python3 -c '
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
for b in data.get("builds", []):
    for k in ("build_time", "packer_run_uuid"):
        b.pop(k, None)
print(json.dumps(data, sort_keys=True, indent=2))
' "$1"
    }
    if ! diff -u <(norm "$backup") <(norm "$m") >/dev/null 2>&1; then
        echo "[FAIL] packer manifest drift for $vm" >&2
        diff -u <(norm "$backup") <(norm "$m") | sed 's/^/  /' >&2 || true
        fail=1
    else
        echo "✓ $vm: packer manifest identical"
    fi
done
[[ "$fail" == "0" ]] || exit 1

banner "DESTROY-RECREATE: end state matches baseline"
