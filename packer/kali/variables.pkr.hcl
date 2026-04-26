# packer/kali/variables.pkr.hcl — see shared/variables.pkr.hcl.tpl for
# the canonical documentation of each field.

variable "hypervisor" {
  type = string
  validation {
    condition     = contains(["virtualbox", "libvirt"], var.hypervisor)
    error_message = "Hypervisor must be 'virtualbox' or 'libvirt'."
  }
}

variable "output_dir" {
  type = string
}

variable "iso_cache_dir" {
  type    = string
  default = ""
}

variable "box_version" {
  type    = string
  default = "0.1.0"
}

# Kali-specific:

variable "kali_version" {
  type = string
  # Current stable at time of writing (verified 2026-04-24). Override with
  # `-var="kali_version=..."` when a newer release lands on cdimage.kali.org.
  default     = "2025.3"
  description = "Kali release line on cdimage.kali.org (e.g., '2025.3')."
}

variable "cpus" {
  type        = number
  default     = 2
  description = "Must match vms[hostname=kali].cpus in config/lab.yml."
}

variable "ram_mb" {
  type        = number
  default     = 4096
  description = "Must match vms[hostname=kali].ram_mb in config/lab.yml."
}

variable "disk_gb" {
  type        = number
  default     = 40
  description = "Must match vms[hostname=kali].disk_gb in config/lab.yml."
}
