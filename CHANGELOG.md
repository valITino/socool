# Changelog

All notable changes to SOCool are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and SOCool
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Dates are ISO 8601 (UTC).

## [Unreleased]

The whole `0.1.0-dev` stream lives here until the project runs its
first successful end-to-end build on a real hypervisor. See
[README](./README.md) for current scaffold status.

### Added

- **Uninstall scripts** — `uninstall.sh` and `uninstall.ps1` at the
  repo root, plus shared phase logic under `scripts/uninstall/`.
  Default phases destroy the lab VMs (`vagrant destroy -f`), remove
  `socool-*` boxes from the local Vagrant store, uninstall the
  `vagrant-libvirt` plugin if present, and clear `.socool-cache/`,
  `packer/*/artifacts/` (rotated credentials), `packer_cache/`, and
  stray `*.box` files. `.env` removal and host-package uninstall
  (packer/vagrant/hypervisor) are opt-in via `--env` / `-EnvFile`
  and `--packages` / `-Packages` respectively, mirroring the same
  detect-and-refuse philosophy that keeps `setup.*` from
  auto-disabling Hyper-V or auto-configuring the HashiCorp apt repo.
  `--dry-run` previews every command without changes. New exit codes
  `80–86` documented in `docs/troubleshooting.md`. Parity is enforced
  by `tests/parity/check-uninstall-parity.sh`. Skills consulted:
  shell-scripting, devops, secure-coding, devsecops, documentation.

## [0.1.0-dev] — 2026-04-24

Initial scaffold of a one-command SOC lab provisioner. Every
subsystem is in place and syntactically / structurally validated;
end-to-end first build against real ISOs is the milestone's
acceptance gate.

### Added

- **Governance layer** (`CLAUDE.md`, `.skills/`) — mandatory 3-phase
  protocol, 8 specialist skill definitions, hard invariants, cross-
  platform rules.
- **Architecture foundation** — `README.md`, `config/lab.yml` schema
  v1, `.gitignore`, `.env.example`, and two ADRs:
  - ADR-0001: Packer-builds, Vagrant-runs (with alternatives
    considered and rejected)
  - ADR-0002: hypervisor matrix × host OS, Windows Hyper-V
    detect-and-refuse philosophy
- **Cross-platform entry points** — `setup.sh` + `setup.ps1` with
  identical flag surface (`--yes`, `--hypervisor`, `--scanner`,
  `--windows-source`, `--windows-iso`, `--allow-bridged`,
  `--log-level`), identical prompt catalogue (pause-for-activation
  pattern), identical exit codes. Bash 4+ gate at the top of
  `setup.sh` for macOS stock-bash 3.2 users.
- **Shared libraries** — `scripts/lib/{common,hypervisor,deps}.{sh,ps1}`
  with symmetric public ABIs across bash and PowerShell.
- **Preflight checks** — eight modular checks under
  `scripts/preflight/checks/`, each with .sh and .ps1 twins:
  - `check-os-arch` (11)
  - `check-cpu-virt` (12)
  - `check-nested-virt` (13)
  - `check-memory` (14)
  - `check-disk` (15)
  - `check-hypervisor-conflict` (16)
  - `check-tools-version` (17)
  - `check-network-cidr` (18)
  Every failure prints a one-sentence remediation sentence.
- **Packer templates** — six VMs (`pfsense`, `kali`, `windows-victim`,
  `wazuh`, `nessus`, `openvas`), each producing a Vagrant box with
  rotated credentials and verified-at-build-time publisher checksums.
  HCL2 with `required_plugins`; VirtualBox + QEMU sources on every
  template; `vagrant` post-processor output.
- **Vagrantfile** — reads `config/lab.yml`, sorts by `boot_order`,
  filters scanner VMs per `SOCOOL_SCANNER`, declares host-only
  private networks for LAN + management, leaves pfSense WAN on
  Vagrant's NAT NIC. Never bridges by default.
