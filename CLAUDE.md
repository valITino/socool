# SOC-Lab — Claude Code Instructions

A one-command SOC lab provisioner. User clones the repo, runs `setup.sh` or `setup.ps1`, and ends up with a networked lab of Kali, pfSense, Windows victim, Wazuh, and (optionally) Nessus/OpenVAS running on VirtualBox or QEMU/KVM.

This file is the governance layer. It does not contain implementation — it tells you **how to develop this project**, **which skill to consult for which kind of work**, and **which invariants must never be broken**.

---

## ⚠️ Mandatory Protocol — Read Before Touching Anything

Before making **any** fix, refactor, addition, or change — no matter how small it looks — you must complete all three phases below in order. **No exceptions.**

> **Note on tradeoffs:** Generic coding guidance often says "for trivial tasks, use judgment and skip the ceremony." That shortcut **does not apply here.** This project ships shell and PowerShell scripts that run with elevated privileges on a user's machine, touch hypervisors, modify network configuration, and download large binaries from the internet. A sloppy one-liner can brick a host OS, leak a license key, or create a lab that silently fails to isolate from the user's LAN. Bias toward caution over speed, always.

### Phase 1: Web Research — Cast a Wide Net

Search the web for current, accurate information on **anything the task touches** that may have changed, broken, or gained known issues since your training cutoff. Err on the side of over-researching.

At minimum, research:

- **Every tool, package, runtime, or hypervisor involved in the change** — current version, deprecations, breaking changes, known CVEs, platform-specific install quirks
- **Every ISO, Vagrant box, or upstream image** you plan to pull — verify publisher, current URL, checksum location, and whether the project still ships what you expect
- **Every config-file format** you generate (`autounattend.xml`, pfSense `config.xml`, Vagrantfile, Packer HCL) — the schemas evolve; confirm current syntax before writing
- **Every OS/hypervisor interaction edge case** — VirtualBox vs. Hyper-V/WSL2 conflicts, QEMU/KVM permission models, macOS Apple Silicon limitations, Windows execution policies
- **Security context relevant to the task** — default credentials in upstream images, known exposures in lab-oriented distros, supply-chain concerns on third-party Vagrant boxes

Then broaden: is there a recent GitHub issue, forum post, or advisory describing a bug very similar to what you're about to fix or introduce? Check.

If your web research is inconclusive, contradicts your prior assumptions, or returns nothing relevant — **say so explicitly** before proceeding. Do not silently fill gaps with memory.

### Phase 2: Full Codebase Review — Understand the Blast Radius

Read the **actual current state** of the codebase. Do not rely on memory from previous sessions, and do not trust summaries — open the files.

Baseline reading (always, every session):

- `CLAUDE.md` (this file), `README.md`
- The `SKILL.md` of every skill relevant to the task (see skill map below)
- `config/lab.yml` — single source of truth for hostnames, IPs, network CIDRs, credentials policy
- `setup.sh` and `setup.ps1` — because almost any change has to stay in parity across both

Task-specific reading (scale to the change):

- **Every file you plan to modify — in full**, not just the region you're touching
- **Every file that sources or is sourced by the files you're touching** (bash `source`, PowerShell dot-sourcing, Packer `variables`, Vagrant `require_relative`)
- **The parity counterpart** — if you change `setup.sh` you read `setup.ps1`, and vice versa. Drift between them is a bug.
- **Related Packer templates, Vagrantfile snippets, preseed/autounattend files** when touching any VM provisioning path
- **Tests** (`tests/preflight/`, `tests/smoke/`, `tests/idempotency/`) covering the code you're changing
- **`docs/adr/`** for any prior architectural decision that might constrain your change

If mid-review you discover the change touches more than you thought, **expand the review** — do not push ahead with a partial picture.

### Phase 3: Understand Before Acting

Before writing code, answer these internally:

1. **Root cause** — not the symptom, the actual root cause?
2. **Blast radius** — which other files, scripts, VMs, or cross-OS behaviors does this change affect?
3. **Stable contracts** — does the fix break any stable internal contract? Examples: the `config/lab.yml` schema, the Vagrant box naming convention, the skill interface, the exit-code conventions for preflight checks, the pause-for-user-input flow pattern.
4. **Security & safety invariants** — see the full list under **Hard Invariants** below. Go through them explicitly.
5. **Cross-platform parity** — does the change work identically on Linux, macOS, and Windows hosts? If behavior must diverge, is the divergence documented and tested?
6. **Idempotency** — can the user re-run the script after a partial failure and reach a correct end state? If not, the change is incomplete.
7. **Simplicity** — is there a simpler fix that achieves the same result?

