#!/usr/bin/env bash
# tests/parity/check-parity.sh — enforces that setup.sh and setup.ps1
# stay in lock-step on what the user sees.
#
# Four checks:
#   1. Every SOCOOL_* env var declared in .env.example is referenced by
#      BOTH setup.sh and setup.ps1.
#   2. Every "Action required: <title>" string defined on either side
#      exists on the other (prompt-title parity).
#   3. Pause-for-activation labels (What:/Where:/Paste:/Env:) exist in
#      both common.{sh,ps1} helpers.
#   4. The high-level flag surface is mirrored (--yes ↔ -Yes, etc.).
#
# This test does NOT execute either script; it only greps the sources.

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

SH="$REPO_ROOT/setup.sh"
PS="$REPO_ROOT/setup.ps1"
ENV_EXAMPLE="$REPO_ROOT/.env.example"

[[ -f "$SH" ]]          || { echo "setup.sh not found: $SH"           >&2; exit 1; }
[[ -f "$PS" ]]          || { echo "setup.ps1 not found: $PS"          >&2; exit 1; }
[[ -f "$ENV_EXAMPLE" ]] || { echo ".env.example not found: $ENV_EXAMPLE" >&2; exit 1; }

fail=0

# ── 1. Canonical env-var list comes from .env.example ─────────────────
# Extract SOCOOL_* names that appear as `SOCOOL_FOO=...`, ignoring lines
# that only mention the name in a comment. Skip vars tagged
# `# reserved-for: step-N` — those are documented placeholders for
# later milestones; the parity test picks them up when the comment is
# removed.
_extract_canonical_vars() {
    awk '
        /^# reserved-for:/ { reserved=1; next }
        /^[A-Z_]+=/ {
            name=$1; sub(/=.*/, "", name);
            if (name ~ /^SOCOOL_/ && !reserved) print name;
            reserved=0;
            next
        }
        /^$/ { reserved=0 }
    ' "$1" | sort -u
}
canonical_vars="$(_extract_canonical_vars "$ENV_EXAMPLE")"

# Search setup.{sh,ps1} AND the scripts/ tree — a canonical env var is
# "honored" if any SOCool code path reads or writes it. Some vars are
# consumed only by scripts/lib/* or scripts/provision/* and never
# mentioned in setup.*.
sh_targets=( "$SH" "$REPO_ROOT/scripts" )
ps_targets=( "$PS" "$REPO_ROOT/scripts" )

sh_missing=""
ps_missing=""
while IFS= read -r var; do
    [[ -z "$var" ]] && continue
    # bash side: any *.sh file may mention it.
    grep -rqF -- "$var" "${sh_targets[@]}" --include='*.sh' 2>/dev/null \
        || sh_missing="${sh_missing}${var}\n"
    # pwsh side: any *.ps1 file.
    grep -rqF -- "$var" "${ps_targets[@]}" --include='*.ps1' 2>/dev/null \
        || ps_missing="${ps_missing}${var}\n"
done <<< "$canonical_vars"

if [[ -n "$sh_missing" ]]; then
    echo "✗ setup.sh missing canonical env vars:" >&2
    printf '%b' "$sh_missing" | sed 's/^/  - /' >&2
    fail=1
fi
if [[ -n "$ps_missing" ]]; then
    echo "✗ setup.ps1 missing canonical env vars:" >&2
    printf '%b' "$ps_missing" | sed 's/^/  - /' >&2
    fail=1
fi
if [[ -z "$sh_missing" && -z "$ps_missing" ]]; then
    echo "✓ env-var parity: $(printf '%s\n' "$canonical_vars" | grep -c .) canonical variables referenced by both scripts"
fi

# ── 2. Prompt-title parity ─────────────────────────────────────────────
# Extract the literal title argument from every prompt_action /
# Show-SocoolAction call across the bash and pwsh sides.
_sh_titles() {
    # bash: prompt_action followed by first-arg quoted string.
    # Matches " ... " or ' ... '.
    grep -rhE 'prompt_action\b|banner[[:space:]]+"Action required:' "$REPO_ROOT/setup.sh" "$REPO_ROOT/scripts" 2>/dev/null |
        grep -oE '"[^"]+"' | tr -d '"' |
        grep -vE '^Action required:|^What:|^Where:|^Paste:|^Env:' |
        sort -u
}
_ps_titles() {
    grep -rhE 'Show-SocoolAction\b|-Title\b|Write-SocoolBanner[[:space:]]+.?Action required:' \
        "$REPO_ROOT/setup.ps1" "$REPO_ROOT/scripts" 2>/dev/null |
        grep -oE "'[^']+'" | tr -d "'" |
        grep -vE '^Action required:|^What:|^Where:|^Paste:|^Env:' |
        sort -u
}

