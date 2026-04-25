# ADR-0002: Hypervisor matrix and Windows Hyper-V conflict handling

- **Status:** Accepted
- **Date:** 2026-04-24
- **Last verified:** 2026-04-24 (Phase 1 web research)
- **Deciders:** SOCool maintainers (authored via the `devops`, `devsecops`, and `software-architect` skills)

> **Phase 1 freshness notice.** The external compatibility claims in this
> ADR are accurate at the "Last verified" date above. Hypervisor support
> changes frequently — Apple Silicon VirtualBox status, Hyper-V +
> VirtualBox interaction on Windows 11, and nested-virt availability on
> Linux kernels all evolve. Re-verify this table at every release per
> `CLAUDE.md`'s Phase 1 protocol.

## Context

SOCool must run on Linux, macOS, and Windows hosts, across both x86_64 and
aarch64 architectures. The two hypervisors we target — Oracle VirtualBox and
QEMU/KVM (via libvirt) — have very different platform support, and on
Windows both suffer hard conflicts with Hyper-V, WSL2 (when backed by
Hyper-V), and Docker Desktop (when using the WSL2 backend).

We cannot silently fall back from one hypervisor to another. A user whose
mental model is "I have VirtualBox installed" and who ends up with a lab
running on QEMU will be surprised the first time `VBoxManage` in their
muscle memory doesn't find the VMs.

Equally, we cannot silently disable Hyper-V on a Windows user's machine —
that breaks their other tooling (WSL2, Docker Desktop, Windows Sandbox,
Hyper-V-accelerated Android emulators).

The decision is: what does SOCool support, what does it refuse to support,
and how does it communicate the reasons?

## Decision

### The matrix

| Host OS | Arch | Primary | Fallback | Hard-blocked by |
|---|---|---|---|---|
| Linux | x86_64 | VirtualBox | QEMU/KVM (libvirt) | — |
| Linux | aarch64 | QEMU/KVM (libvirt) | — | VirtualBox (no aarch64 Linux host support) |
| macOS | x86_64 (Intel) | VirtualBox | QEMU | — |
| macOS | aarch64 (Apple Silicon) | QEMU / UTM | VirtualBox 7.2+ (caveats below) | — |
| Windows | x86_64 | VirtualBox | — | Hyper-V enabled, WSL2 using Hyper-V backend, Docker Desktop on WSL2 |
| Windows | aarch64 | *unsupported* | — | — |

This table is duplicated in `.skills/devops/SKILL.md` and `README.md`; all
three must move together when it changes.

**Apple Silicon note (2026-04-24 verification):** VirtualBox 7.1 added
macOS aarch64 host support and 7.2 (current 7.2.8) continues it, so
Apple Silicon is no longer hard-blocked by lack of host support. We
still prefer QEMU on Apple Silicon because:

1. The lab's pfSense and Windows-victim guests are x86_64 — VirtualBox
   on Apple Silicon runs those under x86 emulation with significant
   performance cost.
