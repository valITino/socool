#!/usr/bin/env bash
# uninstall.sh — SOCool uninstall entry point for Linux / macOS hosts.
# Tears down what setup.sh installed: VMs, boxes, caches, plugins, and
# (opt-in) host packages.
#
# Parity counterpart: uninstall.ps1. Every flag, prompt, env var, and
# exit code here MUST have an equivalent there; a drift is a bug.
#
# Usage: see --help.

set -euo pipefail
IFS=$'\n\t'

# Bash 4+ gate (same justification as setup.sh).
if (( BASH_VERSINFO[0] < 4 )); then
    printf 'uninstall.sh requires bash >= 4.0; detected %s at %s\n' \
        "${BASH_VERSION:-unknown}" "$BASH" >&2
    printf '\n' >&2
    printf 'On macOS, /bin/bash is pinned at 3.2 for licensing reasons.\n' >&2
    printf 'Install a modern bash via Homebrew and re-run under it:\n' >&2
    printf '\n' >&2
    printf '  brew install bash\n' >&2
    printf '  /opt/homebrew/bin/bash ./uninstall.sh    # Apple Silicon\n' >&2
    printf '  /usr/local/bin/bash  ./uninstall.sh      # Intel\n' >&2
    exit 17
fi

socool_version="0.1.0-dev"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=scripts/lib/common.sh
source "$script_dir/scripts/lib/common.sh"
# detect_package_manager / _run_sudo live in deps.sh and are reused by
# the host-package phase.
# shellcheck source=scripts/lib/deps.sh
source "$script_dir/scripts/lib/deps.sh"
# shellcheck source=scripts/uninstall/run-all.sh
source "$script_dir/scripts/uninstall/run-all.sh"

# ────────────────────────────────────────────────────────────────────────
# CLI parsing
# ────────────────────────────────────────────────────────────────────────

usage() {
    cat <<EOF
uninstall.sh — SOCool $socool_version

Usage: ./uninstall.sh [flags]

Removes the SOCool lab from this host. By default this:
  - destroys lab VMs (vagrant destroy -f)
  - removes the local socool-* Vagrant boxes
  - uninstalls the vagrant-libvirt plugin (if present)
  - clears caches and rotated-credential artifacts under the repo

By default this does NOT:
  - delete .env (pass --env)
  - uninstall host packages like packer, vagrant, virtualbox (pass --packages)
  - delete the repo itself (instructions printed at the end)

Flags:
  -h, --help                 Show this help and exit.
      --version              Show version and exit.
  -y, --yes                  Non-interactive mode. Skips every confirmation.
                             Required for CI. (SOCOOL_YES=1)
      --dry-run              Print what would happen, but make no changes.
                             (SOCOOL_UNINSTALL_DRY_RUN=1)
      --keep-vms             Skip the vagrant destroy phase.
                             (SOCOOL_UNINSTALL_VMS=0)
      --keep-boxes           Skip the vagrant box remove phase.
                             (SOCOOL_UNINSTALL_BOXES=0)
      --keep-plugins         Skip the vagrant plugin uninstall phase.
                             (SOCOOL_UNINSTALL_VAGRANT_PLUGINS=0)
      --keep-cache           Skip the cache and artifacts phase.
                             (SOCOOL_UNINSTALL_CACHES=0)
      --env                  Also remove .env (with extra confirmation).
                             (SOCOOL_UNINSTALL_ENV=1)
      --packages             Also uninstall host packages (packer, vagrant,
                             hypervisor). Will break other projects that
                             rely on these tools — use carefully.
                             (SOCOOL_UNINSTALL_PACKAGES=1)
      --all                  Remove everything: VMs + boxes + plugins +
                             cache + .env + host packages. Equivalent to
                             --env --packages with all keep-* flags off.
      --hypervisor <v>       virtualbox | libvirt. Tells the package phase
                             which hypervisor stack to remove. If unset
                             when --packages is on, both are attempted.
                             (SOCOOL_HYPERVISOR)
      --log-level <l>        debug | info | warn | error. (SOCOOL_LOG_LEVEL)

Environment variables are read from .env if present; flags override them.

Exit codes: 0 success; 80–86 documented in scripts/uninstall/run-all.sh.
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)             usage; exit 0 ;;
            --version)             printf 'SOCool %s (uninstall)\n' "$socool_version"; exit 0 ;;
            -y|--yes)              export SOCOOL_YES=1; shift ;;
            --dry-run)             export SOCOOL_UNINSTALL_DRY_RUN=1; shift ;;
            --keep-vms)            export SOCOOL_UNINSTALL_VMS=0; shift ;;
            --keep-boxes)          export SOCOOL_UNINSTALL_BOXES=0; shift ;;
            --keep-plugins)        export SOCOOL_UNINSTALL_VAGRANT_PLUGINS=0; shift ;;
            --keep-cache)          export SOCOOL_UNINSTALL_CACHES=0; shift ;;
            --env)                 export SOCOOL_UNINSTALL_ENV=1; shift ;;
            --packages)            export SOCOOL_UNINSTALL_PACKAGES=1; shift ;;
            --all)
                export SOCOOL_UNINSTALL_VMS=1
                export SOCOOL_UNINSTALL_BOXES=1
                export SOCOOL_UNINSTALL_VAGRANT_PLUGINS=1
                export SOCOOL_UNINSTALL_CACHES=1
                export SOCOOL_UNINSTALL_ENV=1
                export SOCOOL_UNINSTALL_PACKAGES=1
                shift ;;
            --hypervisor)          [[ $# -ge 2 ]] || die 2 "--hypervisor requires a value"
                                   export SOCOOL_HYPERVISOR="$2"; shift 2 ;;
            --log-level)           [[ $# -ge 2 ]] || die 2 "--log-level requires a value"
                                   export SOCOOL_LOG_LEVEL="$2"; shift 2 ;;
            --)                    shift; break ;;
            -*)                    die 2 "unknown flag: $1 (see --help)" ;;
            *)                     die 2 "unexpected positional argument: $1 (see --help)" ;;
        esac
    done
}

main() {
    parse_args "$@"
    load_env

    banner "SOCool $socool_version (uninstall)"
    detect_host

    run_uninstall
}

main "$@"
