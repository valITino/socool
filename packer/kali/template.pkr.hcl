# packer/kali/template.pkr.hcl — Kali Linux attacker VM.
#
# Builds a VirtualBox or QEMU-based Vagrant box from the Kali installer
# ISO using a Debian preseed unattended installation. The resulting box
# is fed to Vagrant by scripts/provision/run-pipeline.*.
#
# Run:
#   packer init template.pkr.hcl
#   packer build -only=socool-kali.virtualbox-iso.vm \
#     -var="hypervisor=virtualbox" \
#     -var="output_dir=/abs/path" \
#     template.pkr.hcl
#
# All variables are declared in variables.pkr.hcl.

packer {
  required_version = ">= 1.11.0"
  required_plugins {
    virtualbox = {
      version = "~> 1"
      source  = "github.com/hashicorp/virtualbox"
    }
    qemu = {
      version = "~> 1"
      source  = "github.com/hashicorp/qemu"
    }
    vagrant = {
      version = "~> 1"
      source  = "github.com/hashicorp/vagrant"
    }
  }
}

locals {
  vm_name = "socool-kali-${var.box_version}"
  iso_url = "https://cdimage.kali.org/kali-${var.kali_version}/kali-linux-${var.kali_version}-installer-amd64.iso"
  # `file:` lets Packer fetch the publisher's signed SHA256SUMS at build
  # time; no literal checksum ever enters the repo. Kali publishes the
  # SHA256SUMS next to the ISO on cdimage.kali.org.
  iso_checksum = "file:https://cdimage.kali.org/kali-${var.kali_version}/SHA256SUMS"
}

# ─── Source: VirtualBox ─────────────────────────────────────────────────
source "virtualbox-iso" "vm" {
  vm_name         = local.vm_name
  guest_os_type   = "Debian_64"
  iso_url         = local.iso_url
  iso_checksum    = local.iso_checksum
  iso_target_path = var.iso_cache_dir == "" ? null : "${var.iso_cache_dir}/kali-${var.kali_version}.iso"

  # Hardware sizing comes from config/lab.yml via run-pipeline.* args.
  cpus      = var.cpus
  memory    = var.ram_mb
  disk_size = var.disk_gb * 1024

  # Packer serves the preseed over HTTP. Port range avoids conflict
  # with the host's own services.
  http_directory = "${path.root}/http"
  http_port_min  = 8800
  http_port_max  = 8899

  boot_wait = "5s"
  boot_command = [
    "<esc><wait>",
    "install <wait>",
    "auto=true <wait>",
    "priority=critical <wait>",
    "url=http://{{ .HTTPIP }}:{{ .HTTPPort }}/preseed.cfg <wait>",
    "<enter>"
  ]

  # First-boot account — rotated by scripts/rotate-credentials.sh.
  ssh_username           = "vagrant"
  ssh_password           = "BUILDONLY-will-be-rotated"
  ssh_port               = 22
  ssh_wait_timeout       = "30m"
  ssh_handshake_attempts = 100

  shutdown_command = "echo 'BUILDONLY-will-be-rotated' | sudo -S shutdown -P now"

  guest_additions_mode    = "disable"
  virtualbox_version_file = ""

  vboxmanage = [
    ["modifyvm", "{{.Name}}", "--nic1", "nat"],
    ["modifyvm", "{{.Name}}", "--nictype1", "virtio"],
    ["modifyvm", "{{.Name}}", "--memory", "${var.ram_mb}"],
    ["modifyvm", "{{.Name}}", "--cpus", "${var.cpus}"],
    ["modifyvm", "{{.Name}}", "--firmware", "efi"],
  ]

  format = "ovf"
}

# ─── Source: QEMU / libvirt ────────────────────────────────────────────
source "qemu" "vm" {
  vm_name         = local.vm_name
  iso_url         = local.iso_url
  iso_checksum    = local.iso_checksum
  iso_target_path = var.iso_cache_dir == "" ? null : "${var.iso_cache_dir}/kali-${var.kali_version}.iso"

  cpus      = var.cpus
  memory    = var.ram_mb
  disk_size = "${var.disk_gb}G"

  http_directory = "${path.root}/http"
  http_port_min  = 8800
  http_port_max  = 8899

  boot_wait = "5s"
  boot_command = [
    "<esc><wait>",
    "install <wait>",
    "auto=true <wait>",
    "priority=critical <wait>",
    "url=http://{{ .HTTPIP }}:{{ .HTTPPort }}/preseed.cfg <wait>",
    "<enter>"
  ]

  ssh_username           = "vagrant"
  ssh_password           = "BUILDONLY-will-be-rotated"
  ssh_port               = 22
  ssh_wait_timeout       = "30m"
  ssh_handshake_attempts = 100

  shutdown_command = "echo 'BUILDONLY-will-be-rotated' | sudo -S shutdown -P now"

  accelerator    = "kvm"
  disk_interface = "virtio"
  net_device     = "virtio-net"
  format         = "qcow2"
  headless       = true
}

# ─── Build ─────────────────────────────────────────────────────────────
build {
  name = "socool-kali"
  sources = [
    "source.virtualbox-iso.vm",
    "source.qemu.vm",
  ]

  # The provisioner-pair runs in a specific order: install Vagrant's
  # insecure SSH key, apply Kali-specific hardening, then rotate the
  # build-only credentials to the final rotated values. cleanup.sh is
  # last so it runs even if rotate-credentials earlier aborted.
  provisioner "shell" {
    scripts = [
      "${path.root}/scripts/vagrant-user.sh",
      "${path.root}/scripts/rotate-credentials.sh",
      "${path.root}/scripts/cleanup.sh",
    ]
    execute_command   = "echo 'BUILDONLY-will-be-rotated' | {{ .Vars }} sudo -S -E bash '{{ .Path }}'"
    expect_disconnect = true
  }

  # The rotated credentials land at packer/kali/artifacts/credentials.json
  # written by rotate-credentials.sh. `packer build` downloads that file
  # via scp already because the file is inside /vagrant on the guest —
  # actually no, the provisioner writes to /tmp/socool-creds.json on the
  # guest, then this file provisioner pulls it back to the host.
  provisioner "file" {
    source      = "/tmp/socool-kali-credentials.json"
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
