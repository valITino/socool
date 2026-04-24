#!/usr/bin/env bash
# scripts/lib/common.sh — shared bash helpers for SOCool.
#
# Sourced by setup.sh and anything under scripts/. Public ABI:
#
#   detect_host                                -> sets SOCOOL_OS, SOCOOL_ARCH
#   log_debug / log_info / log_warn / log_error <msg>
#   die <exit_code> <message>                  -> print and exit
#   banner <title>                             -> print framed title
#   prompt_action <title> <what> <where> <paste> <env_name>
#   prompt_with_default <name> <question> <default> <env_name>
#   prompt_yes_no <name> <question> <default:y|n> <env_name>
#   require_tty_or_env <env_name>              -> exit 64 if neither
#   load_env                                   -> source .env if present
#   lab_config_get <jq-path>                   -> read from config/lab.yml
#   ensure_secret_umask                        -> umask 077 for this shell

set -euo pipefail
IFS=$'\n\t'

# Guard against double-source.
if [[ "${_SOCOOL_COMMON_LOADED:-}" == "1" ]]; then
    return 0
fi
_SOCOOL_COMMON_LOADED=1

# Resolve the repo root from this file's location (scripts/lib/common.sh).
# Lowercase identifiers — these are internal to the bash scripts and are
# intentionally not in the user-facing SOCOOL_* env-var namespace.
_socool_lib_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC2034 # referenced from sibling scripts after sourcing
socool_repo_root="$(cd -- "$_socool_lib_dir/../.." && pwd)"

# ────────────────────────────────────────────────────────────────────────
# Logging
# ────────────────────────────────────────────────────────────────────────

# Levels: debug=10, info=20, warn=30, error=40. Default info.
_socool_log_level_num() {
    case "${SOCOOL_LOG_LEVEL:-info}" in
        debug) printf '%s\n' 10 ;;
        info)  printf '%s\n' 20 ;;
        warn)  printf '%s\n' 30 ;;
        error) printf '%s\n' 40 ;;
        *)     printf '%s\n' 20 ;;
    esac
}

_socool_log() {
    local level_num="$1" tag="$2"; shift 2
    local current; current="$(_socool_log_level_num)"
    if (( level_num < current )); then
        return 0
    fi
    # Tag is fixed-width for readability; message goes to stderr so stdout
    # stays clean for machine-parseable output (e.g., the final summary).
    printf '[%-5s] %s\n' "$tag" "$*" >&2
}

log_debug() { _socool_log 10 DEBUG "$@"; }
log_info()  { _socool_log 20 INFO  "$@"; }
log_warn()  { _socool_log 30 WARN  "$@"; }
log_error() { _socool_log 40 ERROR "$@"; }

# die <exit_code> <message> — print and exit.
die() {
    local code="$1"; shift
    log_error "$*"
    exit "$code"
}

# banner <title> — print framed title to stderr.
banner() {
    local title="$1"
    printf '\n━━━ %s ━━━\n' "$title" >&2
}

# ────────────────────────────────────────────────────────────────────────
# Host detection
# ────────────────────────────────────────────────────────────────────────

# detect_host — sets SOCOOL_OS and SOCOOL_ARCH.
#   SOCOOL_OS   one of: linux, darwin, windows, unknown
#   SOCOOL_ARCH one of: x86_64, aarch64, unknown
detect_host() {
    local uname_s uname_m
    uname_s="$(uname -s 2>/dev/null || printf 'unknown')"
    uname_m="$(uname -m 2>/dev/null || printf 'unknown')"

    case "$uname_s" in
        Linux)         SOCOOL_OS=linux ;;
        Darwin)        SOCOOL_OS=darwin ;;
        CYGWIN*|MINGW*|MSYS*) SOCOOL_OS=windows ;;
        *)             SOCOOL_OS=unknown ;;
    esac

    case "$uname_m" in
        x86_64|amd64)  SOCOOL_ARCH=x86_64 ;;
        aarch64|arm64) SOCOOL_ARCH=aarch64 ;;
        *)             SOCOOL_ARCH=unknown ;;
    esac

    export SOCOOL_OS SOCOOL_ARCH
    log_debug "host: os=$SOCOOL_OS arch=$SOCOOL_ARCH (uname -s=$uname_s, uname -m=$uname_m)"
}

# ────────────────────────────────────────────────────────────────────────
# Environment
# ────────────────────────────────────────────────────────────────────────

# load_env — source .env from repo root if it exists. Silently ignored if
# missing. .env is gitignored and is the sanctioned place for user-local
# SOCOOL_* overrides.
load_env() {
    local env_file="$socool_repo_root/.env"
    if [[ -f "$env_file" ]]; then
        log_debug "sourcing $env_file"
        # shellcheck disable=SC1090 # path is validated above
        set -a
        source "$env_file"
        set +a
    fi
}

# ensure_secret_umask — restrict file creation to 0600 for this shell.
ensure_secret_umask() {
    umask 077
}

# require_tty_or_env <env_name> — if stdin is not a tty AND the given env
# var is unset, exit 64 with a message pointing to the env var. Used by
# every prompt to enforce CI-friendliness.
require_tty_or_env() {
    local env_name="$1"
    if [[ ! -t 0 ]] && [[ -z "${!env_name:-}" ]]; then
        die 64 "non-interactive run: set $env_name to skip this prompt (see .env.example)"
    fi
}

