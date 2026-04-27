#!/usr/bin/env bash
# setup.sh — SOCool entry point for Linux / macOS hosts.
# Runs preflight, installs deps, resolves hypervisor, drives provisioning.
#
# Parity counterpart: setup.ps1. Every flag, prompt, env var, and exit
# code here MUST have an equivalent there; a drift is a bug.
#
# Usage: see --help.

set -euo pipefail
IFS=$'\n\t'

# ────────────────────────────────────────────────────────────────────────
# Bash 4+ gate. This block runs BEFORE sourcing any lib so it works on
# macOS hosts where /bin/bash is still 3.2 (GPLv2 constraint). If the
# user runs via a modern bash (Homebrew's /opt/homebrew/bin/bash or
# /usr/local/bin/bash) the check passes silently.
# ────────────────────────────────────────────────────────────────────────
if (( BASH_VERSINFO[0] < 4 )); then
    printf 'setup.sh requires bash >= 4.0; detected %s at %s\n' \
        "${BASH_VERSION:-unknown}" "$BASH" >&2
    printf '\n' >&2
    printf 'On macOS, /bin/bash is pinned at 3.2 for licensing reasons.\n' >&2
    printf 'Install a modern bash via Homebrew and re-run under it:\n' >&2
    printf '\n' >&2
    printf '  brew install bash\n' >&2
    printf '  /opt/homebrew/bin/bash ./setup.sh     # Apple Silicon\n' >&2
    printf '  /usr/local/bin/bash  ./setup.sh       # Intel\n' >&2
    exit 17
fi

# Internal bash locals — intentionally NOT in the user-facing SOCOOL_*
# namespace (parity test enforces this).
socool_version="0.1.0-dev"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=scripts/lib/common.sh
source "$script_dir/scripts/lib/common.sh"
# shellcheck source=scripts/lib/hypervisor.sh
source "$script_dir/scripts/lib/hypervisor.sh"
# shellcheck source=scripts/lib/deps.sh
source "$script_dir/scripts/lib/deps.sh"
# shellcheck source=scripts/provision/run-pipeline.sh
source "$script_dir/scripts/provision/run-pipeline.sh"

# ────────────────────────────────────────────────────────────────────────
# CLI parsing — every flag also has a SOCOOL_* env-var equivalent.
# ────────────────────────────────────────────────────────────────────────

usage() {
    cat <<EOF
setup.sh — SOCool $socool_version

Usage: ./setup.sh [flags]

Flags:
  -h, --help                 Show this help and exit.
      --version              Show version and exit.
  -y, --yes                  Non-interactive mode (SOCOOL_YES=1). Fails
                             fast if any required env var is unset.
      --hypervisor <v>       virtualbox | libvirt. (SOCOOL_HYPERVISOR)
      --scanner <v>          nessus | openvas | none. (SOCOOL_SCANNER)
      --windows-source <v>   eval | iso. (SOCOOL_WINDOWS_SOURCE)
      --windows-iso <path>   Absolute path to a Windows ISO, required
                             when --windows-source=iso. (SOCOOL_WINDOWS_ISO_PATH)
      --allow-bridged        Permit bridged networking. Off by default;
                             the lab is host-only/internal to preserve
                             isolation. (SOCOOL_ALLOW_BRIDGED=1)
      --log-level <l>        debug | info | warn | error. (SOCOOL_LOG_LEVEL)

Environment variables are read from .env in the repo root if it exists;
command-line flags override env vars.

Exit codes: see scripts/preflight/README.md and docs/troubleshooting.md.
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)          usage; exit 0 ;;
            --version)          printf 'SOCool %s\n' "$socool_version"; exit 0 ;;
            -y|--yes)           export SOCOOL_YES=1; shift ;;
            --hypervisor)       [[ $# -ge 2 ]] || die 2 "--hypervisor requires a value"
                                export SOCOOL_HYPERVISOR="$2"; shift 2 ;;
            --scanner)          [[ $# -ge 2 ]] || die 2 "--scanner requires a value"
                                export SOCOOL_SCANNER="$2"; shift 2 ;;
            --windows-source)   [[ $# -ge 2 ]] || die 2 "--windows-source requires a value"
                                export SOCOOL_WINDOWS_SOURCE="$2"; shift 2 ;;
            --windows-iso)      [[ $# -ge 2 ]] || die 2 "--windows-iso requires a value"
                                export SOCOOL_WINDOWS_ISO_PATH="$2"; shift 2 ;;
            --allow-bridged)    export SOCOOL_ALLOW_BRIDGED=1; shift ;;
            --log-level)        [[ $# -ge 2 ]] || die 2 "--log-level requires a value"
                                export SOCOOL_LOG_LEVEL="$2"; shift 2 ;;
            --)                 shift; break ;;
            -*)                 die 2 "unknown flag: $1 (see --help)" ;;
            *)                  die 2 "unexpected positional argument: $1 (see --help)" ;;
        esac
    done
}

# ────────────────────────────────────────────────────────────────────────
# Prompt helpers specific to setup.sh — high-level user decisions.
# ────────────────────────────────────────────────────────────────────────

resolve_scanner_choice() {
    if [[ -n "${SOCOOL_SCANNER:-}" ]]; then
        case "$SOCOOL_SCANNER" in
            nessus|openvas|none) log_info "scanner: $SOCOOL_SCANNER (from env)"; return 0 ;;
            *) die 2 "invalid SOCOOL_SCANNER='$SOCOOL_SCANNER' (expected nessus, openvas, or none)" ;;
        esac
    fi
    prompt_action \
        "Pick a vulnerability scanner" \
        "SOCool can include one scanner VM: Nessus Essentials (Tenable, free with activation key) or OpenVAS/GVM (Greenbone, open source). Pick 'none' to skip." \
        "https://www.tenable.com/products/nessus/nessus-essentials  or  https://greenbone.github.io/docs/latest/" \
        "nessus, openvas, or none" \
        "SOCOOL_SCANNER"
    local chosen
    chosen="$(prompt_with_default scanner "Scanner" "openvas" "SOCOOL_SCANNER")"
    case "$chosen" in
        nessus|openvas|none) export SOCOOL_SCANNER="$chosen"; log_info "scanner: $chosen" ;;
        *) die 2 "invalid scanner choice: '$chosen'" ;;
    esac
}

