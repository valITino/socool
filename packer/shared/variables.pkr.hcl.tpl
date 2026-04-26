# packer/shared/variables.pkr.hcl.tpl
#
# This file documents the common variables every per-VM template
# declares. It is NOT imported directly — Packer HCL2 has no cross-
# template import mechanism — so each template copies the relevant
# variable blocks and extends with its own. Kept here as the canonical
# reference so per-VM templates stay in sync.
#
# Rename to .pkr.hcl if you want Packer to validate it as a loose file
# (we leave it as .tpl so `packer build` in a per-VM dir does not pick
# it up and fail).

variable "hypervisor" {
  type        = string
  description = "Target hypervisor: 'virtualbox' or 'libvirt'."
  validation {
    condition     = contains(["virtualbox", "libvirt"], var.hypervisor)
    error_message = "Hypervisor must be 'virtualbox' or 'libvirt'."
  }
}

variable "output_dir" {
  type        = string
  description = "Absolute path where the final .box file is written."
}

variable "iso_cache_dir" {
  type        = string
  default     = ""
  description = "Absolute path where Packer caches downloaded ISOs. Empty = Packer's default packer_cache/."
}

variable "box_version" {
  type        = string
  default     = "0.1.0"
  description = "Stamped into the Vagrant box name: socool-<vm>-<box_version>.box."
}

variable "build_parallelism" {
  type        = number
  default     = 1
  description = "How many parallel builders to run (kept at 1 for Step 5 scaffold)."
}
