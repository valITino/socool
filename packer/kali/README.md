# packer/kali/ — Kali Linux attacker VM

Builds a Vagrant box containing the latest stable Kali Linux release
with a minimum of extras — enough to host the standard attacker tool
set (`kali-linux-default`) while still fitting comfortably in a 40 GB
virtual disk.

## Inputs

| Variable | Default | Meaning |
|---|---|---|
| `hypervisor` | (required) | `virtualbox` or `libvirt` |
| `output_dir` | (required) | absolute path for the `.box` output |
| `iso_cache_dir` | `""` | ISO cache; empty = Packer's default `packer_cache/` |
| `box_version` | `0.1.0` | stamped into the box name |
| `kali_version` | `2025.3` | Kali release line on `cdimage.kali.org` |
| `cpus` | `2` | must match `config/lab.yml` `vms[kali].cpus` |
| `ram_mb` | `4096` | must match `config/lab.yml` `vms[kali].ram_mb` |
| `disk_gb` | `40` | must match `config/lab.yml` `vms[kali].disk_gb` |

## Outputs

- `<output_dir>/socool-kali-<box_version>.box` — Vagrant box consumed by `vagrant/Vagrantfile`
- `./artifacts/credentials.json` — rotated `root` + `vagrant` passwords + initial SSH host fingerprint (gitignored; mode 0600)
- `./artifacts/manifest.json` — Packer build manifest (artefact paths, timings)

## Build story

1. Packer downloads `kali-linux-<version>-installer-amd64.iso` from
   `cdimage.kali.org` and verifies the SHA256 via the publisher's
   live `SHA256SUMS` file (no literal checksum in this repo).
2. The installer is seeded via `http/preseed.cfg` served by Packer's
   built-in HTTP server on ports 8800–8899.
3. `preseed.cfg`'s `late_command` creates the `vagrant` user, a
   sudoers NOPASSWD entry, and installs the Vagrant insecure public
   key so Packer's `provisioner "shell"` can SSH in.
4. Three provisioner scripts run in order:
   - `scripts/vagrant-user.sh` — re-asserts the Vagrant account (idempotent safety).
   - `scripts/rotate-credentials.sh` — generates CSPRNG passwords for `root` + `vagrant`, writes `/tmp/socool-kali-credentials.json`.
   - `scripts/cleanup.sh` — trims apt cache, zeroes machine-id, removes SSH host keys (regenerated on first boot), and zero-fills free space so the `.box` compresses well.
5. The Packer `file` provisioner pulls the credentials manifest back
   to `./artifacts/credentials.json`. This directory is gitignored.
6. The `vagrant` post-processor packs the result as
   `<output_dir>/socool-kali-<box_version>.box` with provider
   matching `var.hypervisor`.

## Known gotchas

- **First-boot SSH host keys**: the cleanup step deliberately deletes
  them; `socool-regenerate-sshkeys.service` recreates on next boot.
  If you debug a build failure before cleanup runs, the host keys
  will still be present.
- **`kali-linux-default` is large** — ~4 GB of tools. If disk is tight
  on the build host, swap to `kali-linux-core` in `preseed.cfg`'s
  `d-i pkgsel/include` line.
- **UEFI boot** is enabled (`--firmware efi`) because the Kali
  installer's grub-installer defaults now assume EFI on modern
  releases. Switching back to BIOS requires matching changes in
  `preseed.cfg` grub-installer stanza.
- The template has **not yet been run end-to-end against a real
  hypervisor in this session**; `packer validate` should be the first
  CI gate.
