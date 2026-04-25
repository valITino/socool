# ADR-0001: Use Packer to build boxes and Vagrant to run the lab

- **Status:** Accepted
- **Date:** 2026-04-24
- **Last verified:** 2026-04-24 (Phase 1 web research)
- **Deciders:** SOCool maintainers (authored via the `software-architect` and `documentation` skills)

## Context

SOCool provisions a multi-VM SOC lab on a developer's laptop or a CI runner.
The project has to solve two distinct problems:

1. **Image building.** Turning an upstream ISO (pfSense, Windows dev eval,
   Debian-family for Kali/Wazuh) into a hypervisor-ready VM image with
   credentials rotated, base packages installed, and the guest configured for
   unattended provisioning.
2. **Lab orchestration.** Spinning up four or five of those images as a
   networked cluster, wiring them into three isolated subnets, running
   per-VM provisioners in dependency order, and supporting clean
   destroy/recreate cycles.

These are different workloads on different timescales. Image building is
slow (tens of minutes, rare) and reproducibility-critical. Lab orchestration
is frequent (minutes, every time a user or test runs the lab) and must be
idempotent across re-runs.

The `software-engineer` skill's "Packer builds boxes, Vagrant runs the lab.
Don't blur the line." rule is the operational expression of this ADR.

## Decision

Use **[HashiCorp Packer](https://developer.hashicorp.com/packer/docs) with
the HCL2 syntax** for image builds, producing Vagrant box artefacts
(`.box` files) per VM per provider.

Use **[HashiCorp Vagrant](https://developer.hashicorp.com/vagrant/docs)**
with its native `virtualbox` and `libvirt` providers to instantiate the lab
from those boxes, with a single `vagrant/Vagrantfile` that reads
`config/lab.yml`.

Explicit division of responsibility:

| Concern | Owned by | Not by |
|---|---|---|
| ISO download + checksum | Packer | Vagrant |
| Unattended install (autounattend / preseed / pfSense config.xml) | Packer | Vagrant |
| Base-package install, guest-additions, CVE patches | Packer | Vagrant |
| Default-credential rotation | Packer | Vagrant |
| Final box artefact (`socool-<vm>-<version>.box`) | Packer | Vagrant |
| VM lifecycle (`up`/`halt`/`destroy`/`reload`) | Vagrant | Packer |
| Network wiring (host-only, internal, provider NAT) | Vagrant | Packer |
| Inter-VM boot order and `depends_on` | Vagrant | Packer |
| Lab-scenario-specific provisioning (e.g., Wazuh agent enrollment) | Vagrant | Packer |

## Consequences

### Positive

- Each concern has exactly one owner, reducing where bugs can hide.
- Boxes are cacheable artefacts — a developer or CI runner can pull a
  pre-built box instead of re-running the 20-minute Packer pipeline.
- Both tools natively target VirtualBox and libvirt/QEMU, satisfying the
  cross-platform requirement from [ADR-0002](./0002-hypervisor-matrix.md).
- HCL2 variables let us thread `config/lab.yml` values through without
  hardcoding.
- Vagrant's `config.vm.provider` blocks let us express per-provider tweaks
  (NIC type, storage pool) cleanly.

### Negative

- Two tools to install, version-pin, and keep preflight checks for (see
  `scripts/preflight/`). This is acceptable — both are mature, both are
  packaged by the major OS package managers we target.
- HashiCorp's licence change (BSL 1.1 for Vagrant ≥ 2.4 and Packer ≥
  1.10 as of mid-2023) is a supply-chain consideration. IBM completed
  its acquisition of HashiCorp in February 2025; the BSL terms were
  not changed by the acquisition (re-verified 2026-04-24). For our
  use case (developer / CI internal tool) the BSL allows use; we flag
  this for `devsecops` re-verification each release.
- A new contributor has to understand *both* the Packer and Vagrant
  mental models. Mitigated by the per-VM `README.md` in every
  `packer/<vm>/` directory and the runbooks in `docs/runbooks/`.

### Mitigations

- Every Packer template has a `README.md` documenting inputs, outputs,
  gotchas.
- `tests/idempotency/` asserts Packer does not rebuild on a second run if
  the inputs are unchanged.
- `tests/destroy-recreate/` asserts Vagrant can tear down and bring up the
  lab cleanly.

## Alternatives considered

### A. Ansible driving `virt-install` / `VBoxManage` directly

- **Pro:** one tool, declarative, large ecosystem.
- **Con:** no first-class concept of "a reusable box artefact" — every
  lab run would re-install from ISO (slow, network-dependent) or we'd
  reinvent Packer's caching.
- **Con:** cross-platform story on Windows is weak (Ansible control node
  must be Linux/macOS in practice).
- **Rejected** because we lose artefact caching and cross-platform parity.

### B. Terraform + cloud-init (repurposed for local hypervisors)

- **Pro:** modern, declarative, large community.
- **Con:** Terraform's local-hypervisor providers (`terraform-provider-libvirt`,
  community VirtualBox providers) are third-party, less actively maintained,
  and carry supply-chain risk the `devsecops` skill would reject.
- **Con:** no clean equivalent of a Vagrant box artefact for local
  hypervisors.
- **Rejected** on supply-chain and maturity grounds.

### C. Raw shell scripts driving `VBoxManage` / `virsh` / `qemu-img`

- **Pro:** no extra dependencies.
- **Con:** we'd rebuild Vagrant's lifecycle logic and Packer's unattended-
  install abstraction from scratch. Hundreds of lines of brittle shell,
  duplicated across `setup.sh` and `setup.ps1`.
- **Con:** maintenance burden compounds every time an upstream ISO's boot
  sequence changes.
- **Rejected** on maintenance cost.

### D. Containers (Docker / Podman) instead of VMs

- **Pro:** faster, lighter, cross-platform.
- **Con:** pfSense, Windows, and a realistic Wazuh deployment are not
  container workloads. The whole point of the lab is kernel-level network
  isolation between a real router, real attacker/victim OSes, and a real
  SIEM. Containers can't simulate that without nesting a VM inside anyway.
- **Rejected** on fit-for-purpose grounds.

## References

- HashiCorp Packer documentation: https://developer.hashicorp.com/packer/docs
- HashiCorp Vagrant documentation: https://developer.hashicorp.com/vagrant/docs
- HashiCorp Business Source Licence announcement (2023):
  https://www.hashicorp.com/blog/hashicorp-adopts-business-source-license
  (re-verify current terms per Phase 1 protocol at each release)
- `.skills/software-engineer/SKILL.md` (implementation rules)
- `.skills/software-architect/SKILL.md` (repo layout)
- `.skills/devsecops/SKILL.md` (supply-chain rules)
