#!/usr/bin/env bash
# tests/idempotency/test-idempotency.sh
#
# Two-phase test: `--snapshot` records the state after a successful
# provision; `--compare` re-runs setup.sh and asserts the state hasn't
# drifted. Separated into two invocations so the operator controls
# exactly when the re-run happens.
#
# Exit 0 on identical state; 1 on drift; 77 on skip (lab not up).

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
STATE_DIR="$REPO_ROOT/.socool-cache/idempotency"

if [[ "${SOCOOL_LAB_UP:-0}" != "1" ]]; then
    echo "[SKIP] idempotency test requires SOCOOL_LAB_UP=1 (lab must be running)."
    exit 77
fi

mode="${1:-}"
[[ "$mode" == "--snapshot" || "$mode" == "--compare" ]] || {
    echo "usage: $0 --snapshot | --compare" >&2
    exit 2
}

mkdir -p "$STATE_DIR"

# ─── Fingerprint the lab state ───────────────────────────────────────
# Each fingerprint is written to a separate file so --compare can
# diff them one concern at a time.
capture() {
    local target="$1"

    # 1. Vagrant status — verbatim output (trimmed of timing noise).
    ( cd "$REPO_ROOT/vagrant" && vagrant status --machine-readable 2>/dev/null ) \
        | grep -E ',(state|provider-name),' | sort > "$target/vagrant-status.txt" || true

    # 2. Packer manifests per VM (Packer stamps paths + checksums).
    for m in "$REPO_ROOT"/packer/*/artifacts/manifest.json; do
        [[ -f "$m" ]] || continue
        vm="$(basename "$(dirname "$(dirname "$m")")")"
        # Strip timestamp fields so runs that only differ in build time
        # don't count as drift. Keep file paths, checksums, source IDs.
        python3 -c '
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
for b in data.get("builds", []):
    for k in ("build_time", "packer_run_uuid"):
        b.pop(k, None)
print(json.dumps(data, sort_keys=True, indent=2))
' "$m" > "$target/packer-$vm.json" || true
    done

    # 3. Box-file mtimes (re-runs must not touch the .box).
    box_dir="${SOCOOL_BOX_OUTPUT_DIR:-$REPO_ROOT/.socool-cache/boxes}"
    if [[ -d "$box_dir" ]]; then
        ( cd "$box_dir" && find . -name '*.box' -printf '%p %T@\n' | sort ) \
            > "$target/box-mtimes.txt"
    fi

    # 4. Credentials manifests (SHA256 — the passwords themselves must
    # NOT change between runs, so the hash of the file must match).
    for c in "$REPO_ROOT"/packer/*/artifacts/credentials.json; do
        [[ -f "$c" ]] || continue
        vm="$(basename "$(dirname "$(dirname "$c")")")"
        sha256sum "$c" | awk '{print $1}' > "$target/credentials-$vm.sha256"
    done

    # 5. Host package state — list of the deps we manage.
    {
        for cmd in git python3 packer vagrant VBoxManage qemu-system-x86_64; do
            if command -v "$cmd" >/dev/null 2>&1; then
                printf '%s %s\n' "$cmd" "$(command -v "$cmd")"
            fi
        done
    } | sort > "$target/host-tools.txt"
}

case "$mode" in
    --snapshot)
        before="$STATE_DIR/before"
        mkdir -p "$before"
        capture "$before"
        echo "snapshot written to $before"
        echo "Now re-run ./setup.sh --yes and then '$0 --compare'."
        ;;
    --compare)
        before="$STATE_DIR/before"
        after="$STATE_DIR/after"
        [[ -d "$before" ]] || { echo "no --snapshot found; run '$0 --snapshot' first." >&2; exit 2; }
        mkdir -p "$after"
        capture "$after"

        fail=0
        for file in "$before"/*; do
            name="$(basename "$file")"
            if ! diff -u "$file" "$after/$name" >/dev/null 2>&1; then
                echo "✗ drift in $name:"
                diff -u "$file" "$after/$name" | sed 's/^/  /' || true
                fail=1
            else
                echo "✓ $name unchanged"
            fi
        done

        [[ "$fail" == "0" ]] || exit 1
        echo; echo "IDEMPOTENT: no drift between runs."
        ;;
esac
