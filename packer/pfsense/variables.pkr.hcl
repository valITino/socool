variable "hypervisor" {
  type = string
  validation {
    condition     = contains(["virtualbox", "libvirt"], var.hypervisor)
    error_message = "hypervisor must be 'virtualbox' or 'libvirt'."
  }
}

variable "output_dir"    { type = string }
variable "iso_cache_dir" { type = string, default = "" }
variable "box_version"   { type = string, default = "0.1.0" }

variable "pfsense_version" {
  type    = string
  # 2.7.2 is the last ISO-installable CE release (verified 2026-04-24).
  # Netgate stopped publishing standalone ISOs starting with 2.8.0.
  default = "2.7.2"
}

variable "cpus"    { type = number, default = 1 }
variable "ram_mb"  { type = number, default = 1024 }
variable "disk_gb" { type = number, default = 8 }
