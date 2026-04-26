#!/usr/bin/env bash
# scripts/uninstall/run-all.sh — undo what setup.sh did, in dependency order.
#
# Parity counterpart: scripts/uninstall/run-all.ps1. Every flag, prompt,
# env var, and exit code here MUST have an equivalent there.
#
# Phases (each is opt-in/opt-out via flags; see uninstall.sh --help):
#   1. vagrant destroy -f             (stops & removes the lab VMs)
#   2. vagrant box remove socool-*    (purges the local box store)
#   3. vagrant plugin uninstall       (libvirt only, plus other socool plugins)
#   4. cache + artifact cleanup       (.socool-cache, packer_cache, packer/*/artifacts)
#   5. .env removal                   (sensitive — extra confirmation)
#   6. host package uninstall         (packer/vagrant/hypervisor — OPT-IN only)
#   7. repo deletion hint             (we never delete the repo we run from)
#
# Exit codes:
#   0     success (nothing to do or all phases passed)
#   80    vagrant destroy failed
#   81    vagrant box remove failed
#   82    vagrant plugin uninstall failed
#   83    cache/artifact cleanup failed
#   84    user aborted at confirmation
#   85    package uninstall failed
#   86    .env removal blocked / failed

set -euo pipefail
IFS=$'\n\t'

if [[ "${_SOCOOL_UNINSTALL_LOADED:-}" == "1" ]]; then
    return 0
fi
_SOCOOL_UNINSTALL_LOADED=1

# ────────────────────────────────────────────────────────────────────────
# Helpers
# ────────────────────────────────────────────────────────────────────────

# _dry_run — returns 0 if SOCOOL_UNINSTALL_DRY_RUN=1.
_dry_run() {
    [[ "${SOCOOL_UNINSTALL_DRY_RUN:-0}" == "1" ]]
}

# _show_or_run <description> <cmd...> — prints the command, then either runs
# it or skips when dry-run is on. Returns the command's exit code (or 0 in
# dry-run).
_show_or_run() {
    local desc="$1"; shift
    if _dry_run; then
        log_info "[dry-run] $desc"
        log_info "[dry-run]   \$ $*"
        return 0
    fi
    log_info "$desc"
    "$@"
}

