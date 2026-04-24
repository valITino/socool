# tests/idempotency/

Asserts that `setup.sh` / `setup.ps1` is idempotent: a second run
after a successful provision must produce **no new changes** — same
package versions, same generated files, same box artefacts, same VMs
in the same state.

Requires a **live lab** (run after `setup.sh` completes). Gated by
`SOCOOL_LAB_UP=1`.

## What it checks

1. **Deps install layer** — each dep-install path in
   `scripts/lib/deps.sh` must short-circuit when the tool is already
   installed (`command -v` returns 0). No `apt-get install` / `brew
   install` invocations observed in the second run.
2. **Packer box artefacts** — `packer/<vm>/artifacts/manifest.json`
   unchanged between runs; `.socool-cache/boxes/<box>.box` mtime
   unchanged.
3. **Vagrant state** — `vagrant status` shows identical state before
   and after the second run.
4. **Rotated credentials** — the credentials manifests are NOT
   regenerated on a re-run; the passwords the user got the first
   time are still valid.

## Running

```bash
# First run (fresh)
./setup.sh --yes

# Snapshot state
SOCOOL_LAB_UP=1 bash tests/idempotency/test-idempotency.sh --snapshot

# Run again
./setup.sh --yes

# Diff
SOCOOL_LAB_UP=1 bash tests/idempotency/test-idempotency.sh --compare
```

Exit 0 on identical state; 1 on any drift.
