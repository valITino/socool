# packer/thehive/template.pkr.hcl — TheHive 5 Community Edition on Ubuntu 24.04.
#
# Base image: Ubuntu Server 24.04 LTS (Noble Numbat) installed via
# Subiquity autoinstall (cloud-init user-data — NOT preseed; Subiquity
# dropped preseed support in 20.04+).
#
# On top of the base OS we install Docker Engine, clone StrangeBee's
# official prod1-thehive Compose profile, run their init.sh to
# generate certs and .env, and pre-pull the Cassandra / Elasticsearch /
# TheHive / Nginx images so first boot is fast. A systemd unit brings
# the stack up at boot; a second one rotates the default
# admin@thehive.local password via TheHive's REST API on first boot.
# Pinned to TheHive 5.7.1 (latest 5.x as of 2026-04-27).

packer {
  required_version = ">= 1.11.0"
  required_plugins {
    virtualbox = { version = "~> 1", source = "github.com/hashicorp/virtualbox" }
    qemu       = { version = "~> 1", source = "github.com/hashicorp/qemu" }
    vagrant    = { version = "~> 1", source = "github.com/hashicorp/vagrant" }
  }
}

locals {
  vm_name      = "socool-thehive-${var.box_version}"
  iso_url      = "https://releases.ubuntu.com/${var.ubuntu_release}/ubuntu-${var.ubuntu_release}-live-server-amd64.iso"
  iso_checksum = "file:https://releases.ubuntu.com/${var.ubuntu_release}/SHA256SUMS"
}

# ─── Source: VirtualBox ─────────────────────────────────────────────────
source "virtualbox-iso" "vm" {
  vm_name         = local.vm_name
  guest_os_type   = "Ubuntu_64"
  iso_url         = local.iso_url
  iso_checksum    = local.iso_checksum
  iso_target_path = var.iso_cache_dir == "" ? null : "${var.iso_cache_dir}/ubuntu-${var.ubuntu_release}.iso"

  cpus      = var.cpus
  memory    = var.ram_mb
  disk_size = var.disk_gb * 1024

  http_directory = "${path.root}/http"
  http_port_min  = 9400
  http_port_max  = 9499

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

  ssh_username           = "vagrant"
  ssh_password           = "BUILDONLY-will-be-rotated"
  ssh_port               = 22
  ssh_wait_timeout       = "45m"
  ssh_handshake_attempts = 200

  shutdown_command = "echo 'BUILDONLY-will-be-rotated' | sudo -S shutdown -P now"
  format           = "ovf"
}

# ─── Source: QEMU / libvirt ────────────────────────────────────────────
source "qemu" "vm" {
  vm_name         = local.vm_name
  iso_url         = local.iso_url
  iso_checksum    = local.iso_checksum
  iso_target_path = var.iso_cache_dir == "" ? null : "${var.iso_cache_dir}/ubuntu-${var.ubuntu_release}.iso"

  cpus      = var.cpus
  memory    = var.ram_mb
  disk_size = "${var.disk_gb}G"

  http_directory = "${path.root}/http"
  http_port_min  = 9400
  http_port_max  = 9499

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

  ssh_username           = "vagrant"
  ssh_password           = "BUILDONLY-will-be-rotated"
  ssh_port               = 22
  ssh_wait_timeout       = "45m"
  ssh_handshake_attempts = 200

  shutdown_command = "echo 'BUILDONLY-will-be-rotated' | sudo -S shutdown -P now"
  accelerator      = "kvm"
  disk_interface   = "virtio"
  net_device       = "virtio-net"
  format           = "qcow2"
  headless         = true
}

# ─── Build ─────────────────────────────────────────────────────────────
build {
  name = "socool-thehive"
  sources = [
    "source.virtualbox-iso.vm",
    "source.qemu.vm",
  ]

  provisioner "shell" {
    scripts = [
      "${path.root}/scripts/vagrant-user.sh",
      "${path.root}/scripts/install-thehive.sh",
      "${path.root}/scripts/rotate-credentials.sh",
      "${path.root}/scripts/cleanup.sh",
    ]
    execute_command   = "echo 'BUILDONLY-will-be-rotated' | {{ .Vars }} sudo -S -E bash '{{ .Path }}'"
    expect_disconnect = true
    env = {
      "SOCOOL_STRANGEBEE_DOCKER_REF"       = var.strangebee_docker_ref
      "SOCOOL_THEHIVE_IMAGE_VERSION"       = var.thehive_image_version
      "SOCOOL_CASSANDRA_IMAGE_VERSION"     = var.cassandra_image_version
      "SOCOOL_ELASTICSEARCH_IMAGE_VERSION" = var.elasticsearch_image_version
      "SOCOOL_NGINX_IMAGE_VERSION"         = var.nginx_image_version
      "SOCOOL_CASSANDRA_HEAP_MB"           = var.cassandra_heap_mb
      "SOCOOL_ELASTICSEARCH_HEAP_MB"       = var.elasticsearch_heap_mb
      "SOCOOL_THEHIVE_HEAP_MB"             = var.thehive_heap_mb
    }
  }

  provisioner "file" {
    source      = "/tmp/socool-thehive-credentials.json"
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
