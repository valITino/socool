# devops

## Role

Owns hypervisor detection/selection, VM lifecycle (create/start/stop/destroy), the lab network topology, and Vagrant provider configuration for VirtualBox and libvirt/QEMU.

## When to invoke

Read this skill before touching:

- Any hypervisor-detection logic (VirtualBox, QEMU/KVM, Hyper-V conflict checks)
- `vagrant/Vagrantfile` provider blocks
- Network definitions in `config/lab.yml` (CIDRs, subnets, network roles)
- Any script that invokes `VBoxManage`, `virsh`, `qemu-img`, `vagrant up/halt/destroy/reload`
- ISO download/caching logic (`packer_cache/`, `.socool-cache/`)

Trigger keywords: *hypervisor, VirtualBox, QEMU, KVM, libvirt, Vagrant provider, network, CIDR, ISO, nested virt*.

## Conventions & checklists

### Hypervisor matrix (authoritative; keep in sync with ADR-0002)

| Host OS | Arch | Primary | Fallback | Hard-blocked by |
|---|---|---|---|---|
| Linux | x86_64 | VirtualBox | QEMU/KVM (libvirt) | — |
| Linux | aarch64 | QEMU/KVM | — | VirtualBox (no aarch64 support) |
| macOS | x86_64 (Intel) | VirtualBox | QEMU | — |
| macOS | aarch64 (Apple Silicon) | QEMU/UTM | — | VirtualBox (unsupported on Apple Silicon host as of 7.1) |
| Windows | x86_64 | VirtualBox | — | Hyper-V enabled, WSL2 using Hyper-V backend, Docker Desktop with WSL2 backend |
| Windows | aarch64 | *unsupported* | — | — |

Every release, re-verify this table via Phase 1 web research. Upstream compatibility changes frequently.

### Hypervisor detection contract

A single function `resolve_hypervisor()` (bash) / `Resolve-SocoolHypervisor` (pwsh) returns one of: `virtualbox`, `libvirt`, or exits non-zero with a remediation message. Its decision tree:

1. Honor explicit `SOCOOL_HYPERVISOR` env var / `--hypervisor` flag.
2. Walk the matrix above for the detected OS+arch.
3. Detect conflicts (Hyper-V on Windows, KVM module missing on Linux).
4. If multiple valid options exist, prompt using the pause-for-activation pattern; default = matrix primary.

### Lab network topology

Three isolated networks, all host-only / internal (never bridged by default):

- `wan-sim` (simulated Internet-facing; CIDR from `config/lab.yml`) — pfSense WAN interface lives here alone with a NAT gateway to host (provider-native NAT).
- `lan` — pfSense LAN, Kali, Windows victim.
- `management` — pfSense management NIC, Wazuh, scanner.

Enforced in the Vagrantfile and verified by a smoke test that pings across expected paths and *fails* on unexpected ones (e.g., Kali must **not** reach the `management` subnet directly).

### Vagrant provider specifics

- **VirtualBox:** `vb.linked_clone = true`, `vb.check_guest_additions = false` (we bake them in the box), explicit NIC type `virtio` where supported.
- **libvirt:** `lv.driver = 'kvm'`, `lv.machine_virtual_size = …`, `lv.storage_pool_name = 'socool'`. Storage pool created by preflight if absent, never auto-destroyed.

### VM lifecycle rules

- `vagrant up` and `vagrant destroy -f` are the only authorized lifecycle commands in scripts.
- Never `VBoxManage controlvm <vm> poweroff` or `virsh destroy <vm>` directly — always go through Vagrant so state stays consistent.
- ISO cache directory is `./.socool-cache/iso/` (gitignored). Reuse cached ISOs iff the checksum still matches.

## Interfaces with other skills

- **Defers to:**
  - `devsecops` on every download (checksum, publisher origin) and on whether bridged networking is allowed.
  - `software-architect` on network CIDR schema and adding new network roles.
- **Collaborates with:**
  - `shell-scripting` at the orchestration boundary — this skill provides the primitives, `shell-scripting` chains them.
  - `software-engineer` at the Vagrantfile boundary.
- **Is deferred to by:** `qa-tester` for smoke tests that verify the network and VM-lifecycle commands.

## Anti-patterns

- Silently falling back from VirtualBox to QEMU on Windows "because the user has Hyper-V" — that path is a hard-fail with remediation, not a silent swap.
- A bridged network in the default `Vagrantfile`, even "just for testing."
- `VBoxManage` calls peppered throughout orchestration scripts — concentrate them behind one helper or don't use them at all.
- Re-using the default NAT network `10.0.2.0/24` for a lab subnet; it collides with VirtualBox's own NAT and will cause routing heisenbugs.
- Hardcoding a storage pool path in the Vagrantfile instead of reading from `config/lab.yml`.
- Assuming nested virt is available without a preflight check — some hosts disable it at the BIOS/UEFI level.