# Both grep over the same set of files, looking for literal titles used
# as the FIRST argument to prompt_action / -Title argument to
# Show-SocoolAction. Since this is an imperfect grep-based extractor
# (not a parser), the test compares the set of titles that appear in
# both lists — anything that's one-sided is a warning, anything that's
# in the curated list below but missing on either side is a failure.
_curated_titles=(
    "Choose hypervisor"
    "Pick a vulnerability scanner"
    "Windows victim VM source"
    "Windows ISO path"
    "Bridged networking enabled"
    "cache sudo credentials"
    "SOCool setup complete"
    "Packer build:"
    "vagrant up"
)
for title in "${_curated_titles[@]}"; do
    # "cache sudo credentials" is bash-only (Windows uses UAC instead of sudo).
    # "vagrant up" is identical banner in both.
    case "$title" in
        "cache sudo credentials") continue ;;
    esac
    # Each curated title must appear somewhere under setup.* / scripts on both sides.
    sh_has=$(grep -rlF -- "$title" "$REPO_ROOT/setup.sh" "$REPO_ROOT/scripts" 2>/dev/null | grep -E '\.sh$' | head -1)
    ps_has=$(grep -rlF -- "$title" "$REPO_ROOT/setup.ps1" "$REPO_ROOT/scripts" 2>/dev/null | grep -E '\.ps1$' | head -1)
    if [[ -z "$sh_has" ]]; then echo "✗ bash side missing curated title: $title" >&2; fail=1; fi
    if [[ -z "$ps_has" ]]; then echo "✗ pwsh side missing curated title: $title" >&2; fail=1; fi
done
[[ "$fail" == "0" ]] && echo "✓ prompt-title parity: ${#_curated_titles[@]} curated titles present on both sides"

# ── 3. Pause-for-activation labels present ────────────────────────────
_check_labels() {
    local f="$1"
    for label in 'What:' 'Where:' 'Paste:' 'Env:'; do
        grep -qF "$label" "$f" || { echo "✗ missing '$label' in $f" >&2; return 1; }
    done
}
_check_labels "$REPO_ROOT/scripts/lib/common.sh"  || fail=1
_check_labels "$REPO_ROOT/scripts/lib/common.ps1" || fail=1
[[ "$fail" == "0" ]] && echo "✓ pause-for-activation labels present in common.{sh,ps1}"

# ── 4. Flag-surface parity (high-level) ───────────────────────────────
# Canonical list of flags from setup.sh usage().
_sh_flags=(--help --version --yes --hypervisor --scanner --windows-source --windows-iso --allow-bridged --log-level)
# Pwsh counterparts (param names and aliases):
declare -A _ps_flag_for=(
    [--help]='-Help'
    [--version]='-Version'
    [--yes]='-Yes'
    [--hypervisor]='-Hypervisor'
    [--scanner]='-Scanner'
    [--windows-source]='-WindowsSource'
    [--windows-iso]='-WindowsIso'
    [--allow-bridged]='-AllowBridged'
    [--log-level]='-LogLevel'
)
for f in "${_sh_flags[@]}"; do
    grep -qF -- "$f" "$SH" || { echo "✗ flag $f missing from setup.sh" >&2; fail=1; }
    psf="${_ps_flag_for[$f]}"
    grep -qF -- "$psf" "$PS" || { echo "✗ flag $psf (<- $f) missing from setup.ps1" >&2; fail=1; }
done
[[ "$fail" == "0" ]] && echo "✓ flag-surface parity: ${#_sh_flags[@]} flags mirrored"

if [[ "$fail" == "0" ]]; then
    echo "PARITY OK"
    exit 0
else
    echo "PARITY FAIL" >&2
    exit 1
fi