Only after answering all seven — write the fix.

---

## Skill Map — Who Does What

This project is developed as if by a full software team. Each skill is a specialist role. **Before starting a task, identify which skills apply and read their `SKILL.md` files.** Most non-trivial tasks consult 2–3 skills.

| Skill | When to consult |
|---|---|
| `software-architect` | Repo structure changes, cross-cutting decisions, ADR authorship, resolving conflicts between other skills, any task that touches 3+ subsystems |
| `software-engineer` | Implementing Packer templates, Vagrantfile logic, autounattend/preseed files, config generation, any core feature code |
| `shell-scripting` | Anything in `setup.sh`, `setup.ps1`, or `scripts/` — bash/PowerShell parity, OS detection, installer bootstrapping, prompt UX, exit codes |
| `devops` | Hypervisor detection and selection, VM lifecycle (create/start/stop/destroy), network topology, Vagrant provider config, ISO acquisition |
| `devsecops` | Secret handling, supply-chain checks (checksum verification, publisher validation), firewall rule design for the lab network, hardening defaults |
| `secure-coding` | Input validation, injection-safe subprocess patterns, safe temp-file handling, safe download patterns, privilege boundaries |
| `qa-tester` | Writing and running tests — preflight, smoke, idempotency, clean-install matrix, destroy/recreate cycles |
| `documentation` | README, per-VM runbooks, troubleshooting guide, ADRs, in-script help text, changelog |

### How to "use" a skill

1. Read its `SKILL.md` before acting on its domain
2. Follow its conventions and checklists exactly
3. If two skills conflict (e.g., `devops` wants speed, `devsecops` wants checksum verification on every download), the stricter rule wins and you note the tradeoff in the PR description or commit message
4. When in doubt about scope, escalate to `software-architect`

---

## Hard Invariants

Breaking any of these is a bug, not a tradeoff. Phase 3 Q4 requires you to walk through every one of these before writing code.

### Security
- **No secrets in the repo.** No license keys, passwords, API tokens, or activation codes committed to git. Secrets go in `.env` (gitignored) or are prompted at runtime.
- **No `shell=True` / no unquoted interpolation.** All subprocess calls in scripts must use argument arrays, not string concatenation. Bash: `"$var"` always quoted. PowerShell: use parameter binding, not string building.
- **Every downloaded artifact must be checksum-verified** against a checksum obtained from the publisher over HTTPS. No exceptions for ISOs, Vagrant boxes, installers.
- **No default credentials left in place.** Every VM provisioned with an upstream default password must have it rotated during provisioning, and the rotated value must be surfaced to the user (not buried in logs).
- **The lab network must never bridge to the user's LAN by default.** Host-only / internal networks only. Bridged networking requires an explicit opt-in flag and a warning.

### Architecture
- **Single source of truth.** Hostnames, IPs, CIDRs, VM sizing live in `config/lab.yml`. Never hard-code them in scripts, Packer templates, or Vagrantfiles.
- **Packer builds boxes, Vagrant runs the lab.** Don't blur the line. Don't make Vagrant provisioners do work that belongs in a Packer template, and don't make Packer do orchestration.
- **Bash ↔ PowerShell parity.** Every user-facing capability in `setup.sh` must exist in `setup.ps1` with equivalent UX. If a platform genuinely can't support a feature (e.g., QEMU on Windows), the script exits with a clear message — it does not silently degrade.
- **Idempotent by default.** Every script, every provisioner, every installer step must be safe to re-run. Detect existing state, skip or converge — never blindly reinstall or duplicate.

### User Experience
- **Minimal prompts, at known checkpoints.** The user should be prompted only for things that genuinely require a human (license key, admin password, hypervisor choice when ambiguous). Every prompt has a default where possible, a clear explanation of what's being asked, and a way to provide the answer non-interactively via env var or flag for CI.
- **The pause-for-activation pattern is the standard for any human-in-the-loop step.** The script prints exactly what the user needs to do, where to go, what to paste back, and waits. No silent waiting, no cryptic prompts.
- **Clear failure messages.** Every failure path explains what failed, why, and what to do next. "Preflight failed" is not acceptable; "VirtualBox 7.x is installed but Hyper-V is also enabled — this combination will not work. Disable Hyper-V with [command] and reboot, or use QEMU on a Linux host." is.

