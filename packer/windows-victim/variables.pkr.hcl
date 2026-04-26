variable "hypervisor" {
  type = string
  validation {
    condition     = contains(["virtualbox", "libvirt"], var.hypervisor)
    error_message = "Hypervisor must be 'virtualbox' or 'libvirt'."
  }
}

variable "output_dir" { type = string }
variable "iso_cache_dir" {
  type    = string
  default = ""
}
variable "box_version" {
  type    = string
  default = "0.1.0"
}
# ─── Windows ISO: user-supplied ─────────────────────────────────────────
# The Microsoft Evaluation Center URL is session-gated and rotates, so
# we cannot pin one in the repo. The user provides either:
#   - a direct URL (e.g., to a local mirror) via `windows_iso_url`, or
#   - a local path (file://) also via `windows_iso_url`.
# `windows_iso_checksum` uses Packer's `file:` scheme when a publisher
# SHA256 file is available, or a literal `sha256:...` as a last resort.
variable "windows_iso_url" {
  type        = string
  description = "URL or file:// path to the Windows 11 Enterprise Evaluation ISO."
}

variable "windows_iso_checksum" {
  type        = string
  description = "Packer-format iso_checksum: 'file:...', 'sha256:...', or 'none' (not recommended)."
  default     = "none"
}

# Windows VM (and the Evaluation Center image) is x86_64 only.
variable "cpus" {
  type    = number
  default = 2
}
variable "ram_mb" {
  type    = number
  default = 4096
}
variable "disk_gb" {
  type    = number
  default = 60
}
variable "wazuh_manager_ip" {
  type        = string
  default     = "10.42.20.10"
  description = "IP of the Wazuh manager VM (management network); the Windows agent enrols with this on first boot."
}

# ─── Libvirt / QEMU-specific ────────────────────────────────────────────
variable "virtio_win_iso_path" {
  type        = string
  default     = ""
  description = "Absolute path to the Fedora virtio-win ISO (drivers). Empty = use IDE/e1000 (slow)."
}

variable "ovmf_code_path" {
  type        = string
  default     = "/usr/share/OVMF/OVMF_CODE.fd"
  description = "Path to OVMF/UEFI firmware on the libvirt host."
}
