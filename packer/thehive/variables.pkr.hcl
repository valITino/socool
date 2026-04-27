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
variable "ubuntu_release" {
  type        = string
  default     = "24.04.1"
  description = "Ubuntu Server LTS point release (e.g., '24.04.1')."
}

# StrangeBee publishes the official Compose profiles under
# https://github.com/StrangeBeeCorp/docker. The 'main' branch carries
# the up-to-date prod1-thehive profile (Cassandra + Elasticsearch +
# TheHive + Nginx). We pin to a tag-less main reference and a
# pinned commit SHA so the build is reproducible-ish; bump the SHA
# when the upstream profile changes. Verified 2026-04-27.
variable "strangebee_docker_ref" {
  type        = string
  default     = "main"
  description = "Git ref (branch, tag, or commit SHA) of StrangeBeeCorp/docker to clone for the prod1-thehive Compose profile."
}

# Image versions. These mirror StrangeBee's own versions.env at the
# pinned ref above. Re-stating them here lets us pull-only the exact
# tags we need before the build VM goes offline, instead of relying
# on the upstream env file at run time.
variable "thehive_image_version" {
  type        = string
  default     = "5.7.1"
  description = "strangebee/thehive image tag (5.x latest as of 2026-04-27)."
}
variable "cassandra_image_version" {
  type    = string
  default = "4.1.10"
}
variable "elasticsearch_image_version" {
  type    = string
  default = "8.19.11"
}
variable "nginx_image_version" {
  type    = string
  default = "1.29.5"
}

# Per-component JVM heap sizes, in megabytes. StrangeBee's defaults
# are 3G/3G/3G which only fits a host with 16+ GB RAM dedicated to
# the stack. The lab budget is 8 GB total for this VM, so we cap
# each at 1G — TheHive's Community workload is single-analyst and
# does not need the production heap.
variable "cassandra_heap_mb" {
  type    = number
  default = 1024
}
variable "elasticsearch_heap_mb" {
  type    = number
  default = 1024
}
variable "thehive_heap_mb" {
  type    = number
  default = 1024
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
