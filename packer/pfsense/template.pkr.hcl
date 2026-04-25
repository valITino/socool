# packer/pfsense/template.pkr.hcl — pfSense CE 2.7.2 firewall VM.
#
# pfSense is FreeBSD under the hood. Unattended installation is
# possible with `installerconfig` (bsdinstall's scripted mode) but the
# recipe is fragile: the file has to be present on a mounted media the
# installer will source. Our approach: Packer serves the file over HTTP
# and drives bsdinstall interactively long enough to shell-out and
# fetch+execute it, then the installerconfig takes over.
#
# This is the classic hard-case for Packer; expect the first real build
# to require boot_command timing tuning per host. See README.md.
#
# pfSense CE 2.8 does NOT ship a standalone ISO — Netgate moved to a
# network-only installer. 2.7.2 is the last ISO-installable release
# (verified 2026-04-24). Override `pfsense_version` only if a newer
# ISO-installable release ships.

packer {
  required_version = ">= 1.11.0"
  required_plugins {
    virtualbox = { version = "~> 1", source = "github.com/hashicorp/virtualbox" }
    qemu       = { version = "~> 1", source = "github.com/hashicorp/qemu" }
    vagrant    = { version = "~> 1", source = "github.com/hashicorp/vagrant" }
  }
}

locals {
  vm_name = "socool-pfsense-${var.box_version}"
  # Netgate's atxfiles mirror is the canonical source for CE ISOs.
  iso_url_gz    = "https://atxfiles.netgate.com/mirror/downloads/pfSense-CE-${var.pfsense_version}-RELEASE-amd64.iso.gz"
  # Netgate publishes a SHA256 file alongside the .iso.gz. Packer's
  # `file:` prefix fetches the live value at build time.
  iso_checksum  = "file:${local.iso_url_gz}.sha256"
}

# ─── Source: VirtualBox ─────────────────────────────────────────────────
source "virtualbox-iso" "vm" {
  vm_name              = local.vm_name
  guest_os_type        = "FreeBSD_64"
  iso_url              = local.iso_url_gz
  iso_checksum         = local.iso_checksum
  iso_target_extension = "iso.gz"
  iso_target_path      = var.iso_cache_dir == "" ? null : "${var.iso_cache_dir}/pfsense-${var.pfsense_version}.iso.gz"

  cpus     = var.cpus
  memory   = var.ram_mb
  disk_size = var.disk_gb * 1024

  # Three NICs matching the lab's three networks: WAN simulated,
  # LAN, management. The actual network assignment happens when
  # Vagrant brings the VM up per config/lab.yml.
  vboxmanage = [
    ["modifyvm", "{{.Name}}", "--memory", "${var.ram_mb}"],
    ["modifyvm", "{{.Name}}", "--cpus", "${var.cpus}"],
    ["modifyvm", "{{.Name}}", "--nic1", "nat"],
    ["modifyvm", "{{.Name}}", "--nictype1", "virtio"],
    ["modifyvm", "{{.Name}}", "--nic2", "intnet", "--intnet2", "socool-lan"],
    ["modifyvm", "{{.Name}}", "--nictype2", "virtio"],
    ["modifyvm", "{{.Name}}", "--nic3", "intnet", "--intnet3", "socool-management"],
    ["modifyvm", "{{.Name}}", "--nictype3", "virtio"],
  ]

  http_directory = "${path.root}/http"
  http_port_min  = 8900
  http_port_max  = 8999

  # Boot and drive bsdinstall to shell-out, fetch installerconfig,
  # then execute it. pfSense 2.7.x boots to a menu; we select the
  # installer, open a shell, curl the installerconfig, and invoke
  # it. Timings tuned for a real build will likely need adjustment.
  boot_wait = "45s"
  boot_command = [
    "<enter>",                                # Accept boot menu default
    "<wait30s>",                              # Wait for installer to load
    "I<wait>",                                # Install
    "<wait5s>",
    "<f10><wait>",                            # F10 exits keymap config
    "<wait5s>",
    "<esc>",                                  # Cancel the disk selection menu
    "<wait5s>",
    "<leftShiftOn>s<leftShiftOff><wait>",     # Trigger bsdinstall shell (S)
    "<wait10s>",
    "fetch -o /tmp/installerconfig http://{{ .HTTPIP }}:{{ .HTTPPort }}/installerconfig<enter>",
    "<wait10s>",
    "exit<enter>",                            # Leaves shell; bsdinstall resumes and uses /tmp/installerconfig
  ]

  ssh_username       = "root"
  ssh_password       = "pfsense"   # pfSense default root password; rotated post-install
  ssh_port           = 22
  ssh_wait_timeout   = "45m"       # pfSense install is slow (install + reboot)
  ssh_handshake_attempts = 200

  shutdown_command = "/sbin/shutdown -p now"

  format = "ovf"
}

# ─── Source: QEMU / libvirt ────────────────────────────────────────────
source "qemu" "vm" {
  vm_name          = local.vm_name
  iso_url          = local.iso_url_gz
  iso_checksum     = local.iso_checksum
  iso_target_extension = "iso.gz"
  iso_target_path  = var.iso_cache_dir == "" ? null : "${var.iso_cache_dir}/pfsense-${var.pfsense_version}.iso.gz"

  cpus     = var.cpus
  memory   = var.ram_mb
  disk_size = "${var.disk_gb}G"

  http_directory = "${path.root}/http"
  http_port_min  = 8900
  http_port_max  = 8999

  # Boot command identical; libvirt carries the same VNC-driven input.
  boot_wait = "45s"
  boot_command = [
    "<enter>", "<wait30s>",
    "I<wait>", "<wait5s>",
    "<f10><wait>", "<wait5s>",
    "<esc>", "<wait5s>",
    "<leftShiftOn>s<leftShiftOff><wait>", "<wait10s>",
    "fetch -o /tmp/installerconfig http://{{ .HTTPIP }}:{{ .HTTPPort }}/installerconfig<enter>",
    "<wait10s>",
    "exit<enter>",
  ]

  ssh_username       = "root"
  ssh_password       = "pfsense"
  ssh_port           = 22
  ssh_wait_timeout   = "45m"
  ssh_handshake_attempts = 200

  shutdown_command = "/sbin/shutdown -p now"

  accelerator    = "kvm"
  disk_interface = "virtio"
  net_device     = "virtio-net"
  format         = "qcow2"
  headless       = true
}

# ─── Build ─────────────────────────────────────────────────────────────
build {
  name    = "socool-pfsense"
  sources = [
    "source.virtualbox-iso.vm",
    "source.qemu.vm",
  ]

  # pfSense's post-install provisioning runs over SSH (root + default
  # password 'pfsense'). We rotate the password, seed config.xml with
  # the three lab interfaces, and trim build residue.
  provisioner "file" {
    source      = "${path.root}/http/config-seed.xml"
    destination = "/tmp/config-seed.xml"
  }

  provisioner "shell" {
    scripts = [
      "${path.root}/scripts/post-install.sh",
      "${path.root}/scripts/rotate-credentials.sh",
    ]
    # FreeBSD's /bin/sh; pfSense ships neither bash by default nor
    # sudo (root-only). The shell execute_command reflects that.
    execute_command = "{{ .Vars }} /bin/sh '{{ .Path }}'"
    expect_disconnect = true
  }

  provisioner "file" {
    source      = "/tmp/socool-pfsense-credentials.json"
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
