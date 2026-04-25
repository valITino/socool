# packer/wazuh/template.pkr.hcl — Wazuh all-in-one SIEM on Ubuntu 24.04.
#
# Base image: Ubuntu Server 24.04 LTS (Noble Numbat). Unattended install
# via Subiquity autoinstall (cloud-init user-data / meta-data files —
# NOT preseed; Subiquity dropped preseed support in 20.04+).
#
# On top of the base OS we run wazuh-install.sh -a (assisted all-in-one),
# which installs Wazuh server + indexer + dashboard. Pinned to the 4.14
# release line verified 2026-04-24.

packer {
  required_version = ">= 1.11.0"
  required_plugins {
    virtualbox = { version = "~> 1", source = "github.com/hashicorp/virtualbox" }
    qemu       = { version = "~> 1", source = "github.com/hashicorp/qemu" }
    vagrant    = { version = "~> 1", source = "github.com/hashicorp/vagrant" }
  }
}

locals {
  vm_name = "socool-wazuh-${var.box_version}"
  # Ubuntu 24.04.x ISO. The "current" symlink under releases.ubuntu.com
  # always points at the latest point release; SHA256SUMS lives next to it.
  iso_url      = "https://releases.ubuntu.com/${var.ubuntu_release}/ubuntu-${var.ubuntu_release}-live-server-amd64.iso"
  iso_checksum = "file:https://releases.ubuntu.com/${var.ubuntu_release}/SHA256SUMS"
}

# ─── Source: VirtualBox ─────────────────────────────────────────────────
source "virtualbox-iso" "vm" {
  vm_name              = local.vm_name
  guest_os_type        = "Ubuntu_64"
  iso_url              = local.iso_url
  iso_checksum         = local.iso_checksum
  iso_target_path      = var.iso_cache_dir == "" ? null : "${var.iso_cache_dir}/ubuntu-${var.ubuntu_release}.iso"

  cpus     = var.cpus
  memory   = var.ram_mb
  disk_size = var.disk_gb * 1024

  http_directory = "${path.root}/http"
  http_port_min  = 9100
  http_port_max  = 9199

  # Ubuntu Subiquity reads cloud-init user-data from a URL passed via
  # kernel command line. No keyboard-navigation hacks needed.
  boot_wait = "5s"
  boot_command = [
    "c<wait>",
    "linux /casper/vmlinuz --- autoinstall 'ds=nocloud-net;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/'",
    "<enter><wait>",
    "initrd /casper/initrd",
    "<enter><wait>",
    "boot",
    "<enter>"
  ]

  vboxmanage = [
    ["modifyvm", "{{.Name}}", "--memory", "${var.ram_mb}"],
    ["modifyvm", "{{.Name}}", "--cpus", "${var.cpus}"],
    ["modifyvm", "{{.Name}}", "--nic1", "nat"],
    ["modifyvm", "{{.Name}}", "--nictype1", "virtio"],
    ["modifyvm", "{{.Name}}", "--firmware", "efi"],
  ]

  ssh_username       = "vagrant"
  ssh_password       = "BUILDONLY-will-be-rotated"
  ssh_port           = 22
  ssh_wait_timeout   = "45m"
  ssh_handshake_attempts = 200

  shutdown_command = "echo 'BUILDONLY-will-be-rotated' | sudo -S shutdown -P now"
  format = "ovf"
}

# ─── Source: QEMU / libvirt ────────────────────────────────────────────
source "qemu" "vm" {
  vm_name          = local.vm_name
  iso_url          = local.iso_url
  iso_checksum     = local.iso_checksum
  iso_target_path  = var.iso_cache_dir == "" ? null : "${var.iso_cache_dir}/ubuntu-${var.ubuntu_release}.iso"

  cpus     = var.cpus
  memory   = var.ram_mb
  disk_size = "${var.disk_gb}G"

  http_directory = "${path.root}/http"
  http_port_min  = 9100
  http_port_max  = 9199

  boot_wait = "5s"
  boot_command = [
    "c<wait>",
    "linux /casper/vmlinuz --- autoinstall 'ds=nocloud-net;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/'",
    "<enter><wait>",
    "initrd /casper/initrd",
    "<enter><wait>",
    "boot",
    "<enter>"
  ]

  ssh_username       = "vagrant"
  ssh_password       = "BUILDONLY-will-be-rotated"
  ssh_port           = 22
  ssh_wait_timeout   = "45m"
  ssh_handshake_attempts = 200

  shutdown_command = "echo 'BUILDONLY-will-be-rotated' | sudo -S shutdown -P now"
  accelerator    = "kvm"
  disk_interface = "virtio"
  net_device     = "virtio-net"
  format         = "qcow2"
  headless       = true
}

# ─── Build ─────────────────────────────────────────────────────────────
build {
  name    = "socool-wazuh"
  sources = [
    "source.virtualbox-iso.vm",
    "source.qemu.vm",
  ]

  provisioner "shell" {
    scripts = [
      "${path.root}/scripts/vagrant-user.sh",
      "${path.root}/scripts/install-wazuh.sh",
      "${path.root}/scripts/rotate-credentials.sh",
      "${path.root}/scripts/cleanup.sh",
    ]
    execute_command = "echo 'BUILDONLY-will-be-rotated' | {{ .Vars }} sudo -S -E bash '{{ .Path }}'"
    expect_disconnect = true
    env = {
      "SOCOOL_WAZUH_VERSION" = var.wazuh_version
    }
  }

  provisioner "file" {
    source      = "/tmp/socool-wazuh-credentials.json"
    destination = "${path.root}/artifacts/credentials.json"
    direction   = "download"
  }

  post-processor "vagrant" {
    provider_override = var.hypervisor == "virtualbox" ? "virtualbox" : "libvirt"
    output            = "${var.output_dir}/${local.vm_name}.box"
    keep_input_artifact = false
  }

  post-processor "manifest" {
    output     = "${path.root}/artifacts/manifest.json"
    strip_path = true
  }
}