resolve_windows_source() {
    if [[ -n "${SOCOOL_WINDOWS_SOURCE:-}" ]]; then
        case "$SOCOOL_WINDOWS_SOURCE" in
            eval) log_info "windows-source: eval (from env)"; return 0 ;;
            iso)
                if [[ -z "${SOCOOL_WINDOWS_ISO_PATH:-}" ]]; then
                    die 2 "SOCOOL_WINDOWS_SOURCE=iso requires SOCOOL_WINDOWS_ISO_PATH"
                fi
                [[ -f "$SOCOOL_WINDOWS_ISO_PATH" ]] || die 2 "SOCOOL_WINDOWS_ISO_PATH does not exist: $SOCOOL_WINDOWS_ISO_PATH"
                log_info "windows-source: iso ($SOCOOL_WINDOWS_ISO_PATH, from env)"; return 0 ;;
            msdev)
                die 2 "SOCOOL_WINDOWS_SOURCE=msdev is no longer supported: Microsoft's Windows dev VM page has been unavailable since October 2024. Use 'eval' (Evaluation Center ISO) or 'iso' (provide your own)." ;;
            *) die 2 "invalid SOCOOL_WINDOWS_SOURCE='$SOCOOL_WINDOWS_SOURCE' (expected eval or iso)" ;;
        esac
    fi
    prompt_action \
        "Windows victim VM source" \
        "SOCool can download the free Windows 11 Enterprise evaluation ISO (90-day, no product key required) and run an unattended install, or build from a Windows ISO you provide." \
        "https://www.microsoft.com/en-us/evalcenter/evaluate-windows-11-enterprise" \
        "eval (auto-download evaluation ISO) or iso (you provide a path)" \
        "SOCOOL_WINDOWS_SOURCE"
    local chosen
    chosen="$(prompt_with_default windows-source "Source" "eval" "SOCOOL_WINDOWS_SOURCE")"
    case "$chosen" in
        eval) export SOCOOL_WINDOWS_SOURCE=eval ;;
        iso)
            export SOCOOL_WINDOWS_SOURCE=iso
            prompt_action \
                "Windows ISO path" \
                "Absolute path to your Windows ISO (Microsoft Evaluation Center or your own licensed media)." \
                "https://www.microsoft.com/en-us/evalcenter/" \
                "absolute path to the .iso file" \
                "SOCOOL_WINDOWS_ISO_PATH"
            local iso_path
            iso_path="$(prompt_with_default windows-iso "ISO path" "" "SOCOOL_WINDOWS_ISO_PATH")"
            [[ -n "$iso_path" ]] || die 2 "ISO path is required when --windows-source=iso"
            [[ -f "$iso_path" ]] || die 2 "ISO not found at: $iso_path"
            export SOCOOL_WINDOWS_ISO_PATH="$iso_path"
            ;;
        *) die 2 "invalid windows-source choice: '$chosen'" ;;
    esac
    log_info "windows-source: $SOCOOL_WINDOWS_SOURCE"
}

