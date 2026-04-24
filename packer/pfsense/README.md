# packer/pfsense/ — pfSense CE 2.7.2 firewall VM

Builds a Vagrant box containing pfSense CE 2.7.2 (the last release
Netgate ships as a standalone ISO — 2.8.0+ is network-installer only).
Three virtio NICs map to `wan-sim` / `lan` / `management` per
`config/lab.yml`. webConfigurator bound to the `management` interface
only. Build-only credentials rotated during provisioning.

## Inputs

| Variable | Default | Meaning |
|---|---|---|
| `hypervisor` | (required) | `virtualbox` or `libvirt` |
| `output_dir` | (required) | where the `.box` is written |
| `iso_cache_dir` | `""` | ISO cache |
| `box_version` | `0.1.0` | stamped into box name |
| `pfsense_version` | `2.7.2` | Netgate release line |
| `cpus` | `1` | matches `lab.yml` |
| `ram_mb` | `1024` | matches `lab.yml` |
| `disk_gb` | `8` | matches `lab.yml` |

## Outputs

- `<output_dir>/socool-pfsense-<box_version>.box`
- `./artifacts/credentials.json` — rotated `root` + `admin` passwords
- `./artifacts/manifest.json`

## Build story

1. Packer downloads `pfSense-CE-2.7.2-RELEASE-amd64.iso.gz` from
   `atxfiles.netgate.com`, verifies SHA256 via the publisher's live
   `.sha256` file.
2. Packer boots the ISO. The `boot_command` stanza:
   - accepts the boot menu default
   - enters `bsdinstall` (the FreeBSD installer)
   - drops to a shell inside bsdinstall
   - `fetch`es `http/installerconfig` from Packer's HTTP server
   - exits the shell so bsdinstall resumes with `/tmp/installerconfig` as its script
3. `installerconfig` partitions the disk, installs the base system,
   enables `sshd`, drops `/cf/conf/config.xml` (seeded from
   `http/config-seed.xml`), and configures the three NICs.
4. The VM reboots. pfSense starts up, applies the seeded config,
   enables SSH on the WAN (NAT) interface for Packer's provisioner.
5. `scripts/post-install.sh` trims caches and log files.
6. `scripts/rotate-credentials.sh` generates CSPRNG passwords for
   `root` (SSH + console) and `admin` (webConfigurator), updates
   `/cf/conf/config.xml` via pfSense's PHP helper, and writes
   `/tmp/socool-pfsense-credentials.json`.
7. Packer's `file` provisioner pulls the manifest back to
   `./artifacts/credentials.json`.
8. The `vagrant` post-processor packs the `.box`.

## Known gotchas

- **`boot_command` timing is the hardest part.** bsdinstall's menu
  flow has shifted between pfSense releases; the sequence in
  `template.pkr.hcl` matches 2.7.2 as tested against Netgate's
  2.7.2 ISO. Running against a newer ISO will likely require
  re-recording the key sequence.
- **The shipped `config-seed.xml`** includes a BUILD-ONLY admin
  hash. `rotate-credentials.sh` overwrites it. Sanity-check after
  each build that the hash in the shipped box is NOT the literal
  `$2y$10$BUILDONLY...` placeholder.
- **pfSense 2.8+ has no standalone ISO.** If you need 2.8, expect
  a separate ADR documenting the network-installer path (currently
  out of scope; tracked as a later milestone).
- **Three NICs at build time** require matching internal networks
  on the host. The Vagrantfile (Step 6) wires VM 2/3 to the
  `socool-lan` / `socool-management` internal networks; for an
  ad-hoc Packer run outside of SOCool orchestration, pre-create
  these networks with `VBoxManage` or `virsh net-define` first.
- **Not yet run end-to-end** in this session; `packer validate`
  and a first build-iteration to tune `boot_command` timings are
  expected.

## References

- [pfSense Installation Walkthrough](https://docs.netgate.com/pfsense/en/latest/install/install-walkthrough.html)
- [pfSense XML Configuration File](https://docs.netgate.com/pfsense/en/latest/config/xml-configuration-file.html)
- [bsdinstall(8) SCRIPTING section](https://man.freebsd.org/cgi/man.cgi?bsdinstall(8))
- [Netgate atxfiles mirror](https://atxfiles.netgate.com/mirror/downloads/)
