#!/usr/bin/env bash
# scripts/lib/deps.sh — dependency detection & installation (bash).
#
# Public ABI:
#   detect_package_manager       -> echoes apt|dnf|pacman|brew, or exits 21
#   install_deps <hypervisor>    -> ensures git, python3, python3-yaml,
#                                   packer, vagrant, and the hypervisor
#                                   are present. Idempotent.
#
# Design notes:
# - We never auto-configure third-party repos (HashiCorp's apt/dnf repo,
#   Oracle's VirtualBox repo). Silently modifying sources.list is a
#   supply-chain surprise. If a required tool is missing and its
#   package manager can't install it without a third-party repo, we
#   print the exact remediation command and exit 21.
# - brew, winget, and choco are not in this file (brew is here for
#   macOS; winget/choco are pwsh-only).
# - sudo is requested once at the top (via sudo -v) the first time we
#   need it. If stdin is not a tty and SOCOOL_YES isn't 1, we exit 64.

set -euo pipefail

if [[ "${_SOCOOL_DEPS_LOADED:-}" == "1" ]]; then
    return 0
fi
_SOCOOL_DEPS_LOADED=1

# ────────────────────────────────────────────────────────────────────────
# Package manager detection
# ────────────────────────────────────────────────────────────────────────

detect_package_manager() {
    case "$SOCOOL_OS" in
        darwin)
            command -v brew >/dev/null 2>&1 || die 21 "brew not found. Install Homebrew from https://brew.sh/ and re-run."
            printf 'brew'
            return 0
            ;;
        linux)
            command -v apt-get >/dev/null 2>&1 && { printf 'apt';    return 0; }
            command -v dnf     >/dev/null 2>&1 && { printf 'dnf';    return 0; }
            command -v pacman  >/dev/null 2>&1 && { printf 'pacman'; return 0; }
            die 21 "no supported package manager found on Linux host (looked for apt-get, dnf, pacman)"
            ;;
        *)
            die 21 "dependency auto-install on os='$SOCOOL_OS' not supported by setup.sh. Use setup.ps1 on Windows."
            ;;
    esac
}

# ────────────────────────────────────────────────────────────────────────
# Sudo handling
# ────────────────────────────────────────────────────────────────────────

_sudo_verified=0

_ensure_sudo() {
    [[ "$_sudo_verified" == "1" ]] && return 0
    # Darwin + pacman/apt/dnf: sudo needed. Homebrew refuses sudo.
    if [[ "$SOCOOL_OS" == "darwin" ]]; then
        _sudo_verified=1
        return 0
    fi
    if [[ "$(id -u)" == "0" ]]; then
        _sudo_verified=1
        return 0
    fi
    if ! command -v sudo >/dev/null 2>&1; then
        die 21 "sudo not available but required to install packages. Re-run as root or install sudo."
    fi
    if ! sudo -n true >/dev/null 2>&1; then
        if [[ ! -t 0 ]] && [[ "${SOCOOL_YES:-0}" != "1" ]]; then
            die 64 "sudo credentials not cached; run interactively or pre-cache with 'sudo -v' before setting SOCOOL_YES=1."
        fi
        banner "Action required: cache sudo credentials"
        printf 'What:  SOCool needs to install host packages (git, python3, hypervisor, etc).\n' >&2
        printf 'Where: <your local sudo password prompt>\n' >&2
        printf 'Paste: <your sudo password>\n' >&2
        printf 'Env:   SOCOOL_YES=1 (non-interactive: pre-cache with sudo -v)\n' >&2
        sudo -v
    fi
    _sudo_verified=1
}

_run_sudo() {
    _ensure_sudo
    if [[ "$(id -u)" == "0" ]]; then
        "$@"
    else
        sudo -- "$@"
    fi
}

# ────────────────────────────────────────────────────────────────────────
# Per-package-manager install primitives
# ────────────────────────────────────────────────────────────────────────

