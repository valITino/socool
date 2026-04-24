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
}
# User supplies these — Tenable download is session-gated; activation
# code is emailed on sign-up at tenable.com/products/nessus/nessus-essentials.
variable "nessus_deb_url" {
  type        = string
  description = "URL (or file://) to the Nessus-*-debian10_amd64.deb. Tenable download is session-gated; user supplies."
}

variable "nessus_activation_code" {
  type        = string
  description = "One-time Nessus Essentials activation code (emailed by Tenable). Required for -a builds."
  sensitive   = true
}

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
  default = 40
}