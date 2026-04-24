variable "hypervisor" {
  type = string
  validation {
    condition     = contains(["virtualbox", "libvirt"], var.hypervisor)
    error_message = "hypervisor must be 'virtualbox' or 'libvirt'."
  }
}

variable "output_dir"    { type = string }
variable "iso_cache_dir" {
  type    = string
  default = ""
}
variable "box_version" {
  type    = string
  default = "0.1.0"
}
variable "ubuntu_release" {
  type    = string
  default = "24.04.1"
  description = "Ubuntu Server LTS point release (e.g., '24.04.1')."
}

variable "wazuh_version" {
  type    = string
  default = "4.14"
  description = "Wazuh major.minor line; installer pulls latest 4.x.y."
}

variable "cpus" {
  type    = number
  default = 4
}
variable "ram_mb" {
  type    = number
  default = 8192
}
variable "disk_gb" {
  type    = number
  default = 60
}