warn_if_bridged() {
    [[ "${SOCOOL_ALLOW_BRIDGED:-0}" == "1" ]] || return 0
    banner "Bridged networking enabled"
    log_warn "SOCOOL_ALLOW_BRIDGED=1 — the lab will bridge to your real LAN."
    log_warn "This undermines the default isolation. Attacker VM traffic may reach real hosts on your network."
    local answer
    answer="$(prompt_yes_no bridged-confirm "Are you sure you want to bridge the lab to your LAN?" "n" "SOCOOL_YES")"
    [[ "$answer" == "y" ]] || die 2 "bridged networking not confirmed; re-run without --allow-bridged"
}

# ────────────────────────────────────────────────────────────────────────
# Final summary
# ────────────────────────────────────────────────────────────────────────

print_final_summary() {
    banner "SOCool setup complete"
    printf 'Lab components:\n' >&2
    local repo_root="$socool_repo_root"

    while IFS= read -r vm; do
        [[ -z "$vm" ]] && continue
        # Skip scanner VMs the user didn't pick.
        case "$vm" in
            nessus)  [[ "${SOCOOL_SCANNER:-}" != "nessus"  ]] && continue ;;
            openvas) [[ "${SOCOOL_SCANNER:-}" != "openvas" ]] && continue ;;
        esac

        local idx ip role
        idx="$(_lab_vm_index "$vm")"
        ip="$(lab_config_get "vms.$idx.ip" 2>/dev/null || printf '(multi-homed)')"
        role="$(lab_config_get "vms.$idx.role")"

        printf '  %-16s  role=%-9s  ip=%s\n' "$vm" "$role" "$ip" >&2

        local creds="$repo_root/packer/$vm/artifacts/credentials.json"
        if [[ -f "$creds" ]]; then
            # Restrict read perm while we inspect.
            ensure_secret_umask
            log_info "    credentials (rotated): $creds"
        else
            log_warn "    credentials manifest not found: $creds (Step 5 will populate this)"
        fi
    done < <(lab_vm_hostnames)

    printf '\nNext steps:\n' >&2
    printf '  - pfSense webConfigurator:  https://10.42.20.1/\n' >&2
    printf '  - Wazuh dashboard:          https://10.42.20.10/\n' >&2
    printf '  - TheHive web UI:           https://10.42.20.30/\n' >&2
    printf '  - Kali (SSH):               ssh vagrant@10.42.10.10\n' >&2
    printf '  - Windows victim (RDP):     10.42.10.20:3389\n' >&2
    printf '  - Destroy the lab:          (cd vagrant && vagrant destroy -f)\n' >&2
}

# ────────────────────────────────────────────────────────────────────────
# Main
# ────────────────────────────────────────────────────────────────────────

main() {
    parse_args "$@"
    load_env

    banner "SOCool $socool_version"
    detect_host

    # Step 2: preflight.
    bash -- "$script_dir/scripts/preflight/run-all.sh"

    # Step 4: hypervisor resolution. Done before deps so we know which
    # hypervisor to install.
    local hv
    hv="$(resolve_hypervisor)"
    export SOCOOL_HYPERVISOR="$hv"

    # Step 5: Windows source.
    resolve_windows_source

    # Step 6: scanner choice.
    resolve_scanner_choice

    # Step 3: install deps (AFTER hypervisor choice is known — deps must
    # target a specific hypervisor package).
    install_deps "$hv"

    # Safety check, not a numbered step: warn and re-confirm if the user
    # opted into bridged networking (which breaks default isolation).
    warn_if_bridged

    # Step 7: provisioning pipeline (templates/Vagrantfile from Steps 5/6
    # land later; missing artifacts are reported cleanly).
    run_pipeline "$hv" "${SOCOOL_SCANNER:-none}" "$SOCOOL_WINDOWS_SOURCE"

    # Step 8: final summary.
    print_final_summary
}

main "$@"
