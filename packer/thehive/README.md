# packer/thehive/ — TheHive 5 Community Edition

Builds a Vagrant box of Ubuntu 24.04 LTS hosting TheHive 5
Community via [StrangeBee's official `prod1-thehive` Docker
Compose profile](https://github.com/StrangeBeeCorp/docker) —
Cassandra + Elasticsearch + TheHive + Nginx, all on one VM.

Pinned to TheHive `5.7.1` (latest 5.x verified 2026-04-27) with
matching pinned tags for Cassandra `4.1.10`, Elasticsearch
`8.19.11`, and Nginx `1.29.5`.

## Inputs

| Variable | Default | Meaning |
|---|---|---|
| `hypervisor` | (required) | `virtualbox` or `libvirt` |
| `output_dir` | (required) | where the `.box` is written |
| `iso_cache_dir` | `""` | ISO cache |
| `box_version` | `0.1.0` | stamped into box name |
| `ubuntu_release` | `24.04.1` | Ubuntu Server LTS point release |
| `strangebee_docker_ref` | `main` | git ref of `StrangeBeeCorp/docker` |
| `thehive_image_version` | `5.7.1` | `strangebee/thehive` image tag |
| `cassandra_image_version` | `4.1.10` | `cassandra` image tag |
| `elasticsearch_image_version` | `8.19.11` | `elasticsearch` image tag |
| `nginx_image_version` | `1.29.5` | `nginx` image tag |
| `cassandra_heap_mb` | `1024` | Cassandra `MAX_HEAP_SIZE` (capped from upstream 3 GB) |
| `elasticsearch_heap_mb` | `1024` | Elasticsearch `Xms/Xmx` (capped from 3 GB) |
| `thehive_heap_mb` | `1024` | TheHive JVM heap (capped from 3 GB) |
| `cpus` | `4` | matches `lab.yml` |
| `ram_mb` | `8192` | matches `lab.yml` |
| `disk_gb` | `60` | matches `lab.yml` |

## Outputs

- `<output_dir>/socool-thehive-<box_version>.box`
- `./artifacts/credentials.json` — rotated `vagrant` (SSH) and
  `admin@thehive.local` (web UI). The TheHive admin rotation is
  staged under `/etc/socool/thehive-admin.env` and applied by
  `socool-thehive-firstboot.service` on first `vagrant up` once
  TheHive's API is reachable.
- `./artifacts/manifest.json`

## Build story

1. Packer downloads the Ubuntu 24.04 Live Server ISO, verifies via
   the publisher's `SHA256SUMS`.
2. Boots the ISO with Subiquity autoinstall (`ds=nocloud-net;…`),
   reading `user-data` + `meta-data` from Packer's HTTP server.
3. Subiquity runs unattended — LVM root, vagrant user with
   BUILD-ONLY password, SSH enabled, insecure Vagrant key
   authorized.
4. Post-install provisioners run as root:
   - `vagrant-user.sh` — re-assert sudoers + SSH config.
   - `install-thehive.sh` — install Docker Engine + Compose plugin
     from the official Docker apt repo, apply the
     `vm.max_map_count=262144` sysctl Elasticsearch needs, clone
     `StrangeBeeCorp/docker` at the pinned ref, copy its
     `prod1-thehive/` profile to `/opt/thehive/`, pin every image
     tag in `versions.env`, run StrangeBee's `init.sh` (generates
     self-signed certs + `secret.conf` + `.env`), append heap
     overrides to `.env`, pre-pull all images, and install
     `socool-thehive.service` to bring the stack up at boot.
   - `rotate-credentials.sh` — generate CSPRNG passwords for
     `vagrant` and `admin@thehive.local`, stage the latter under
     `/etc/socool/thehive-admin.env`, install
     `socool-thehive-firstboot.service` to apply it via the
     TheHive REST API on first boot.
   - `cleanup.sh` — trim apt cache, drop the StrangeBee clone,
     scrub machine-id + SSH host keys (regenerated on first boot),
     zero free space.
5. Packer pulls `credentials.json`; `vagrant` post-processor packs.

## Known gotchas

- **First boot is slow.** Cassandra has to initialise its commit
  log + system keyspaces before TheHive will start; expect ~3
  minutes after `vagrant up` before the web UI responds. The
  `socool-thehive-firstboot.service` unit polls `/api/v1/status`
  for up to 10 minutes before giving up.
- **Community license required for write access.** TheHive 5.3+
  runs read-only without an active Community license. The
  license is free but requires a one-time signup on
  [strangebee.com/community](https://strangebee.com/community/).
  Apply under *Settings → License* after first login. The Packer
  build deliberately does not bake a license in — licenses are
  per-deployment and are not redistributable.
- **Heap caps are aggressive.** StrangeBee's defaults (3 GB for
  each of Cassandra / Elasticsearch / TheHive) assume a 16 GB
  host. We override to 1 GB each so the stack fits in this VM's
  8 GB budget. Single-analyst Community workloads run fine at
  this cap; bump `cassandra_heap_mb` / `elasticsearch_heap_mb`
  / `thehive_heap_mb` in `variables.pkr.hcl` if you raise the
  VM's RAM in `config/lab.yml`.
- **`vm.max_map_count`.** Elasticsearch refuses to start without
  this kernel tunable raised to 262144. We persist it via
  `/etc/sysctl.d/99-thehive.conf`.
- **Self-signed cert on the Nginx fronting TheHive.** Browsers
  warn on first connection. Replace `./certificates/server.crt`
  + `server.key` inside `/opt/thehive/` and restart the stack to
  use your own certificate.
- **StrangeBee `init.sh` may prompt interactively.** We pass
  `SERVER_NAME='thehive.socool.lab'` and pipe `</dev/null` so any
  remaining prompts default-out; if `init.sh` fails the script
  falls back to writing empty `secret.conf` / `index.conf` stubs
  so the stack still starts. Re-run `init.sh` by hand from the
  runbook if cert generation didn't complete cleanly.
- **Image is large** — the four pre-pulled images sum to roughly
  2 GB on disk, plus Cassandra's commit log + Elasticsearch's
  indices grow with case data. The shipped box is ~3 GB after
  compression.
- **Not yet validated E2E** in this session; first build
  iteration needed to tune the Subiquity boot timings and confirm
  StrangeBee's `init.sh` runs unattended on Ubuntu 24.04.

## References

- [TheHive 5 Docker installation](https://docs.strangebee.com/thehive/installation/docker/)
- [StrangeBeeCorp/docker — prod1-thehive profile](https://github.com/StrangeBeeCorp/docker)
- [Docker Hub — strangebee/thehive](https://hub.docker.com/r/strangebee/thehive)
- [Community license terms](https://docs.strangebee.com/thehive/installation/licenses/about-licenses/)
- [TheHive 5 Community license request portal](https://strangebee.com/community/)
- [TheHive REST API — User: set password](https://docs.strangebee.com/thehive/api-docs/)
- [Subiquity autoinstall reference](https://canonical-subiquity.readthedocs-hosted.com/en/latest/reference/autoinstall-reference.html)
