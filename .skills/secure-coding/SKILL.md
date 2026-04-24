# secure-coding

## Role

Owns the correctness and safety of every code path that takes input, calls a subprocess, writes a temp file, handles a downloaded artifact, or crosses a privilege boundary.

## When to invoke

Read this skill before writing:

- Any subprocess invocation (bash, PowerShell, Python, Ruby)
- Any code that accepts user input from a prompt, CLI flag, env var, or file
- Any temp-file creation, especially under privileged context
- Any file download and execution
- Any sudo/elevation request
- Any path built from a variable (path traversal surface)
- Any code that parses YAML, XML, JSON from outside the repo

Trigger keywords: *subprocess, input, validate, sanitize, temp file, download, sudo, elevation, injection, path traversal*.

## Conventions & checklists

### Subprocess invocation — zero-tolerance rules

- **Bash:** always pass arguments as separate tokens.
  - Good: `packer build -var-file="$vars" "$template"`
  - Bad: `packer build $cmd` (word-split injection)
  - Never `bash -c "$user_input"`; never `eval` without an inline `# eval-justified:` comment explaining why nothing else works.
- **PowerShell:** use the call operator `&` with an argument array, or native cmdlets.
  - Good: `& packer @('build', "-var-file=$vars", $template)`
  - Bad: `Invoke-Expression "packer build $cmd"`
  - Never `Start-Process -ArgumentList` with a single pre-built string.
- **Python:** `subprocess.run([...], shell=False)` always. `shell=True` is forbidden.
- **Ruby (Vagrantfile):** use the array form of `system` / `exec`; never backticks with interpolation.

### Input validation

- Validate at the boundary; trust internally.
- For IPs, CIDRs, hostnames: parse with a library (`ipaddress` in Python, `[ipaddress]::Parse` in PowerShell, `getent hosts` probing in bash) — never regex-only.
- For file paths from user input: resolve to absolute, then verify it is inside the expected directory (no `..` escape). Reject symlinks that cross the boundary.
- For YAML from `config/lab.yml`: use a safe loader (`yaml.safe_load` in Python, `ConvertFrom-Yaml` via `powershell-yaml` in pwsh, `yq` in bash). Never `yaml.load` / `Invoke-Expression` on a config.

### Temp file handling

- Bash: `mktemp` only; `trap 'rm -rf "$tmp"' EXIT` immediately after creation.
- PowerShell: `New-TemporaryFile` under `[System.IO.Path]::GetTempPath()`, remove in `finally`.
- Never `/tmp/socool-$$` — predictable, and `/tmp` is world-writable on shared systems.
- Files containing secrets: create with `umask 0177` / `-Mode 0600` equivalent *before* writing content.

### Downloads

- Use `curl -fsSL --proto =https --tlsv1.2 -o <tmp> <url>` (bash) or `Invoke-WebRequest -Uri <url> -OutFile <tmp> -UseBasicParsing` (pwsh).
- `--proto =https` (bash) enforces HTTPS-only — a plain `http://` redirect fails.
- Verify checksum **before** moving the file into the cache directory or executing it.
- Never `curl ... | sh`. Always land, verify, then run.

### Privilege boundaries

- Scripts ask for sudo / admin **once**, at the top, with a clear reason. Do not re-prompt per step.
- Never cache sudo credentials past the script run.
- Packer provisioners should drop privilege back to an unprivileged user as soon as package install is complete.
- `setup.sh` uses `sudo -n true` as a preflight gate; if no cached creds and stdin isn't a tty, exits with code 64.

### Path traversal / injection surfaces

- `config/lab.yml` hostnames and role names flow into filesystem paths (`packer/<role>/…`). Validate they match `^[a-z][a-z0-9-]{0,30}$` at load time.
- The Vagrantfile `vm.box = ` value flows to disk; same rule.

## Interfaces with other skills

- **Collaborates with:** `devsecops` (that skill says *what* is sensitive; this one says *how code must handle it*).
- **Enforced by:** `qa-tester` — every new subprocess call gets a test that passes an adversarial input.
- **Is deferred to by:** `shell-scripting`, `software-engineer`, `devops` on any code-level question.

## Anti-patterns

- `bash -c "$var"`, `Invoke-Expression $var`, `subprocess.run(cmd, shell=True)`, `eval "$cmd"` — all forbidden without an inline justification comment that will survive code review.
- Building a command with string concatenation "because it's easier": `cmd="packer build $flags"; $cmd`.
- `mkdir -p /tmp/socool && cd /tmp/socool` — predictable path, race condition.
- Downloading over HTTP and "just noting we should fix it later."
- Trusting `config/lab.yml` contents (it's repo-local, but a malicious fork is a supply-chain vector for a user who cloned it).
- Passing secrets via command-line arguments — they appear in `ps` output. Use stdin or an env var file with `0600` perms.
- Assuming `umask` is `022` everywhere; set it explicitly before creating sensitive files.