---

## Cross-Platform Rules

- **Linux hosts:** VirtualBox *or* QEMU/KVM. User chooses, or script auto-detects and recommends.
- **Windows hosts:** VirtualBox only. Must detect and hard-fail on conflict with Hyper-V / WSL2 / Docker Desktop with a clear remediation message. Do not attempt to auto-disable Hyper-V — that breaks the user's other tooling.
- **macOS hosts:** VirtualBox on Intel. On Apple Silicon, VirtualBox support is limited and QEMU/UTM is preferred; detect architecture and route accordingly.
- **PowerShell:** Target PowerShell 7+ (cross-platform). Do not rely on Windows-PowerShell-only cmdlets unless Windows-gated.
- **Shell:** Target Bash 4+. Do not rely on zsh- or dash-only behavior. Use `#!/usr/bin/env bash` and `set -euo pipefail` at the top of every script.

---

## Code Standards

- **Shell scripts:** `set -euo pipefail`, all variables quoted, `shellcheck`-clean. No backticks — use `$(...)`. No `eval` without a written justification in comments.
- **PowerShell:** `Set-StrictMode -Version Latest`, `$ErrorActionPreference = 'Stop'`, `PSScriptAnalyzer`-clean. Advanced functions with `[CmdletBinding()]` and proper parameter validation.
- **Packer:** HCL2 only (no legacy JSON). Variables in `variables.pkr.hcl`, never hardcoded.
- **Vagrant:** Ruby style consistent with `rubocop` defaults. Provider-specific config gated on `config.vm.provider`.
- **Python (if/when added):** Type-annotated, Pydantic for any config loading, no `subprocess.run(..., shell=True)`.
- **YAML:** `yamllint`-clean. `config/lab.yml` uses a schema documented in the `software-architect` skill.

---

## Adding a New VM to the Lab

Follow the existing conventions — don't invent new patterns. Read at least one existing VM's Packer template and Vagrantfile block end-to-end before starting.

1. Add the VM spec to `config/lab.yml` (hostname, IP, RAM, CPUs, network role)
2. Create `packer/<vm-name>/` with `template.pkr.hcl`, `variables.pkr.hcl`, unattended-install file, and a `README.md` explaining the build
3. Add a provisioning block to `vagrant/Vagrantfile` keyed on the `lab.yml` entry
4. Add a preflight check if the VM has special host requirements (disk space, nested-virt, etc.)
5. Add a smoke test in `tests/smoke/` that verifies the VM boots and its primary service responds
6. Add an idempotency test in `tests/idempotency/` that re-runs provisioning and asserts no changes
7. Document the VM in `docs/runbooks/<vm-name>.md` (purpose, default creds policy, how to reach it, how to reset it)
8. Update `README.md` components table

---

## Key Reference Links

| Resource | URL |
|---|---|
| Packer docs | https://developer.hashicorp.com/packer/docs |
| Vagrant docs | https://developer.hashicorp.com/vagrant/docs |
| VirtualBox manual | https://www.virtualbox.org/manual |
| libvirt / QEMU | https://libvirt.org/docs.html |
| pfSense install guide | https://docs.netgate.com/pfsense/en/latest/install/ |
| Wazuh deployment | https://documentation.wazuh.com/current/installation-guide |
| Kali Linux VMs | https://www.kali.org/get-kali/#kali-virtual-machines |
| Microsoft Windows dev VM | https://developer.microsoft.com/en-us/windows/downloads/virtual-machines/ |
| Nessus Essentials | https://www.tenable.com/products/nessus/nessus-essentials |
| OpenVAS / GVM | https://greenbone.github.io/docs/latest/ |

---

## Self-Check — Are These Guidelines Working?

These guidelines are working if:

- Diffs contain fewer unnecessary changes
- Clarifying questions come **before** implementation, not after mistakes
- Every Phase 3 question is answered before code is written
- No secrets in the repo, no unverified downloads, no `shell=True`, no bridged networking by default, no drift between `setup.sh` and `setup.ps1`
- Every change was developed by consulting the right skill(s) — the PR description or commit message names them
- When research is inconclusive or the codebase review surfaces a surprise, it's named explicitly instead of papered over

---

*This project provisions real systems on the user's real machine. Research first. Understand fully. Consult the right skill. Then act.*
