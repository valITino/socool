#!/usr/bin/env bash
# tests/parity/check-uninstall-parity.sh — enforces that uninstall.sh and
# uninstall.ps1 stay in lock-step on what the user sees.
#
# Mirrors tests/parity/check-parity.sh but for the uninstall entry points.
# Three checks:
#   1. Every uninstall-specific SOCOOL_* env var declared in .env.example
#      is referenced by the bash and pwsh uninstall code paths.
#   2. Every CLI flag has a matching pwsh parameter (or alias).
#   3. Curated banner / prompt titles appear on both sides.
#
# This test does NOT execute either script.

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

SH="$REPO_ROOT/uninstall.sh"
PS="$REPO_ROOT/uninstall.ps1"
SH_LIB="$REPO_ROOT/scripts/uninstall/run-all.sh"
PS_LIB="$REPO_ROOT/scripts/uninstall/run-all.ps1"
ENV_EXAMPLE="$REPO_ROOT/.env.example"

[[ -f "$SH" ]]          || { echo "uninstall.sh not found: $SH"           >&2; exit 1; }
[[ -f "$PS" ]]          || { echo "uninstall.ps1 not found: $PS"          >&2; exit 1; }
[[ -f "$SH_LIB" ]]      || { echo "scripts/uninstall/run-all.sh missing"  >&2; exit 1; }
[[ -f "$PS_LIB" ]]      || { echo "scripts/uninstall/run-all.ps1 missing" >&2; exit 1; }
[[ -f "$ENV_EXAMPLE" ]] || { echo ".env.example not found: $ENV_EXAMPLE" >&2; exit 1; }

fail=0

# ── 1. Uninstall-specific env vars exist on both sides ────────────────
# Pull every SOCOOL_UNINSTALL_* line from .env.example, then check both
# the entrypoint and the helper for each one.
canonical_vars="$(awk '
    /^SOCOOL_UNINSTALL_[A-Z_]+=/ {
        name=$1; sub(/=.*/, "", name);
        print name
    }
' "$ENV_EXAMPLE" | sort -u)"

if [[ -z "$canonical_vars" ]]; then
    echo "✗ no SOCOOL_UNINSTALL_* vars found in .env.example" >&2
    exit 1
fi

sh_missing=""
ps_missing=""
while IFS= read -r var; do
    [[ -z "$var" ]] && continue
    grep -qF -- "$var" "$SH" "$SH_LIB" \
        || sh_missing="${sh_missing}${var}\n"
    grep -qF -- "$var" "$PS" "$PS_LIB" \
        || ps_missing="${ps_missing}${var}\n"
done <<< "$canonical_vars"

if [[ -n "$sh_missing" ]]; then
    echo "✗ uninstall.sh / scripts/uninstall/run-all.sh missing env vars:" >&2
    printf '%b' "$sh_missing" | sed 's/^/  - /' >&2
    fail=1
fi
if [[ -n "$ps_missing" ]]; then
    echo "✗ uninstall.ps1 / scripts/uninstall/run-all.ps1 missing env vars:" >&2
    printf '%b' "$ps_missing" | sed 's/^/  - /' >&2
    fail=1
fi
if [[ -z "$sh_missing" && -z "$ps_missing" ]]; then
    echo "✓ uninstall env-var parity: $(printf '%s\n' "$canonical_vars" | grep -c .) variables on both sides"
fi

# ── 2. Flag surface ────────────────────────────────────────────────────
_sh_flags=(--help --version --yes --dry-run --keep-vms --keep-boxes --keep-plugins --keep-cache --env --packages --all --hypervisor --log-level)
declare -A _ps_flag_for=(
    [--help]='-Help'
    [--version]='-Version'
    [--yes]='-Yes'
    [--dry-run]='-DryRun'
    [--keep-vms]='-KeepVms'
    [--keep-boxes]='-KeepBoxes'
    [--keep-plugins]='-KeepPlugins'
    [--keep-cache]='-KeepCache'
    [--env]='-EnvFile'
    [--packages]='-Packages'
    [--all]='-All'
    [--hypervisor]='-Hypervisor'
    [--log-level]='-LogLevel'
)
for f in "${_sh_flags[@]}"; do
    grep -qF -- "$f" "$SH" || { echo "✗ flag $f missing from uninstall.sh" >&2; fail=1; }
    psf="${_ps_flag_for[$f]}"
    grep -qF -- "$psf" "$PS" || { echo "✗ flag $psf (<- $f) missing from uninstall.ps1" >&2; fail=1; }
done
[[ "$fail" == "0" ]] && echo "✓ uninstall flag-surface parity: ${#_sh_flags[@]} flags mirrored"

# ── 3. Curated banner titles present on both sides ─────────────────────
_titles=(
    "SOCool uninstall"
    "Uninstall: vagrant destroy"
    "Uninstall: vagrant box remove"
    "Uninstall: vagrant plugins"
    "Uninstall: caches and artifacts"
    "Uninstall: .env"
    "Uninstall: host packages"
    "Final step: remove the repo directory"
    "SOCool uninstall complete"
)
for title in "${_titles[@]}"; do
    grep -qF -- "$title" "$SH" "$SH_LIB" \
        || { echo "✗ bash side missing banner title: $title" >&2; fail=1; }
    grep -qF -- "$title" "$PS" "$PS_LIB" \
        || { echo "✗ pwsh side missing banner title: $title" >&2; fail=1; }
done
[[ "$fail" == "0" ]] && echo "✓ uninstall banner-title parity: ${#_titles[@]} titles on both sides"

# ── 4. Exit-code documentation ─────────────────────────────────────────
# Codes 80..86 must be in docs/troubleshooting.md (per shell-scripting skill).
TS="$REPO_ROOT/docs/troubleshooting.md"
for code in 80 81 82 83 84 85 86; do
    grep -qE "\` *$code *\`" "$TS" \
        || { echo "✗ exit code $code missing from docs/troubleshooting.md" >&2; fail=1; }
done
[[ "$fail" == "0" ]] && echo "✓ uninstall exit codes 80–86 documented"

if [[ "$fail" == "0" ]]; then
    echo "UNINSTALL PARITY OK"
    exit 0
else
    echo "UNINSTALL PARITY FAIL" >&2
    exit 1
fi