# _safe_rm_rf <path-under-repo-root> — refuses to act on empty paths or
# paths outside the repo root. Idempotent (no error if path is missing).
_safe_rm_rf() {
    local target="${1:?_safe_rm_rf requires a path}"
    [[ -n "$target" ]] || die 1 "_safe_rm_rf: empty path (refusing)"
    # Resolve to an absolute path. If the path doesn't exist, that's fine —
    # uninstall is idempotent, no-op.
    if [[ ! -e "$target" && ! -L "$target" ]]; then
        log_debug "rm: skip (absent): $target"
        return 0
    fi
    local abs
    abs="$(cd -- "$(dirname -- "$target")" 2>/dev/null && pwd)/$(basename -- "$target")" || die 1 "_safe_rm_rf: cannot resolve $target"
    case "$abs" in
        /|""|/home|/home/*/..*|/Users|/Users/*/..*) die 1 "_safe_rm_rf: refusing to delete '$abs'" ;;
    esac
    # Confine to repo root: require the path is inside socool_repo_root.
    case "$abs" in
        "$socool_repo_root"/*) ;;
        *) die 1 "_safe_rm_rf: '$abs' is outside repo root '$socool_repo_root' (refusing)" ;;
    esac
    if _dry_run; then
        log_info "[dry-run] rm -rf -- $abs"
        return 0
    fi
    log_info "rm -rf -- $abs"
    rm -rf -- "$abs"
}

# ────────────────────────────────────────────────────────────────────────
# Phase 1: vagrant destroy
# ────────────────────────────────────────────────────────────────────────

uninstall_vms() {
    [[ "${SOCOOL_UNINSTALL_VMS:-1}" == "1" ]] || { log_info "skip: vagrant destroy (SOCOOL_UNINSTALL_VMS=0)"; return 0; }

    local vagrantfile="$socool_repo_root/vagrant/Vagrantfile"
    if [[ ! -f "$vagrantfile" ]]; then
        log_info "skip: no Vagrantfile at $vagrantfile"
        return 0
    fi
    if ! command -v vagrant >/dev/null 2>&1; then
        log_warn "vagrant not on PATH — assuming no VMs are registered. Re-run with --packages skipped if you want to keep host tools."
        return 0
    fi

    banner "Uninstall: vagrant destroy"
    local rc=0
    (
        cd -- "$socool_repo_root/vagrant"
        if _dry_run; then
            log_info "[dry-run] cd vagrant && vagrant destroy -f"
        else
            # `|| true` guarded by rc capture below: an empty environment
            # (no VMs ever brought up) returns nonzero on some Vagrant
            # versions; that's not a failure for us.
            vagrant destroy -f || rc=$?
        fi
    ) || rc=$?

    # Vagrant exits 1 when no machines exist in the env — treat that
    # benign case as success.
    if (( rc != 0 )); then
        if [[ ! -d "$socool_repo_root/vagrant/.vagrant/machines" ]]; then
            log_info "no Vagrant machines registered (vagrant exited $rc); continuing"
            rc=0
        else
            die 80 "vagrant destroy failed (exit $rc); resolve manually with 'cd vagrant && vagrant status' before re-running"
        fi
    fi

    # Remove the per-environment .vagrant/ directory so a future setup.sh
    # starts cleanly.
    if [[ -d "$socool_repo_root/vagrant/.vagrant" ]]; then
        _safe_rm_rf "$socool_repo_root/vagrant/.vagrant"
    fi
}

# ────────────────────────────────────────────────────────────────────────
# Phase 2: vagrant box remove socool-*
# ────────────────────────────────────────────────────────────────────────

uninstall_boxes() {
    [[ "${SOCOOL_UNINSTALL_BOXES:-1}" == "1" ]] || { log_info "skip: vagrant box remove (SOCOOL_UNINSTALL_BOXES=0)"; return 0; }
    if ! command -v vagrant >/dev/null 2>&1; then
        log_debug "vagrant not on PATH; nothing to remove from box store"
        return 0
    fi

    banner "Uninstall: vagrant box remove"

    # `vagrant box list` output format: "<name> (<provider>, <version>)".
    # We filter to lines starting with 'socool-'.
    local list rc=0
    list="$(vagrant box list 2>/dev/null || true)"
    if [[ -z "$list" ]]; then
        log_info "vagrant box store is empty"
        return 0
    fi

    local removed=0
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        # Format: name (provider, version)
        local name
        name="${line%% *}"
        case "$name" in
            socool-*) ;;
            *) continue ;;
        esac
        if _dry_run; then
            log_info "[dry-run] vagrant box remove --force --all -- $name"
            removed=$((removed+1))
            continue
        fi
        log_info "vagrant box remove --force --all -- $name"
        if ! vagrant box remove --force --all -- "$name"; then
            die 81 "vagrant box remove failed for '$name'"
        fi
        removed=$((removed+1))
    done <<< "$list"

    if (( removed == 0 )); then
        log_info "no socool-* boxes registered"
    else
        log_info "removed $removed socool-* box(es) from the local store"
    fi
}

# ────────────────────────────────────────────────────────────────────────
# Phase 3: vagrant plugin uninstall (libvirt path)
# ────────────────────────────────────────────────────────────────────────

uninstall_vagrant_plugins() {
    [[ "${SOCOOL_UNINSTALL_VAGRANT_PLUGINS:-1}" == "1" ]] || { log_info "skip: vagrant plugin uninstall (SOCOOL_UNINSTALL_VAGRANT_PLUGINS=0)"; return 0; }
    if ! command -v vagrant >/dev/null 2>&1; then
        return 0
    fi

    banner "Uninstall: vagrant plugins"

    local plugins
    plugins="$(vagrant plugin list 2>/dev/null || true)"
    if ! grep -q '^vagrant-libvirt\b' <<< "$plugins"; then
        log_info "vagrant-libvirt plugin not installed; nothing to do"
        return 0
    fi

    if _dry_run; then
        log_info "[dry-run] vagrant plugin uninstall vagrant-libvirt"
        return 0
    fi

    log_info "vagrant plugin uninstall vagrant-libvirt"
    if ! vagrant plugin uninstall vagrant-libvirt; then
        die 82 "vagrant plugin uninstall failed for vagrant-libvirt"
    fi
}

# ────────────────────────────────────────────────────────────────────────
# Phase 4: cache + artifact cleanup
# ────────────────────────────────────────────────────────────────────────

uninstall_caches() {
    [[ "${SOCOOL_UNINSTALL_CACHES:-1}" == "1" ]] || { log_info "skip: cache/artifact cleanup (SOCOOL_UNINSTALL_CACHES=0)"; return 0; }

    banner "Uninstall: caches and artifacts"

    # 1. .socool-cache/ (downloaded ISOs and built .box files).
    local cache_dir="${SOCOOL_BOX_OUTPUT_DIR:-}"
    [[ -n "$cache_dir" ]] || cache_dir="$socool_repo_root/.socool-cache"
    # If the user pointed SOCOOL_BOX_OUTPUT_DIR outside the repo, only
    # remove the default in-repo .socool-cache; leave external dirs alone
    # and warn so they can clean up manually.
    case "$cache_dir" in
        "$socool_repo_root"/*) _safe_rm_rf "$cache_dir" ;;
        *)
            log_warn "SOCOOL_BOX_OUTPUT_DIR='$cache_dir' is outside the repo; skipping (remove manually if desired)"
            ;;
    esac
    if [[ -d "$socool_repo_root/.socool-cache" ]]; then
        _safe_rm_rf "$socool_repo_root/.socool-cache"
    fi

    # 2. packer/*/artifacts/ — rotated-credential manifests, gitignored.
    #    These contain sensitive material (rotated default creds), so the
    #    log line is intentionally generic.
    local pkr_dir
    while IFS= read -r pkr_dir; do
        [[ -z "$pkr_dir" ]] && continue
        if [[ -d "$pkr_dir" ]]; then
            log_info "removing packer artifacts (contains rotated credentials)"
            _safe_rm_rf "$pkr_dir"
        fi
    done < <(find "$socool_repo_root/packer" -maxdepth 2 -type d -name 'artifacts' 2>/dev/null || true)

    # 3. packer_cache/ anywhere in the repo (Packer drops these next to
    #    each template).
    while IFS= read -r pkr_dir; do
        [[ -z "$pkr_dir" ]] && continue
        if [[ -d "$pkr_dir" ]]; then
            _safe_rm_rf "$pkr_dir"
        fi
    done < <(find "$socool_repo_root" -type d -name 'packer_cache' 2>/dev/null || true)

    # 4. Stray *.box files in the repo (Packer's vagrant post-processor
    #    sometimes drops next to the template too).
    while IFS= read -r boxfile; do
        [[ -z "$boxfile" ]] && continue
        _safe_rm_rf "$boxfile"
    done < <(find "$socool_repo_root" -maxdepth 4 -type f -name '*.box' 2>/dev/null || true)

    log_info "cache + artifact cleanup done"
}

