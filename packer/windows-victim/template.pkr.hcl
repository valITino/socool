# packer/windows-victim/template.pkr.hcl — Windows 11 Enterprise victim VM.
#
# Packer drives an unattended install from the Windows 11 Enterprise
# evaluation ISO (download URL is session-gated at the Microsoft
# Evaluation Center — the user provides a path or URL via env vars
# or -var flags; see README.md).
#
# We do not bake a specific ISO URL into the repo because the Microsoft
# Evaluation Center's URLs are rotated periodically and one cannot be
# pinned the way vendor FTP/atxfiles URLs can. `windows_iso_url` and
# `windows_iso_checksum` are required inputs.

packer {
  required_version = ">= 1.11.0"
  required_plugins {
    virtualbox = { version = "~> 1", source = "github.com/hashicorp/virtualbox" }
    qemu       = { version = "~> 1", source = "github.com/hashicorp/qemu" }
    vagrant    = { version = "~> 1", source = "github.com/hashicorp/vagrant" }
  }
}

locals {
  vm_name = "socool-windows-victim-${var.box_version}"
}

# ─── Source: VirtualBox ─────────────────────────────────────────────────
source "virtualbox-iso" "vm" {
  vm_name         = local.vm_name
  guest_os_type   = "Windows11_64"
  iso_url         = var.windows_iso_url
  iso_checksum    = var.windows_iso_checksum
  iso_target_path = var.iso_cache_dir == "" ? null : "${var.iso_cache_dir}/windows-11-eval.iso"

  cpus      = var.cpus
  memory    = var.ram_mb
  disk_size = var.disk_gb * 1024

  # autounattend.xml is served as a CD ROM / floppy image. VirtualBox
  # builder exposes the HTTP server path; Windows setup looks in
  # A:\autounattend.xml first, so we also attach the file via
  # cd_files so setup finds it.
  http_directory = "${path.root}/http"
  http_port_min  = 9000
  http_port_max  = 9099
  cd_files = [
    "${path.root}/http/autounattend.xml",
    "${path.root}/http/setup-winrm.ps1",
  ]
  cd_label = "CIDATA"

  # Windows 11 installer expects a TPM + secure boot; we stub both
  # via VirtualBox's virtual TPM and EFI firmware.
  vboxmanage = [
    ["modifyvm", "{{.Name}}", "--firmware", "efi"],
    ["modifyvm", "{{.Name}}", "--tpm-type", "2.0"],
    ["modifyvm", "{{.Name}}", "--memory", "${var.ram_mb}"],
    ["modifyvm", "{{.Name}}", "--cpus", "${var.cpus}"],
    ["modifyvm", "{{.Name}}", "--nic1", "nat"],
    ["modifyvm", "{{.Name}}", "--nictype1", "virtio"],
    ["modifyvm", "{{.Name}}", "--audio-driver", "none"],
    ["modifyvm", "{{.Name}}", "--graphicscontroller", "vboxsvga"],
    ["modifyvm", "{{.Name}}", "--vram", "64"],
  ]

  communicator   = "winrm"
  winrm_username = "vagrant"
  winrm_password = "BUILDONLY-will-be-rotated"
  winrm_timeout  = "60m"
  winrm_use_ssl  = false
  winrm_insecure = true

  shutdown_command = "shutdown /s /t 10 /f /d p:4:1 /c \"Packer shutdown\""
  shutdown_timeout = "30m"

  format = "ovf"
}

# ─── Source: QEMU / libvirt ────────────────────────────────────────────
source "qemu" "vm" {
  vm_name         = local.vm_name
  iso_url         = var.windows_iso_url
  iso_checksum    = var.windows_iso_checksum
  iso_target_path = var.iso_cache_dir == "" ? null : "${var.iso_cache_dir}/windows-11-eval.iso"

  cpus      = var.cpus
  memory    = var.ram_mb
  disk_size = "${var.disk_gb}G"

  http_directory = "${path.root}/http"
  http_port_min  = 9000
  http_port_max  = 9099
  cd_files = [
    "${path.root}/http/autounattend.xml",
    "${path.root}/http/setup-winrm.ps1",
  ]
  cd_label = "CIDATA"

  # virtio drivers come from virtio-win ISO; the user supplies the path.
  # If not supplied we fall back to IDE + e1000 (slower).
  disk_interface = var.virtio_win_iso_path == "" ? "ide" : "virtio"
  net_device     = var.virtio_win_iso_path == "" ? "e1000" : "virtio-net"
  accelerator    = "kvm"
  format         = "qcow2"
  headless       = true

  # UEFI firmware for Windows 11.
  efi_boot     = true
  machine_type = "q35"
  firmware     = var.ovmf_code_path

  communicator   = "winrm"
  winrm_username = "vagrant"
  winrm_password = "BUILDONLY-will-be-rotated"
  winrm_timeout  = "60m"
  winrm_use_ssl  = false
  winrm_insecure = true

  shutdown_command = "shutdown /s /t 10 /f /d p:4:1 /c \"Packer shutdown\""
  shutdown_timeout = "30m"
}

# ─── Build ─────────────────────────────────────────────────────────────
build {
  name = "socool-windows-victim"
  sources = [
    "source.virtualbox-iso.vm",
    "source.qemu.vm",
  ]

  # PowerShell provisioners: bootstrap ordering + Wazuh agent +
  # credential rotation. cleanup runs last.
  provisioner "powershell" {
    scripts = [
      "${path.root}/scripts/install-wazuh-agent.ps1",
      "${path.root}/scripts/rotate-credentials.ps1",
      "${path.root}/scripts/cleanup.ps1",
    ]
    env = {
      "SOCOOL_WAZUH_MANAGER_IP" = var.wazuh_manager_ip
    }
  }

  provisioner "file" {
    source      = "C:/Windows/Temp/socool-windows-victim-credentials.json"
    destination = "${path.root}/artifacts/credentials.json"
    direction   = "download"
  }

  post-processor "vagrant" {
    provider_override   = var.hypervisor == "virtualbox" ? "virtualbox" : "libvirt"
    output              = "${var.output_dir}/${local.vm_name}.box"
    keep_input_artifact = false
  }

  post-processor "manifest" {
    output     = "${path.root}/artifacts/manifest.json"
    strip_path = true
  }
}
