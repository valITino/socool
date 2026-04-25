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
variable "greenbone_compose_url" {
  type    = string
  # Greenbone Community Containers' published compose file. The URL
  # is stable across releases; the images it references are tagged
  # with a major version. Verified 2026-04-24.
  default = "https://greenbone.github.io/docs/latest/_static/docker-compose-22.4.yml"
  description = "Upstream docker-compose manifest for Greenbone Community Containers."
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