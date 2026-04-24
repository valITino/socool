# shell-scripting

## Role

Owns every line of bash and PowerShell that runs on the host: `setup.sh`, `setup.ps1`, everything under `scripts/` that orchestrates the lab (not in-VM provisioners, those are `software-engineer`).

## When to invoke

Read this skill before touching:

- `setup.sh`, `setup.ps1`
- Any file under `scripts/preflight/`, `scripts/lib/`, `scripts/*.sh`, `scripts/*.ps1`
- Any change to prompt UX, exit codes, OS detection, package-manager bootstrap, or the pause-for-activation flow

Trigger keywords: *bash, powershell, preflight, prompt, OS detection, installer, parity, exit code*.

## Conventions & checklists

### Bash

- Shebang: `#!/usr/bin/env bash`. First three lines: `set -euo pipefail`, `IFS=$'\n\t'`, a comment naming the script's one job.
- Target Bash 4+. No zsh/dash-only constructs. `[[ ... ]]`, not `[ ... ]`.
- Quote every variable: `"$var"`, `"${arr[@]}"`. No unquoted command substitution.
- `$(...)` only, never backticks. `eval` forbidden except with a `# eval-justified:` comment.
- `shellcheck` clean at `-S style`. No disabled rules without inline justification.
- All shared helpers live in `scripts/lib/common.sh`; sourced with `# shellcheck source=scripts/lib/common.sh`.
- Subprocess calls pass arguments as separate tokens — never build a command string and pass it to a subshell.

### PowerShell

- Target PowerShell 7+ (cross-platform). Avoid `Get-WmiObject`, `Get-CimInstance` is Windows-only, gate appropriately.
- Top of every script: `Set-StrictMode -Version Latest`, `$ErrorActionPreference = 'Stop'`, `$PSNativeCommandUseErrorActionPreference = $true`.
- Advanced functions with `[CmdletBinding()]` and `[Parameter(Mandatory)]` validation. No positional magic.
- `PSScriptAnalyzer` clean. No suppressions without inline justification.
- Shared helpers in `scripts/lib/common.ps1`, dot-sourced: `. "$PSScriptRoot/lib/common.ps1"`.
- Call externals via argument arrays: `& packer @('build', '-var-file=x.pkrvars', 'template.pkr.hcl')`. Never string-concatenate commands.

### OS & architecture detection

- Bash: use `uname -s` (Linux/Darwin) + `uname -m` (x86_64/aarch64/arm64). Record into `SOCOOL_OS` and `SOCOOL_ARCH`.
- PowerShell: `$IsWindows`, `$IsLinux`, `$IsMacOS`, then `[System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture` for arch.
- Central helper: `detect_host()` (bash) / `Get-SocoolHost` (pwsh). Every other script calls this — no ad-hoc checks.

### Prompt UX — the pause-for-activation pattern

Every human-in-the-loop step follows this exact shape:

```
━━━ Action required: <one-line title> ━━━
What:  <one-sentence description of the step>
Where: <URL or path>
Paste: <what the user must provide back>
Env:   <SOCOOL_* env var to skip this prompt in CI>
```

Then prompt. Every prompt:

- Has a sensible default shown as `[default]`.
- Accepts an env var or CLI flag override (document both).
- Never silently loops — on empty input, re-show the prompt with the default highlighted.
- On stdin-is-not-a-tty **and** no env var set, fail fast with exit code 64 and a message telling the user which env var to set.

### Exit codes (project-wide contract)

- `0` success
- `1` generic runtime failure (last resort — prefer a specific code)
- `2` invalid CLI usage
- `10-19` preflight failures (see `scripts/preflight/README.md`; each check owns one code)
- `20-29` dependency install failures
- `30-39` hypervisor/network conflicts
- `40-49` Packer build failures
- `50-59` Vagrant lifecycle failures
- `60-63` credential / secret handling failures (`64` reserved for "non-interactive run without required env var")
- `70-79` smoke-test failures

New codes require an update to `docs/troubleshooting.md` and `scripts/preflight/README.md` in the same commit.

### Parity enforcement

- Every capability in `setup.sh` has an equivalent in `setup.ps1`, same prompt text, same env-var name, same exit code.
- A `tests/parity/` script diff-compares the prompt catalogue and env-var list between the two scripts; any drift fails CI.

## Interfaces with other skills

- **Defers to:**
  - `secure-coding` on input validation, subprocess argument passing, temp files, downloads.
  - `devsecops` on checksum verification and secret surfacing.
  - `devops` on *what* to do with a hypervisor once detected (this skill only detects and dispatches).
- **Is deferred to by:** everyone who writes anything that runs on the host OS.

## Anti-patterns

- `curl ... | bash` in `setup.sh`. Download to a temp file, checksum, then execute.
- Using `&&`/`||` long chains instead of `set -e` + explicit guards. Readability matters; this is run with sudo.
- PowerShell calls built with `Invoke-Expression` or string-concatenated commands.
- Bash `rm -rf "$var/"` where `$var` could be empty. Always guard: `[[ -n "$var" ]] || { echo "bug"; exit 1; }`.
- Prompting without an env-var / flag equivalent — breaks CI and CLAUDE.md's non-interactive requirement.
- Silently degrading on unsupported platforms instead of exiting with a remediation message.
- Parity drift: adding a flag to `setup.sh` and not `setup.ps1` (or vice versa) in the same commit.
