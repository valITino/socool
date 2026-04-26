# SOCool

A one-command SOC lab provisioner. Clone, run `setup.sh` (Linux/macOS) or
`setup.ps1` (Windows), and you end up with a networked lab of Kali, pfSense, a
Windows victim, Wazuh (SIEM), and optionally Nessus or OpenVAS (vulnerability
scanner) running on VirtualBox or QEMU/KVM.

> Status: early development. The repo layout, governance model, and initial
> configuration are in place; provisioning pipelines land in later milestones.
> See [`CHANGELOG.md`](./CHANGELOG.md) for what ships when.

## Components

| VM | Role | Image source | Network |
|---|---|---|---|
| `pfsense` | Firewall / router between `wan-sim`, `lan`, `management` | Netgate official ISO | all three |
| `kali` | Attacker workstation | Offensive Security official Vagrant box / ISO | `lan` |
| `windows-victim` | Target endpoint with Wazuh agent | Microsoft Windows dev eval VM | `lan` |
| `wazuh` | All-in-one SIEM (manager + indexer + dashboard) | Wazuh official RPM/DEB repos | `management` |
| `nessus` / `openvas` | Vulnerability scanner (optional; pick one or skip) | Tenable or Greenbone official | `management` |

Full component runbooks land under [`docs/runbooks/`](./docs/runbooks/) in a
later milestone.

## Quickstart

```bash
# Linux / macOS
git clone https://github.com/valITino/socool.git
cd socool
./setup.sh

# Windows (PowerShell 7+)
git clone https://github.com/valITino/socool.git
cd socool
./setup.ps1
```

Both scripts run preflight checks, install missing dependencies through your
native package manager (`apt` / `dnf` / `pacman` / `brew` / `winget` / `choco`),
resolve the hypervisor, and drive the per-VM provisioning pipeline. Every
prompt has an environment-variable equivalent for non-interactive CI use; see
[`.env.example`](./.env.example).

## Uninstall

Tear the lab down and reclaim disk space with the matching uninstall scripts:

```bash
# Linux / macOS
./uninstall.sh             # default: VMs + boxes + caches
./uninstall.sh --dry-run   # preview only
./uninstall.sh --all --yes # also remove .env and host packages

# Windows (PowerShell 7+)
./uninstall.ps1
./uninstall.ps1 -DryRun
./uninstall.ps1 -All -Yes
```

Default uninstall leaves your `.env` and host packages (packer, vagrant,
hypervisor) alone — they're commonly used by other projects. Pass `--env` /
`-EnvFile` and `--packages` / `-Packages` to opt in. The script never deletes
the repo directory itself; it prints the `rm -rf` line at the end. See
[`scripts/uninstall/README.md`](./scripts/uninstall/README.md) for the full
phase list, safety rules, and exit codes.

## Requirements

| Resource | Minimum (base lab, no scanner) | With scanner | Recommended |
|---|---|---|---|
| CPU | 4 physical cores with VT-x / AMD-V | 4 cores | 8 cores |
| RAM free | 22 GB (17 GB VMs + 4 GB host headroom + margin) | 26 GB | 32 GB |
| Disk free | 190 GB (168 GB VMs + 20 GB headroom) | 230 GB | 500 GB SSD |
| Nested virt | — | required | — |
| Host OS | Linux (x86_64, aarch64), macOS (Intel, Apple Silicon), Windows 10/11 (x86_64) | same | Linux x86_64 |

The minimum-RAM/disk figures are what `scripts/preflight/check-memory.sh`
and `check-disk.sh` actually enforce. Actual per-VM sizing lives in
[`config/lab.yml`](./config/lab.yml).

## Hypervisor matrix

| Host | Primary | Fallback | Hard-blocked by |
|---|---|---|---|
| Linux x86_64 | VirtualBox | QEMU/KVM | — |
| Linux aarch64 | QEMU/KVM | — | VirtualBox (no aarch64 Linux host) |
| macOS Intel | VirtualBox | QEMU | — |
| macOS Apple Silicon | QEMU / UTM | VirtualBox 7.2+ (with caveats) | — |
| Windows x86_64 | VirtualBox | — | Hyper-V / WSL2 / Docker Desktop |
| Windows aarch64 | *unsupported* | — | — |

See [ADR-0002](./docs/adr/0002-hypervisor-matrix.md) for rationale,
remediation paths, and the Apple Silicon caveats (VirtualBox 7.1+
supports the host, but the lab's x86 guests run under slow x86
emulation either way and 7.2.4 has a known Windows-guest crash).

## Lab topology

Three isolated networks, host-only or internal — **never bridged to your LAN
by default**.

```
  [host]
    │
    ├── wan-sim  (198.18.0.0/24)   ── pfSense WAN
    ├── lan      (10.42.10.0/24)   ── pfSense LAN  ─┬── kali
    │                                               └── windows-victim
    └── management (10.42.20.0/24) ── pfSense MGMT ─┬── wazuh
                                                    └── nessus / openvas
```

Bridged networking requires `SOCOOL_ALLOW_BRIDGED=1` plus an explicit
confirmation prompt and warning. Topology diagram and firewall rules land in
[`docs/network-topology.md`](./docs/network-topology.md).

## Troubleshooting

Each preflight check and runtime failure mode exits with a documented code;
the full table lives in [`docs/troubleshooting.md`](./docs/troubleshooting.md).
Ranges:

| Range | Meaning |
|---|---|
| 10–19 | preflight |
| 20–29 | dependency install |
| 30–39 | hypervisor / network conflict |
| 40–49 | Packer build |
| 50–59 | Vagrant lifecycle |
| 60–63 | credential / secret handling |
| 64 | non-interactive run, required env var missing |
| 70–79 | smoke test |

## Contributing

Every change follows the protocol in [`CLAUDE.md`](./CLAUDE.md) and consults
the relevant skill files under [`.skills/`](./.skills/). Commit messages name
the skills consulted: `subsystem: change (skills: devops, devsecops)`.

## License

TBD — to be decided before `0.1.0` ships.
