# packer/openvas/ — Greenbone Community Edition (OpenVAS) scanner

Builds a Vagrant box of Ubuntu 24.04 LTS with Greenbone Community
Containers pre-pulled. On first `vagrant up`, the containers start,
and a first-boot unit applies the rotated Greenbone admin password.

Building from source (the "traditional" OpenVAS path) is avoided —
half-a-dozen components (Redis, Postgres, openvasd, gvmd,
gsa + gsad, notus-scanner replacement) would add hours to the build
for no benefit at lab scale.

## Inputs

| Variable | Default | Meaning |
|---|---|---|
| `hypervisor` | (required) | `virtualbox` or `libvirt` |
| `output_dir` | (required) | where the `.box` is written |
| `iso_cache_dir` | `""` | ISO cache |
| `box_version` | `0.1.0` | stamped into box name |
| `ubuntu_release` | `24.04.1` | |
| `greenbone_compose_url` | `https://greenbone.github.io/docs/latest/_static/docker-compose-22.4.yml` | upstream compose manifest |
| `cpus` / `ram_mb` / `disk_gb` | `2 / 4096 / 40` | matches `lab.yml` |

## Outputs

- `<output_dir>/socool-openvas-<box_version>.box`
- `./artifacts/credentials.json` — rotated vagrant + pending Greenbone admin
- `./artifacts/manifest.json`

## Build story

1. Ubuntu 24.04 autoinstall (same template shape as wazuh/, nessus/).
2. `install-greenbone.sh` — installs Docker CE from Docker's official
   apt repo (explicit user-level repo setup, not a third-party
   script), fetches Greenbone's compose manifest, pre-pulls all
   images (~2 GB) so first boot is quick. Writes a systemd unit
   `socool-greenbone.service` that `docker compose up -d`s the stack
   on boot.
3. `rotate-credentials.sh` — stages the CSPRNG-generated admin
   password in `/etc/socool/greenbone-admin.env` and writes a
   `socool-greenbone-firstboot.service` unit that applies it via
   `gvmd --new-password` after the stack is up. The unit creates
   `/var/lib/socool/greenbone-firstboot.done` so it only runs once.
4. `cleanup.sh` — standard shrink.

## Known gotchas

- **Feed sync at first boot is slow** — Greenbone pulls ~3 GB of
  NVT feeds on first run; the UI is responsive after ~5 minutes
  but scan coverage grows for 30–90 minutes.
- **Compose URL pins a major version** (`22.4`). Newer major Greenbone
  releases change service names and the `gvmd --new-password`
  invocation; re-verify the compose file + CLI syntax when bumping.
- **docker-compose-v2 plugin** (installed via `docker-compose-plugin`)
  is used — NOT the legacy standalone `docker-compose` binary.
  Invocation is `docker compose` (space), not `docker-compose` (dash).
- **First-boot unit failure mode**: if `gvmd --create-user` fails
  because the user already exists, the unit falls through to
  `--new-password`. Either way, `greenbone-firstboot.done` is
  touched only on success, so re-runs are safe.
- **Not validated E2E** in this session — requires a host that can
  pull 2 GB of docker images to fully rehearse.

## References

- [Greenbone Community Documentation](https://greenbone.github.io/docs/latest/)
- [Greenbone Community Containers](https://greenbone.github.io/docs/latest/22.4/container/index.html)
- [gvmd user administration](https://greenbone.github.io/docs/latest/22.4/troubleshooting/user-password-reset.html)
