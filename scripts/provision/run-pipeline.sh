#!/usr/bin/env bash
# scripts/provision/run-pipeline.sh — per-VM Packer build + `vagrant up`.
#
# Step 3 ships a dispatcher that iterates VMs from config/lab.yml in
# boot_order and calls:
#   packer build <packer/<vm>/template.pkr.hcl>
#   (after all builds) vagrant up (from vagrant/Vagrantfile)
# Packer templates and the Vagrantfile land in Steps 5 and 6; this file
# detects their absence and reports clearly.

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

# run_pipeline <hypervisor> <scanner-choice> <windows-source>
run_pipeline() {
    local hv="${1:?hypervisor arg required}"
    local scanner="${2:?scanner arg required}"
    local winsrc="${3:?windows-source arg required}"

    log_info "provision pipeline: hv=$hv scanner=$scanner windows=$winsrc"

    local repo_root="$socool_repo_root"
    local built=0 skipped=0 missing=0

    while IFS= read -r vm; do
        [[ -z "$vm" ]] && continue
        validate_hostname_token "$vm"

        # Filter: scanner choice gates nessus/openvas.
        case "$vm" in
            nessus)  [[ "$scanner" != "nessus"  ]] && { log_info "skip vm=$vm (scanner=$scanner)"; skipped=$((skipped+1)); continue; } ;;
            openvas) [[ "$scanner" != "openvas" ]] && { log_info "skip vm=$vm (scanner=$scanner)"; skipped=$((skipped+1)); continue; } ;;
        esac

        local template="$repo_root/packer/$vm/template.pkr.hcl"
        local box_name
        box_name="$(lab_config_get "vms.$(_lab_vm_index "$vm").box")"
        local output_dir="${SOCOOL_BOX_OUTPUT_DIR:-$repo_root/.socool-cache/boxes}"
        mkdir -p -- "$output_dir"
        local box_file="$output_dir/$box_name.box"

        if [[ ! -f "$template" ]]; then
            log_warn "packer template missing: $template (Step 5 pending for vm=$vm)"
            missing=$((missing+1))
            continue
        fi

        if [[ -f "$box_file" ]]; then
            log_info "box already built, skipping: $box_file"
            skipped=$((skipped+1))
            continue
        fi

        banner "Packer build: $vm"
        log_info "packer build $template -> $box_file"

        # Per-hypervisor source name: the Packer templates declare
        # 'source "virtualbox-iso" "vm"' and 'source "qemu" "vm"';
        # -only = "<build_name>.<source_type>.vm".
        local packer_source
        case "$hv" in
            virtualbox) packer_source="socool-${vm}.virtualbox-iso.vm" ;;
            libvirt)    packer_source="socool-${vm}.qemu.vm" ;;
            *)          die 1 "unknown hypervisor: $hv" ;;
        esac

        # Common variables every template accepts.
        local -a packer_vars=(
            "-var=hypervisor=$hv"
            "-var=output_dir=$output_dir"
            "-var=iso_cache_dir=${SOCOOL_ISO_CACHE_DIR:-$repo_root/.socool-cache/iso}"
        )

        # Per-VM extras.
        case "$vm" in
            windows-victim)
                # Resolve the Windows ISO URL: either a user-supplied
                # URL (eval source) or a file:// path from the local
                # ISO path.
                local win_url="${SOCOOL_WINDOWS_ISO_URL:-}"
                if [[ "$winsrc" == "iso" && -n "${SOCOOL_WINDOWS_ISO_PATH:-}" ]]; then
                    win_url="file://${SOCOOL_WINDOWS_ISO_PATH}"
                fi
                if [[ -z "$win_url" ]]; then
                    die 40 "windows-victim build needs SOCOOL_WINDOWS_ISO_URL (for eval) or SOCOOL_WINDOWS_ISO_PATH (for iso). See packer/windows-victim/README.md."
                fi
                packer_vars+=("-var=windows_iso_url=$win_url")
                packer_vars+=("-var=windows_iso_checksum=${SOCOOL_WINDOWS_ISO_CHECKSUM:-none}")
                ;;
            nessus)
                [[ -n "${SOCOOL_NESSUS_DEB_URL:-}"         ]] || die 40 "nessus build needs SOCOOL_NESSUS_DEB_URL. See packer/nessus/README.md."
                [[ -n "${SOCOOL_NESSUS_ACTIVATION_CODE:-}" ]] || die 40 "nessus build needs SOCOOL_NESSUS_ACTIVATION_CODE."
                packer_vars+=("-var=nessus_deb_url=$SOCOOL_NESSUS_DEB_URL")
                packer_vars+=("-var=nessus_activation_code=$SOCOOL_NESSUS_ACTIVATION_CODE")
                ;;
        esac

        # Argument array; no string concatenation.
        ( cd -- "$repo_root/packer/$vm" && \
          packer init -- "$template" && \
          packer build -only="$packer_source" "${packer_vars[@]}" -- "$template" )
        built=$((built+1))
    done < <(lab_vm_hostnames)

    log_info "pipeline summary: built=$built skipped=$skipped template-missing=$missing"

    # Final stage: vagrant up the lab.
    local vagrantfile="$repo_root/vagrant/Vagrantfile"
    if [[ ! -f "$vagrantfile" ]]; then
        log_warn "Vagrantfile missing: $vagrantfile (Step 6 pending). The lab cannot be started yet."
        return 0
    fi
    banner "vagrant up"
    ( cd -- "$repo_root/vagrant" && vagrant up --provider "$(_vagrant_provider_for "$hv")" )
}

# _vagrant_provider_for <hypervisor> — maps our hypervisor name to Vagrant's.
_vagrant_provider_for() {
    case "$1" in
        virtualbox) printf 'virtualbox' ;;
        libvirt)    printf 'libvirt' ;;
        *) die 1 "_vagrant_provider_for: unknown '$1'" ;;
    esac
}

# _lab_vm_index <hostname> — returns the vms[] list index (0-based).
_lab_vm_index() {
    local target="$1"
    python3 - "$socool_repo_root/config/lab.yml" "$target" <<'PY'
import sys, yaml
with open(sys.argv[1], 'r') as f:
    data = yaml.safe_load(f)
for i, vm in enumerate(data.get('vms', [])):
    if vm['hostname'] == sys.argv[2]:
        print(i)
        sys.exit(0)
sys.exit(1)
PY
}

# If invoked directly (not sourced), run the pipeline with the first three
# positional arguments so a maintainer can test in isolation.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    detect_host
    load_env
    run_pipeline "${1:-}" "${2:-}" "${3:-}"
fi