# ────────────────────────────────────────────────────────────────────────
# Phase 5: .env removal
# ────────────────────────────────────────────────────────────────────────

uninstall_env_file() {
    [[ "${SOCOOL_UNINSTALL_ENV:-0}" == "1" ]] || { log_info "skip: .env removal (default; pass --env or SOCOOL_UNINSTALL_ENV=1 to remove)"; return 0; }

    local env_file="$socool_repo_root/.env"
    if [[ ! -f "$env_file" ]]; then
        log_info "no .env to remove"
        return 0
    fi

    banner "Uninstall: .env"
    log_warn ".env may contain license keys, activation codes, or paths to sensitive ISOs."
    log_warn "It is gitignored, so this only affects your local copy. There is no backup."

    local answer
    answer="$(prompt_yes_no env-remove "Delete $env_file?" "n" "SOCOOL_YES")"
    if [[ "$answer" != "y" ]]; then
        log_info "leaving .env in place"
        return 0
    fi

    if _dry_run; then
        log_info "[dry-run] rm -f -- $env_file"
        return 0
    fi
    rm -f -- "$env_file" || die 86 "failed to remove $env_file"
    log_info "removed $env_file"
}

# ────────────────────────────────────────────────────────────────────────
# Phase 6: host package uninstall (opt-in)
# ────────────────────────────────────────────────────────────────────────