- **Test suite**:
  - `tests/parity/` — four-check parity of setup.sh ↔ setup.ps1
  - `tests/preflight/test-checks.sh` — docs ↔ files parity + twin
    parity + exit-code validation
  - `tests/preflight/test-mocked.sh` — unit-style tests of checks
    against fixture /proc/cpuinfo files, uname shims, version
    strings, CIDR overlaps
  - `tests/vagrant/test-vagrantfile.rb` — 10 tests, 34 assertions
  - `tests/smoke/probes/` — per-VM service probes (require live lab)
  - `tests/idempotency/`, `tests/destroy-recreate/` — post-setup
    invariant tests (require live lab)
  - `tests/run-all.sh` — master runner; cleanly skips lab-requiring
    suites when no hypervisor is up
- **Documentation** (this step):
  - `docs/runbooks/<vm>.md` for all six VMs
  - `docs/troubleshooting.md` — consolidated exit-code index +
    common failure modes
  - `docs/network-topology.md` — Mermaid diagram + firewall zones
  - `CHANGELOG.md` (this file)

### Changed

- **Windows source** `msdev` → `eval` — Microsoft's Windows developer
  VM download page has been unavailable since October 2024. The
  `eval` source downloads the Windows 11 Enterprise Evaluation ISO
  from the Microsoft Evaluation Center instead. Old `msdev` value
  now rejected with a deprecation message pointing users at `eval`
  or `iso`.
- **Apple Silicon hypervisor matrix** — VirtualBox 7.1+ now supports
  macOS aarch64 hosts, so `darwin:aarch64:virtualbox` lifted from
  hard-fail (exit 30) to a warning. QEMU remains the default for
  Apple Silicon because the lab's pfSense + Windows victim are
  x86_64 and run under slow x86 emulation under either hypervisor.
- **Hyper-V / VirtualBox coexistence** — ADR-0002 now acknowledges
  WHPX coexistence is technically possible but keeps the detect-and-
  refuse policy on reliability + performance grounds.
- **HashiCorp repo** — `deps.sh` refusal message now prints the
  exact apt/dnf install commands pulled from the official
  `apt.releases.hashicorp.com` / `rpm.releases.hashicorp.com` docs.

### Fixed

- `scripts/preflight/checks/check-cpu-virt.sh` and `check-memory.sh`
  used `local` outside any function body (inside a case arm),
  which fails at runtime on some bash builds. Removed; caught by
  the new `tests/preflight/test-mocked.sh`.
- `scripts/preflight/run-all.sh` used `if ! bash ...; then rc=$?;`
  which always recorded `rc=0` because `$?` inside the `then` block
  of a negated `if` is the negation's result. Replaced with
  `rc=0; bash ... || rc=$?` so failed checks report their real
  documented exit code.
- `tests/parity/check-parity.sh` rewritten to use `.env.example` as
  the canonical env-var list (with a `# reserved-for: step-N` skip
  marker) instead of grepping every `SOCOOL_*` identifier in either
  script, which was flagging internal bash locals as drift.

### Known limitations

- None of the six Packer templates have been run end-to-end against
  a real hypervisor in this session (no VT-x and insufficient disk
  in the sandbox). Templates are syntactically reviewed and
  structurally consistent; first-build tuning is expected in a real
  environment.
- Default gateway on non-pfSense VMs is the NAT NIC, not pfSense.
  This bypasses pfSense for Internet egress — fine for port/service
  testing, less realistic for attack-flow studies. Fix is a per-VM
  Packer provisioner tweak.
- Distro-specific HashiCorp apt/dnf repo setup is not automated
  (intentional; `devsecops` declines to silently write a new GPG
  key + sources file). Users on Ubuntu/Debian/Fedora follow the
  printed instructions once.

---

[Unreleased]: https://github.com/valITino/socool/compare/v0.1.0-dev...HEAD
[0.1.0-dev]: https://github.com/valITino/socool/releases/tag/v0.1.0-dev
