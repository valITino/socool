# packer/

This directory holds one subdirectory per VM that `setup.*` provisions.
Packer builds each subdirectory's template into a Vagrant box (`.box`
file) that `vagrant/Vagrantfile` consumes. Packer-builds-boxes,
Vagrant-runs-the-lab per
[ADR-0001](../docs/adr/0001-packer-plus-vagrant.md).

## Tree

```
packer/
├── shared/               # packer{} block + common variable types, included
│                         #   by every template. Not a builder itself.
├── pfsense/              # pfSense CE 2.7.2 — last ISO-installable release
├── kali/                 # Kali Linux rolling (2025.3+) via Debian preseed
├── windows-victim/       # Windows 11 Enterprise Eval via autounattend.xml
├── wazuh/                # Ubuntu 24.04 + wazuh-install.sh -a (all-in-one)
├── nessus/               # Ubuntu 24.04 + Nessus Essentials .deb (optional)
└── openvas/              # Ubuntu 24.04 + Greenbone Community Containers (optional)
```

## Per-VM contract

Every template:

1. Declares `source "virtualbox-iso" "vm"` **and** `source "qemu" "vm"`.
   `setup.*` drives the chosen one via `packer build -only=<name>.<source>.vm`.
2. Accepts these common variables (see `shared/variables.pkr.hcl.tpl`):
   - `hypervisor`           — `virtualbox` | `libvirt`
   - `output_dir`           — where to write the `.box`
   - `iso_cache_dir`        — where to cache downloaded ISOs
   - `box_version`          — stamped into box name and metadata
3. Uses `iso_checksum = "file:<publisher-URL>.sha256"` so Packer
   fetches the **live** checksum from the publisher at build time —
   never a literal pasted into the repo. See `.skills/devsecops/SKILL.md`.
4. Rotates the upstream default password during provisioning with a
   CSPRNG (`openssl rand -base64 32`), then emits
   `packer/<vm>/artifacts/credentials.json` (mode 0600, gitignored).
5. Emits one `.box` file named `socool-<vm>-<box_version>.box` into
   `output_dir`.

## Build order

Per `config/lab.yml`'s `boot_order` (pfsense → kali → windows-victim →
wazuh → scanner). `scripts/provision/run-pipeline.*` walks that order.

## Known limitations (scaffold status)

The templates in this tree are **scaffold-complete** as of 2026-04-24:
HCL2 syntax reviewed, unattended-install files verified against
upstream references, credential-rotation paths connected end-to-end.
They have **not** yet been run end-to-end against real ISOs in this
session (no hypervisor + insufficient disk). First-build validation
and per-VM tuning are part of each VM's milestone acceptance.

Known items that require real-environment validation before shipping a
Vagrant box:

- pfSense `installerconfig` + `config.xml` seed — boot-time ordering
  on FreeBSD is finicky; see `pfsense/README.md`.
- Windows 11 `autounattend.xml` — Evaluation Center image edition
  naming varies per download; see `windows-victim/README.md`.
- Ubuntu 24.04 Subiquity `autoinstall` — Subiquity's ordering of
  early-commands vs late-commands has changed between 20.04 and 24.04;
  the template uses the 24.04 layout (verified 2026-04-24).
- Nessus `.deb` URL is session-gated behind a Tenable redirect;
  `nessus/README.md` documents the env vars that plug the gap.
- Greenbone Community Containers — the upstream
  `docker-compose.yml` URL moves between Greenbone releases; the
  template pins a specific tag.

## Local overrides

Per-user `*.pkrvars.hcl` files are gitignored. Example:

```hcl
# packer/wazuh/my.pkrvars.hcl  (NOT committed)
wazuh_indexer_heap = "4G"
```

Run with `packer build -var-file=my.pkrvars.hcl ...`.