# We deliberately leave host packages alone by default. Many users install
# Packer / Vagrant / VirtualBox for projects beyond SOCool, and silently
# uninstalling them is the same class of mistake as auto-disabling Hyper-V
# (see CLAUDE.md, ADR-0002). The user must pass --packages to opt in.

_uninstall_pkg_apt() {
    _run_sudo env DEBIAN_FRONTEND=noninteractive apt-get remove -y "$@" || return $?
    _run_sudo env DEBIAN_FRONTEND=noninteractive apt-get autoremove -y || true
}
_uninstall_pkg_dnf()    { _run_sudo dnf remove -y "$@" || return $?; }
_uninstall_pkg_pacman() { _run_sudo pacman -Rns --noconfirm "$@" || return $?; }
_uninstall_pkg_brew()        { brew uninstall "$@" || return $?; }
_uninstall_pkg_brew_cask()   { brew uninstall --cask "$@" || return $?; }

uninstall_host_packages() {
    [[ "${SOCOOL_UNINSTALL_PACKAGES:-0}" == "1" ]] || { log_info "skip: host package uninstall (default; pass --packages or SOCOOL_UNINSTALL_PACKAGES=1 to opt in)"; return 0; }

    banner "Uninstall: host packages"
    log_warn "About to remove packer, vagrant, and the hypervisor package(s) you used."
    log_warn "Other projects on this host that rely on these tools will break."
    local answer
    answer="$(prompt_yes_no pkg-confirm "Continue removing host packages?" "n" "SOCOOL_YES")"
    [[ "$answer" == "y" ]] || die 84 "aborted by user at host-package confirmation"

    # Rely on detect_package_manager from deps.sh (already sourced).
    local pm
    pm="$(detect_package_manager)"

    # Map hypervisor to the package list we installed in deps.sh.
    local hv="${SOCOOL_HYPERVISOR:-}"
    if [[ -z "$hv" ]]; then
        # If the user didn't tell us, scrub both possible toolchains.
        log_warn "SOCOOL_HYPERVISOR not set; will attempt to remove every hypervisor stack we know about"
        hv="all"
    fi

    # Pretty-print a package list for dry-run with space separators,
    # since IFS is intentionally $'\n\t' for the rest of the script.
    _join_space() { local IFS=' '; printf '%s' "$*"; }

    local rc=0
    case "$pm" in
        apt)
            local pkgs=(packer vagrant)
            case "$hv" in
                virtualbox)  pkgs+=(virtualbox virtualbox-7.0 virtualbox-7.1 virtualbox-7.2) ;;
                libvirt|all) pkgs+=(qemu-kvm libvirt-daemon-system libvirt-clients virtinst libvirt-dev ruby-dev) ;;
            esac
            [[ "$hv" == "all" ]] && pkgs+=(virtualbox virtualbox-7.0 virtualbox-7.1 virtualbox-7.2)
            if _dry_run; then
                log_info "[dry-run] apt-get remove -y $(_join_space "${pkgs[@]}")"
            else
                # Some packages may not be installed; apt-get handles "not
                # found" with a warning and a non-zero rc. Run per-package
                # so one missing entry doesn't block the rest.
                local p
                for p in "${pkgs[@]}"; do
                    if dpkg -s "$p" >/dev/null 2>&1; then
                        _uninstall_pkg_apt "$p" || rc=$?
                    fi
                done
            fi
            ;;
        dnf)
            local pkgs=(packer vagrant)
            case "$hv" in
                virtualbox)  pkgs+=(VirtualBox VirtualBox-7.0 VirtualBox-7.1 VirtualBox-7.2) ;;
                libvirt|all) pkgs+=(qemu-kvm libvirt libvirt-devel virt-install) ;;
            esac
            [[ "$hv" == "all" ]] && pkgs+=(VirtualBox VirtualBox-7.0 VirtualBox-7.1 VirtualBox-7.2)
            if _dry_run; then
                log_info "[dry-run] dnf remove -y $(_join_space "${pkgs[@]}")"
            else
                local p
                for p in "${pkgs[@]}"; do
                    if rpm -q "$p" >/dev/null 2>&1; then
                        _uninstall_pkg_dnf "$p" || rc=$?
                    fi
                done
            fi
            ;;
        pacman)
            local pkgs=(packer vagrant)
            case "$hv" in
                virtualbox)  pkgs+=(virtualbox) ;;
                libvirt|all) pkgs+=(qemu-full libvirt virt-install) ;;
            esac
            [[ "$hv" == "all" ]] && pkgs+=(virtualbox)
            if _dry_run; then
                log_info "[dry-run] pacman -Rns --noconfirm $(_join_space "${pkgs[@]}")"
            else
                local p
                for p in "${pkgs[@]}"; do
                    if pacman -Qi "$p" >/dev/null 2>&1; then
                        _uninstall_pkg_pacman "$p" || rc=$?
                    fi
                done
            fi
            ;;
        brew)
            local formulae=(hashicorp/tap/packer hashicorp/tap/hashicorp-vagrant)
            local casks=()
            case "$hv" in
                virtualbox)  casks+=(virtualbox) ;;
                libvirt|all) formulae+=(qemu) ;;
            esac
            [[ "$hv" == "all" ]] && casks+=(virtualbox)
            if _dry_run; then
                log_info "[dry-run] brew uninstall $(_join_space "${formulae[@]}")"
                (( ${#casks[@]} > 0 )) && log_info "[dry-run] brew uninstall --cask $(_join_space "${casks[@]}")"
            else
                local f
                for f in "${formulae[@]}"; do
                    brew list --formula "$f" >/dev/null 2>&1 && _uninstall_pkg_brew "$f" || true
                done
                local c
                for c in "${casks[@]}"; do
                    brew list --cask "$c" >/dev/null 2>&1 && _uninstall_pkg_brew_cask "$c" || true
                done
            fi
            ;;
        *)
            die 85 "uninstall_host_packages: unsupported package manager '$pm'"
            ;;
    esac

    if (( rc != 0 )); then
        die 85 "host package uninstall reported errors (last rc=$rc); inspect output above"
    fi
    log_info "host packages removed"
}

# ────────────────────────────────────────────────────────────────────────
# Phase 7: repo deletion hint
# ────────────────────────────────────────────────────────────────────────

print_repo_deletion_hint() {
    banner "Final step: remove the repo directory"
    printf 'SOCool will not delete the directory it is running from.\n' >&2
    printf 'When you are ready, run:\n\n' >&2
    printf '  cd ..\n' >&2
    printf '  rm -rf -- %q\n\n' "$socool_repo_root" >&2
    printf 'VirtualBox host-only adapters created during the lab life are not\n' >&2
    printf 'removed automatically (Vagrant leaves them in place by design).\n' >&2
    printf 'Inspect with `VBoxManage list hostonlyifs` and remove any unused\n' >&2
    printf 'ones with `VBoxManage hostonlyif remove <name>` if you wish.\n' >&2
}

# ────────────────────────────────────────────────────────────────────────
# Top-level orchestrator
# ────────────────────────────────────────────────────────────────────────

run_uninstall() {
    banner "SOCool uninstall"
    if _dry_run; then
        log_warn "DRY RUN — no changes will be made"
    fi

    # Top-level confirmation. SOCOOL_YES skips it; otherwise we always
    # prompt because uninstall is destructive.
    if [[ "${SOCOOL_YES:-0}" != "1" ]] && ! _dry_run; then
        log_warn "This will destroy the SOCool lab VMs, remove built boxes, and clear local caches."
        log_warn "Repo files tracked by git are NOT modified. The .env file is left in place"
        log_warn "unless you pass --env."
        local answer
        answer="$(prompt_yes_no uninstall-confirm "Proceed with uninstall?" "n" "SOCOOL_YES")"
        [[ "$answer" == "y" ]] || die 84 "aborted by user at top-level confirmation"
    fi

    uninstall_vms
    uninstall_boxes
    uninstall_vagrant_plugins
    uninstall_caches
    uninstall_env_file
    uninstall_host_packages
    print_repo_deletion_hint

    banner "SOCool uninstall complete"
}

# When sourced, the caller invokes run_uninstall(). When run directly,
# wire up the same env that uninstall.sh would so a maintainer can test
# in isolation.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    # shellcheck source=scripts/lib/common.sh
    source "$SCRIPT_DIR/../lib/common.sh"
    # shellcheck source=scripts/lib/deps.sh
    source "$SCRIPT_DIR/../lib/deps.sh"
    detect_host
    load_env
    run_uninstall
fi