# ────────────────────────────────────────────────────────────────────────
# Prompts — the pause-for-activation pattern
# ────────────────────────────────────────────────────────────────────────

# prompt_action <title> <what> <where> <paste> <env_name>
# Prints the framed action block. Does NOT prompt — callers chain with
# prompt_with_default or prompt_yes_no. Separated so tests can assert the
# banner text without running the prompt.
prompt_action() {
    local title="$1" what="$2" where="$3" paste="$4" env_name="$5"
    banner "Action required: $title"
    printf 'What:  %s\n' "$what"  >&2
    printf 'Where: %s\n' "$where" >&2
    printf 'Paste: %s\n' "$paste" >&2
    printf 'Env:   %s\n' "$env_name" >&2
}

# prompt_with_default <label> <question> <default> <env_name>
# Returns the chosen value on stdout. Env var wins; then tty prompt; then
# default.
prompt_with_default() {
    local label="$1" question="$2" default="$3" env_name="$4"
    local env_val="${!env_name:-}"

    if [[ -n "$env_val" ]]; then
        log_debug "$label <- $env_name=$env_val"
        printf '%s' "$env_val"
        return 0
    fi

    require_tty_or_env "$env_name"

    local answer=""
    printf '%s [%s]: ' "$question" "$default" >&2
    IFS= read -r answer
    if [[ -z "$answer" ]]; then
        answer="$default"
    fi
    printf '%s' "$answer"
}

# prompt_yes_no <label> <question> <default:y|n> <env_name>
# Writes 'y' or 'n' to stdout.
prompt_yes_no() {
    local label="$1" question="$2" default="$3" env_name="$4"
    local env_val="${!env_name:-}"

    case "$default" in y|n) ;; *) die 1 "prompt_yes_no default must be y or n, got '$default'" ;; esac

    if [[ -n "$env_val" ]]; then
        case "$env_val" in
            1|true|yes|y|Y) printf 'y' ;;
            0|false|no|n|N) printf 'n' ;;
            *) die 2 "invalid $env_name='$env_val' — expected 0/1/yes/no" ;;
        esac
        return 0
    fi

    require_tty_or_env "$env_name"

    local hint="[y/N]"
    [[ "$default" == "y" ]] && hint="[Y/n]"

    local answer=""
    printf '%s %s: ' "$question" "$hint" >&2
    IFS= read -r answer
    if [[ -z "$answer" ]]; then
        answer="$default"
    fi
    case "$answer" in
        y|Y|yes|YES) printf 'y' ;;
        n|N|no|NO)   printf 'n' ;;
        *)           printf '%s' "$default" ;;
    esac
}

# ────────────────────────────────────────────────────────────────────────
# Config loading — config/lab.yml is the single source of truth.
# ────────────────────────────────────────────────────────────────────────

# lab_config_get <python-path>
# Example: lab_config_get 'network.lan.cidr'
# Implemented via python3 + PyYAML. Requires ensure_python to have run.
lab_config_get() {
    local path="$1"
    local config_file="$socool_repo_root/config/lab.yml"
    if [[ ! -f "$config_file" ]]; then
        die 1 "config not found: $config_file"
    fi
    if ! command -v python3 >/dev/null 2>&1; then
        die 21 "python3 required for config parsing — install it or run scripts/preflight/run-all.sh first"
    fi

    python3 - "$config_file" "$path" <<'PY'
import sys, yaml
cfg_path, key_path = sys.argv[1], sys.argv[2]
with open(cfg_path, 'r') as f:
    data = yaml.safe_load(f)
cur = data
for part in key_path.split('.'):
    if isinstance(cur, list):
        try:
            cur = cur[int(part)]
        except (ValueError, IndexError):
            print(f"lab_config_get: key '{key_path}' not found at '{part}'", file=sys.stderr)
            sys.exit(1)
    elif isinstance(cur, dict) and part in cur:
        cur = cur[part]
    else:
        print(f"lab_config_get: key '{key_path}' not found at '{part}'", file=sys.stderr)
        sys.exit(1)
if isinstance(cur, (dict, list)):
    print(yaml.safe_dump(cur, default_flow_style=False).rstrip())
else:
    print(cur)
PY
}

# lab_vm_hostnames — print VM hostnames in boot_order (one per line).
lab_vm_hostnames() {
    local config_file="$socool_repo_root/config/lab.yml"
    python3 - "$config_file" <<'PY'
import sys, yaml
with open(sys.argv[1], 'r') as f:
    data = yaml.safe_load(f)
vms = sorted(data.get('vms', []), key=lambda v: v.get('boot_order', 0))
for vm in vms:
    print(vm['hostname'])
PY
}

# validate_hostname_token <value> — reject path-traversal / injection
# characters in a value destined for a filesystem path. Used for every
# hostname and role name read from config/lab.yml.
validate_hostname_token() {
    local v="$1"
    if [[ ! "$v" =~ ^[a-z][a-z0-9-]{0,30}$ ]]; then
        die 1 "invalid hostname token: '$v' (must match ^[a-z][a-z0-9-]{0,30}\$)"
    fi
}