_pkg_install_apt() {
    # _pkg_install_apt <deb-package-name> ...
    _run_sudo env DEBIAN_FRONTEND=noninteractive apt-get update -y
    _run_sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$@"
}

_pkg_install_dnf() {
    _run_sudo dnf install -y "$@"
}

_pkg_install_pacman() {
    _run_sudo pacman -Sy --noconfirm --needed "$@"
}

_pkg_install_brew() {
    # Homebrew must never run under sudo.
    brew install "$@"
}

_pkg_install_brew_cask() {
    brew install --cask "$@"
}

# ────────────────────────────────────────────────────────────────────────
# Per-dependency helpers
# ────────────────────────────────────────────────────────────────────────

# _ensure_confirm <package-description> — in interactive mode, prompts
# y/N before any install. Non-interactive respects SOCOOL_YES.
_ensure_confirm() {
    local what="$1"
    if [[ "${SOCOOL_YES:-0}" == "1" ]]; then
        log_info "installing $what (SOCOOL_YES=1)"
        return 0
    fi
    local answer
    answer="$(prompt_yes_no 'dep-install' "Install $what now?" 'y' 'SOCOOL_YES')"
    [[ "$answer" == "y" ]] || die 21 "aborted by user: $what required"
}

ensure_git() {
    command -v git >/dev/null 2>&1 && { log_debug "git: present"; return 0; }
    _ensure_confirm "git"
    case "$(detect_package_manager)" in
        apt)    _pkg_install_apt git ;;
        dnf)    _pkg_install_dnf git ;;
        pacman) _pkg_install_pacman git ;;
        brew)   _pkg_install_brew git ;;
    esac
}

ensure_python() {
    if command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' >/dev/null 2>&1; then
        log_debug "python3 + PyYAML: present"
        return 0
    fi
    _ensure_confirm "python3 and PyYAML (for config parsing)"
    case "$(detect_package_manager)" in
        apt)    _pkg_install_apt python3 python3-yaml ;;
        dnf)    _pkg_install_dnf python3 python3-pyyaml ;;
        pacman) _pkg_install_pacman python python-yaml ;;
        brew)
            command -v python3 >/dev/null 2>&1 || _pkg_install_brew python
            # Homebrew's python ships with pip; PyYAML via pip3 install --user.
            python3 -m pip install --user --quiet pyyaml
            ;;
    esac
}

# Packer and Vagrant: on apt/dnf/pacman we refuse to auto-configure the
# HashiCorp repo. See module header for rationale.
ensure_packer() {
    command -v packer >/dev/null 2>&1 && { log_debug "packer: present"; return 0; }
    _ensure_confirm "packer"
    case "$(detect_package_manager)" in
        apt|dnf)
            _hashicorp_repo_refusal_message "packer"
            die 21 "packer not found" ;;
        pacman)
            die 21 "packer is not in Arch core/extra/community. Install via AUR (e.g., 'yay -S packer') and re-run." ;;
        brew)
            brew tap hashicorp/tap
            _pkg_install_brew hashicorp/tap/packer ;;
    esac
}

ensure_vagrant() {
    command -v vagrant >/dev/null 2>&1 && { log_debug "vagrant: present"; return 0; }
    _ensure_confirm "vagrant"
    case "$(detect_package_manager)" in
        apt|dnf)
            _hashicorp_repo_refusal_message "vagrant"
            die 21 "vagrant not found" ;;
        pacman)
            _pkg_install_pacman vagrant ;;
        brew)
            brew tap hashicorp/tap
            _pkg_install_brew hashicorp/tap/hashicorp-vagrant ;;
    esac
}

