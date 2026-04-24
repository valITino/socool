# packer/openvas/template.pkr.hcl — OpenVAS / GVM scanner on Ubuntu 24.04.
#
# Instead of building the Greenbone stack from source (half-dozen
# components, hours of build time), we use Greenbone Community
# Containers — official docker-compose stack from greenbone.github.io.
# That keeps our Packer template small: install Docker, fetch the
# compose manifest, pre-pull images so the first boot is quick.

packer {
  required_version = ">= 1.11.0"
  required_plugins {
    virtualbox = { version = "~> 1", source = "github.com/hashicorp/virtualbox" }
    qemu       = { version = "~> 1", source = "github.com/hashicorp/qemu" }
    vagrant    = { version = "~> 1", source = "github.com/hashicorp/vagrant" }
  }
}

locals {
  vm_name      = "socool-openvas-${var.box_version}"
  iso_url      = "https://releases.ubuntu.com/${var.ubuntu_release}/ubuntu-${var.ubuntu_release}-live-server-amd64.iso"
  iso_checksum = "file:https://releases.ubuntu.com/${var.ubuntu_release}/SHA256SUMS"
}

source "virtualbox-iso" "vm" {
  vm_name              = local.vm_name
  guest_os_type        = "Ubuntu_64"
  iso_url              = local.iso_url
  iso_checksum         = local.iso_checksum
  iso_target_path      = var.iso_cache_dir == "" ? null : "${var.iso_cache_dir}/ubuntu-${var.ubuntu_release}.iso"
  cpus = var.cpus; memory = var.ram_mb; disk_size = var.disk_gb * 1024
  http_directory = "${path.root}/http"; http_port_min = 9300; http_port_max = 9399
  boot_wait = "5s"
  boot_command = [
    "c<wait>",
    "linux /casper/vmlinuz --- autoinstall 'ds=nocloud-net;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/'",
    "<enter><wait>",
    "initrd /casper/initrd",
    "<enter><wait>",
    "boot<enter>"
  ]
  vboxmanage = [
    ["modifyvm", "{{.Name}}", "--memory", "${var.ram_mb}"],
    ["modifyvm", "{{.Name}}", "--cpus",   "${var.cpus}"],
    ["modifyvm", "{{.Name}}", "--nic1",   "nat"],
    ["modifyvm", "{{.Name}}", "--nictype1", "virtio"],
    ["modifyvm", "{{.Name}}", "--firmware", "efi"],
  ]
  ssh_username = "vagrant"; ssh_password = "BUILDONLY-will-be-rotated"
  ssh_port = 22; ssh_wait_timeout = "45m"; ssh_handshake_attempts = 200
  shutdown_command = "echo 'BUILDONLY-will-be-rotated' | sudo -S shutdown -P now"
  format = "ovf"
}

source "qemu" "vm" {
  vm_name              = local.vm_name
  iso_url              = local.iso_url
  iso_checksum         = local.iso_checksum
  iso_target_path      = var.iso_cache_dir == "" ? null : "${var.iso_cache_dir}/ubuntu-${var.ubuntu_release}.iso"
  cpus = var.cpus; memory = var.ram_mb; disk_size = "${var.disk_gb}G"
  http_directory = "${path.root}/http"; http_port_min = 9300; http_port_max = 9399
  boot_wait = "5s"
  boot_command = [
    "c<wait>",
    "linux /casper/vmlinuz --- autoinstall 'ds=nocloud-net;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/'",
    "<enter><wait>",
    "initrd /casper/initrd",
    "<enter><wait>",
    "boot<enter>"
  ]
  ssh_username = "vagrant"; ssh_password = "BUILDONLY-will-be-rotated"
  ssh_port = 22; ssh_wait_timeout = "45m"; ssh_handshake_attempts = 200
  shutdown_command = "echo 'BUILDONLY-will-be-rotated' | sudo -S shutdown -P now"
  accelerator = "kvm"; disk_interface = "virtio"; net_device = "virtio-net"
  format = "qcow2"; headless = true
}

build {
  name = "socool-openvas"
  sources = [ "source.virtualbox-iso.vm", "source.qemu.vm" ]

  provisioner "shell" {
    scripts = [
      "${path.root}/scripts/vagrant-user.sh",
      "${path.root}/scripts/install-greenbone.sh",
      "${path.root}/scripts/rotate-credentials.sh",
      "${path.root}/scripts/cleanup.sh",
    ]
    execute_command = "echo 'BUILDONLY-will-be-rotated' | {{ .Vars }} sudo -S -E bash '{{ .Path }}'"
    expect_disconnect = true
    env = {
      "SOCOOL_GREENBONE_COMPOSE_URL" = var.greenbone_compose_url
    }
  }

  provisioner "file" {
    source      = "/tmp/socool-openvas-credentials.json"
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
