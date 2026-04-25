# scripts/preflight/

Each check is its own file under `checks/`, executable, with exit codes
in the `10..19` range on failure. Step 4 lands the actual checks; this
file pins their contract now so Step 3 dispatchers are correct.

## Dispatchers

- `run-all.sh` — POSIX / Linux / macOS. Sourced by `setup.sh`.
- `run-all.ps1` — Windows / cross-platform PowerShell 7. Sourced by `setup.ps1`.

Both iterate `checks/` alphabetically, run each check in a subshell, and
aggregate failures. Any failure → dispatcher exits `10`.

## Check contract

A check:

1. Is named `check-<short-topic>.{sh,ps1}` (kebab-case, descriptive).
2. Is executable, with the standard shebang (`#!/usr/bin/env bash`) or
   `#Requires -Version 7.0` at the top.
3. Sources `scripts/lib/common.{sh,ps1}` for logging/exit helpers.
4. On success, exits `0` (optionally `log_info` a one-line confirmation).
5. On failure, prints a **one-sentence remediation** to stderr and exits
   with its assigned code from the table below.
6. Is idempotent — running twice in a row produces the same result.

## Exit-code assignment (10..19)

| Code | Check | Remediation hint |
|---|---|---|
| 10 | dispatcher aggregate failure | see individual messages |
| 11 | `check-os-arch` — unsupported host | see [ADR-0002](../../docs/adr/0002-hypervisor-matrix.md) |
| 12 | `check-cpu-virt` — VT-x / AMD-V not enabled | enable in BIOS/UEFI |
| 13 | `check-nested-virt` — nested virt unavailable | scanner VM requires it; disable the scanner (`SOCOOL_SCANNER=none`) or enable nested virt |
| 14 | `check-memory` — host RAM below lab total | close apps or skip optional VMs |
| 15 | `check-disk` — host disk space below lab total | free space or move `SOCOOL_BOX_OUTPUT_DIR` to a larger volume |
| 16 | `check-hypervisor-conflict` — Hyper-V / WSL2 / Docker on Windows | see [troubleshooting](../../docs/troubleshooting.md#windows-hyperv-conflict) |
| 17 | `check-tools-version` — Packer/Vagrant/hypervisor too old | upgrade via `setup.sh` or your package manager |
| 18 | `check-network-cidr` — lab CIDR collides with host route | edit `config/lab.yml` or disconnect the conflicting interface |
| 19 | reserved | — |

New codes require a coordinated update to this table, [`docs/troubleshooting.md`](../../docs/troubleshooting.md), and the project-wide exit-code contract in `.skills/shell-scripting/SKILL.md`.

## Running the checks standalone

```bash
# Linux / macOS
bash scripts/preflight/run-all.sh

# Windows (PowerShell 7+)
pwsh -NoProfile -File scripts/preflight/run-all.ps1
```

Both honour `SOCOOL_LOG_LEVEL` and `SOCOOL_STRICT_PREFLIGHT`.