# _hashicorp_repo_refusal_message <pkg> — prints the exact copy-paste
# commands to add the HashiCorp apt/dnf repo, then exits. SOCool
# does not auto-configure third-party package repositories: adding a
# trusted signing key + sources.list entry is a per-host security
# decision and we want the user's conscious consent each time. Verified
# 2026-04-24.
_hashicorp_repo_refusal_message() {
    local pkg="$1" pm; pm="$(detect_package_manager)"
    log_error ""
    log_error "SOCool does not auto-configure HashiCorp's package repository"
    log_error "because it requires adding a trusted GPG key and a new"
    log_error "sources entry to your system — a decision only you should"
    log_error "make. The official instructions are:"
    log_error ""
    case "$pm" in
        apt)
            log_error "  # Ubuntu / Debian"
            log_error "  wget -O- https://apt.releases.hashicorp.com/gpg | \\"
            log_error "      sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg"
            log_error "  echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com \$(lsb_release -cs) main\" | \\"
            log_error "      sudo tee /etc/apt/sources.list.d/hashicorp.list"
            log_error "  sudo apt-get update && sudo apt-get install -y $pkg"
            ;;
        dnf)
            log_error "  # Fedora / RHEL"
            log_error "  sudo dnf install -y dnf-plugins-core"
            log_error "  sudo dnf config-manager addrepo --from-repofile=https://rpm.releases.hashicorp.com/fedora/hashicorp.repo"
            log_error "  sudo dnf install -y $pkg"
            ;;
    esac
    log_error ""
    log_error "Reference: https://developer.hashicorp.com/$pkg/install"
    log_error ""
    log_error "Re-run setup.sh after installing."
}

# ensure_hypervisor <virtualbox|libvirt>
ensure_hypervisor() {
    local hv="$1"
    case "$hv" in
        virtualbox)
            if _vboxmanage_available; then log_debug "virtualbox: present"; return 0; fi
            _ensure_confirm "virtualbox"
            case "$(detect_package_manager)" in
                apt)    die 21 "VirtualBox not found. Install from Oracle's apt repo per https://www.virtualbox.org/wiki/Linux_Downloads and re-run." ;;
                dnf)    die 21 "VirtualBox not found. Install from Oracle's dnf repo per https://www.virtualbox.org/wiki/Linux_Downloads and re-run." ;;
                pacman) _pkg_install_pacman virtualbox ;;
                brew)   _pkg_install_brew_cask virtualbox ;;
            esac
            ;;
        libvirt)
            # libvirt means qemu-system + libvirt-daemon + virt-install
            # plus vagrant-libvirt plugin. Plugin install is vagrant's job,
            # not apt's; we do it after the OS packages are present.
            case "$(detect_package_manager)" in
                apt)
                    _ensure_confirm "qemu-kvm, libvirt-daemon-system, virtinst, build-essential"
                    _pkg_install_apt qemu-kvm libvirt-daemon-system libvirt-clients virtinst \
                                     bridge-utils dnsmasq-base build-essential libvirt-dev ruby-dev ;;
                dnf)
                    _ensure_confirm "qemu-kvm, libvirt, virt-install"
                    _pkg_install_dnf qemu-kvm libvirt libvirt-devel virt-install gcc ;;
                pacman)
                    _ensure_confirm "qemu-full, libvirt, virt-install"
                    _pkg_install_pacman qemu-full libvirt virt-install iptables-nft dnsmasq ;;
                brew)
                    _ensure_confirm "qemu"
                    _pkg_install_brew qemu ;;
            esac
            if command -v vagrant >/dev/null 2>&1; then
                if ! vagrant plugin list 2>/dev/null | grep -q '^vagrant-libvirt\b'; then
                    log_info "installing vagrant-libvirt plugin"
                    vagrant plugin install vagrant-libvirt
                fi
            fi
            ;;
        *)
            die 1 "ensure_hypervisor: unknown hypervisor '$hv'"
            ;;
    esac
}

# install_deps <hypervisor> — idempotent entry point.
install_deps() {
    local hv="${1:?install_deps requires a hypervisor arg}"
    log_info "resolving dependencies (pkg manager: $(detect_package_manager))"
    ensure_git
    ensure_python
    ensure_hypervisor "$hv"
    ensure_packer
    ensure_vagrant
    log_info "dependencies ready"
}