2. VirtualBox 7.2.4 has been reported to crash Windows 11 guests at
   startup on several host configurations; workarounds exist (switch
   the VM's paravirtualization setting from Hyper-V to Legacy) but the
   bug is a reliability concern for an unattended provisioner.
3. QEMU has been stable on Apple Silicon for years and handles the
   same x86 guests via TCG. Slower than native, but predictable.

If a user sets `SOCOOL_HYPERVISOR=virtualbox` on Apple Silicon, we
permit it (no longer a hard-fail) but log the caveats above.

### Hypervisor resolution algorithm

A single helper — `resolve_hypervisor()` in bash, `Resolve-SocoolHypervisor`
in PowerShell — returns one of `virtualbox`, `libvirt`, or exits non-zero.
Order of operations:

1. **Explicit override wins.** Honour `SOCOOL_HYPERVISOR` env var and
   `--hypervisor` flag. Validate the choice against the matrix for the
   detected OS+arch; reject with remediation message if incompatible.
2. **Walk the matrix.** Pick the primary for the host. If primary is
   missing, try fallback.
3. **Detect conflicts.** Windows only: enumerate Hyper-V feature state,
   WSL2 version (1 vs 2), Docker Desktop backend. Any of these on → hard
   fail with remediation.
4. **Ambiguity.** Linux x86_64 with both VirtualBox and QEMU/KVM installed
   → prompt the user using the pause-for-activation pattern; default =
   the primary from the matrix.

### Windows conflict handling — the philosophy

On Windows, we **detect and refuse**, not **detect and fix**. Rationale:

- Disabling Hyper-V requires a reboot and breaks WSL2, Docker Desktop,
  Windows Sandbox, and any Hyper-V-backed VM a user already depends on.
- `bcdedit /set hypervisorlaunchtype off` is a shared global setting. An
  installer that flips it has made a decision the user didn't authorise.
- Even if we asked for consent, the next Windows update may re-enable
  Hyper-V automatically, silently un-fixing our fix.

**Note on WHPX coexistence (2026-04-24 verification):** VirtualBox 7.1+
with the Extension Pack can run on the Windows Hypervisor Platform
(WHPX) while Hyper-V is active, so the technical answer to "can they
coexist" is now yes. We still refuse this configuration because:

- Reported performance is up to ~20× slower than native VT-x (guest
  boot times measured in minutes, not seconds).
- VirtualBox 7.2.4 has a known issue crashing Windows 11 guests at
  startup when WHPX is active. Moving target.
- A SOC lab with an attacker, SIEM, and scanner under sustained load
  is exactly the workload where WHPX's overhead is worst felt.

"Works technically" is not the same as "works for the lab". We keep
the hard refuse and document the alternative for users who choose to
accept the performance penalty manually by unsetting
`SOCOOL_STRICT_HYPERV_CHECK` in a future release (not yet implemented).

Therefore the failure message is explicit:

> VirtualBox 7.x is installed, but Hyper-V is currently enabled. VirtualBox
> and Hyper-V cannot coexist reliably on Windows; VMs will fail to start or
> will run at severely degraded performance.
>
> You have three options:
>
> 1. Disable Hyper-V (breaks WSL2 and Docker Desktop until you re-enable):
>    run `bcdedit /set hypervisorlaunchtype off` as Administrator and
>    reboot.
> 2. Move SOCool to a Linux host (recommended for the full scanner
>    workload, which needs nested virtualisation).
> 3. Wait for a future SOCool release with Hyper-V-native support (not
>    currently on the roadmap).

### Apple Silicon

VirtualBox 7.1 added production macOS aarch64 host support and 7.2
continues it. For SOCool specifically we still route Apple Silicon to
QEMU as primary (see the table note above) because the lab's x86
guests — pfSense and the Windows victim — would run under x86
emulation regardless of hypervisor, and QEMU's TCG emulator is well
understood, whereas VirtualBox 7.2.4's Windows-guest crash issue
introduces a moving target. `brew install qemu` provides the
open-source QEMU; UTM is surfaced as a GUI wrapper for users who
prefer it. A user can override to VirtualBox via
`SOCOOL_HYPERVISOR=virtualbox` and accept the caveats.

### Nested virtualisation

Required for Nessus / OpenVAS workloads and recommended for Wazuh. The
preflight check in `scripts/preflight/check-nested-virt.sh` verifies:

- **Linux KVM:** `/sys/module/kvm_intel/parameters/nested` or
  `/sys/module/kvm_amd/parameters/nested` reads `Y` / `1`.
- **VirtualBox:** `VBoxManage modifyvm ... --nested-hw-virt on` succeeds
  on a throwaway VM (capability probe, immediately deleted).
- **macOS:** nested virt is not user-exposed; the scanner VMs are
  documented as best-effort on macOS.
- **Windows:** VirtualBox exposes nested virt on AMD hosts reliably, on
  Intel hosts only on recent CPUs; the check reports the result and
  allows the user to continue with a warning if they opt out of the
  scanner VM.

## Consequences

### Positive

- No silent platform swaps — a user who expects VirtualBox gets
  VirtualBox or a clear refusal.
- No unauthorised global changes to the host (Hyper-V stays as the user
  configured it).
- The matrix is a single source of truth referenced from three places
  with a parity test in `tests/parity/`.

### Negative

- Windows users with Hyper-V-dependent tooling cannot run SOCool without
  making a disruptive change. This is a real limitation we accept.
- Apple Silicon users get a slower lab (x86 emulation for the Windows
  victim) and fewer tested workloads.
- Maintaining three-way parity (matrix table, README, skill file) has a
  small cost; offset by the parity test.

### Mitigations

- `docs/troubleshooting.md` carries a dedicated section for every
  hard-blocked combination, with the same remediation text as the
  runtime failure message.
- The scanner VM is `optional: true` in `config/lab.yml`, so hosts
  without nested virt can still run the rest of the lab.

## Alternatives considered

### A. Support only Linux x86_64

- **Pro:** simplest matrix, best hypervisor story.
- **Con:** eliminates the majority of home lab users (Windows / macOS
  laptops).
- **Rejected** on audience reach.

### B. Automate Hyper-V disable on Windows

- **Pro:** frictionless for users.
- **Con:** requires admin + reboot, breaks unrelated tooling, and the
  "fix" may be silently reverted by Windows Update.
- **Rejected** on respect-the-user-OS-state grounds. Documented in the
  Windows conflict-handling section above.

### C. Silent fallback between hypervisors

- **Pro:** "it just works."
- **Con:** surprising behaviour, breaks user mental model, makes
  troubleshooting harder.
- **Rejected** per the philosophy stated above.

### D. Require Hyper-V on Windows and target it natively

- **Pro:** aligns with Microsoft's preferred virtualisation.
- **Con:** Packer's Hyper-V builder is functional but less well-trodden
  than the VirtualBox builder for pfSense and Windows dev images; the
  Vagrant Hyper-V provider has rougher edges for our use case. We'd
  pay a reliability tax on every release.
- **Rejected** for v1; may be revisited in a future ADR if the
  VirtualBox situation on Windows deteriorates further.

## References

- VirtualBox manual: https://www.virtualbox.org/manual
- VirtualBox 7.2 Apple Silicon announcement:
  https://blogs.oracle.com/virtualization/oracle-virtualbox-72
- VirtualBox downloads & current version:
  https://www.virtualbox.org/wiki/Downloads
- libvirt / QEMU documentation: https://libvirt.org/docs.html
- Microsoft — Virtualization apps and Hyper-V coexistence:
  https://learn.microsoft.com/en-us/troubleshoot/windows-client/application-management/virtualization-apps-not-work-with-hyper-v
- Microsoft Hyper-V + nested virtualisation:
  https://learn.microsoft.com/en-us/virtualization/hyper-v-on-windows/user-guide/nested-virtualization
- HashiCorp Vagrant providers:
  https://developer.hashicorp.com/vagrant/docs/providers
- [ADR-0001](./0001-packer-plus-vagrant.md) — tool choice that this ADR
  builds on.
- `.skills/devops/SKILL.md` (hypervisor matrix duplicated there)
