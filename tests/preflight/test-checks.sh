#!/usr/bin/env bash
# tests/preflight/test-checks.sh — lightweight validation of the
# preflight-check surface. Runs each .sh check on the current host and
# asserts:
#   1. Every check in scripts/preflight/README.md's exit-code table
#      has a corresponding check-*.sh file.
#   2. Every check-*.sh file has a documented exit-code row.
#   3. Every check exits with 0 OR with its documented code (11..19).
#   4. Every failing check writes at least one line to stderr.
#   5. Every check has a PowerShell twin (check-*.ps1).
#
# Does NOT execute the .ps1 files (we're usually on a Linux CI runner);
# Step 7 adds full cross-platform smoke testing.

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
CHECKS_DIR="$REPO_ROOT/scripts/preflight/checks"
README="$REPO_ROOT/scripts/preflight/README.md"

[[ -d "$CHECKS_DIR" ]] || { echo "checks dir missing: $CHECKS_DIR" >&2; exit 1; }
[[ -f "$README" ]]     || { echo "README missing: $README"        >&2; exit 1; }

fail=0

# Extract the documented check names from the README exit-code table.
# The table rows look like: "| 11 | `check-os-arch` — ... |"
documented="$(grep -oE '`check-[a-z-]+`' "$README" | tr -d '`' | sort -u)"

# Extract present check names from the filesystem (strip .sh).
present_sh="$(find "$CHECKS_DIR" -maxdepth 1 -name 'check-*.sh' -printf '%f\n' | sed 's/\.sh$//' | sort -u)"
present_ps1="$(find "$CHECKS_DIR" -maxdepth 1 -name 'check-*.ps1' -printf '%f\n' | sed 's/\.ps1$//' | sort -u)"

# 1 + 2. Documented ↔ present equality.
if [[ "$documented" != "$present_sh" ]]; then
    echo "✗ documented vs present-.sh drift:" >&2
    diff <(printf '%s\n' "$documented") <(printf '%s\n' "$present_sh") | sed 's/^/  /' >&2
    fail=1
else
    echo "✓ documentation parity: $(printf '%s\n' "$documented" | wc -l | tr -d ' ') checks documented and present as .sh"
fi

# 5. Every .sh has a .ps1 twin.
if [[ "$present_sh" != "$present_ps1" ]]; then
    echo "✗ .sh/.ps1 twin parity broken:" >&2
    diff <(printf '%s\n' "$present_sh") <(printf '%s\n' "$present_ps1") | sed 's/^/  /' >&2
    fail=1
else
    echo "✓ .sh/.ps1 parity: every check has both platform twins"
fi

# 3 + 4. Run each .sh check and validate exit code + stderr.
# Use an array (not a space-separated string) because the top-of-script
# `IFS=$'\n\t'` removes space from the split set.
allowed_codes=(0 11 12 13 14 15 16 17 18 19)
while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    path="$CHECKS_DIR/$name.sh"
    err_file="$(mktemp)"
    rc=0
    bash -- "$path" 2>"$err_file" >/dev/null || rc=$?
    err_content="$(cat -- "$err_file")"
    rm -f -- "$err_file"

    # Exit code in allowed range?
    found=0
    for c in "${allowed_codes[@]}"; do
        if [[ "$rc" == "$c" ]]; then found=1; break; fi
    done
    if [[ "$found" != "1" ]]; then
        echo "✗ $name: undocumented exit code $rc (allowed: ${allowed_codes[*]})" >&2
        fail=1
        continue
    fi

    # Failure must include a remediation sentence.
    if [[ "$rc" != "0" ]]; then
        if [[ -z "$err_content" ]]; then
            echo "✗ $name: exited $rc but wrote nothing to stderr (remediation sentence required)" >&2
            fail=1
            continue
        fi
    fi
    echo "✓ $name: exit=$rc (expected 0 or documented code for this host)"
done <<< "$present_sh"

if [[ "$fail" == "0" ]]; then
    echo "PREFLIGHT TEST OK"
    exit 0
else
    echo "PREFLIGHT TEST FAIL" >&2
    exit 1
fi
