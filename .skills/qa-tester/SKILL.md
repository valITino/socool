# qa-tester

## Role

Owns every test in the repo — preflight, smoke, idempotency, destroy-recreate, and parity — and the runner that executes them across the Linux/macOS/Windows host matrix.

## When to invoke

Read this skill before:

- Adding or modifying anything under `tests/`
- Adding a new VM, preflight check, or CLI flag (each needs tests before shipping)
- Changing the test runner, CI config, or any shared test helper
- Validating a fix — a regression test must land in the same commit as the fix

Trigger keywords: *test, regression, smoke, preflight, idempotency, destroy-recreate, CI, coverage*.

## Conventions & checklists

### Test layout

```
tests/
├── preflight/       # unit-ish; mock environments, exercise each check
├── smoke/           # post-provision; hit live VMs over the lab network
├── idempotency/     # re-run setup; assert zero-diff
├── destroy-recreate/# vagrant destroy + re-setup; assert identical state
├── parity/          # diff setup.sh vs setup.ps1 surface area
└── lib/             # shared harness (bash/pwsh)
```

### Framework choices

- **Bash tests:** [`bats-core`](https://github.com/bats-core/bats-core) — files end in `.bats`, one behavior per test.
- **PowerShell tests:** [`Pester` 5.x](https://pester.dev) — `*.Tests.ps1`, `Describe`/`Context`/`It` blocks.
- **Python tests (if introduced for a config loader):** `pytest`, fixtures for mocked filesystems.
- Do not introduce a fourth framework without an ADR.

### Preflight tests

- One test file per preflight check (`tests/preflight/check-cpu-virt.bats` ↔ `scripts/preflight/check-cpu-virt.sh`).
- Cases required: pass, fail, ambiguous, unsupported OS, missing dependency. The failure cases assert both the exit code *and* the remediation message.
- Mock the environment — never read real `/proc/cpuinfo` in a test. Use fixture files under `tests/preflight/fixtures/`.

### Smoke tests

- Run *after* `vagrant up` completes.
- For each VM, verify: SSH/WinRM reachable on the expected interface, primary service port open, service banner/version matches what we installed.
- Explicit **negative** reachability: e.g., Kali must *not* reach the management subnet. A missing negative test is a bug.
- Smoke tests never modify the lab — read-only probes only.

### Idempotency tests

- Pre-condition: a successfully provisioned lab.
- Action: re-run `setup.sh` / `setup.ps1`.
- Assert: no Packer rebuild, no Vagrant re-provision, no changed file under `config/`, no new credential written. The script prints a clear "already provisioned, nothing to do" summary.

### Destroy-recreate tests

- Action: `vagrant destroy -f` + `setup.sh`.
- Assert: the resulting lab is identical *in structure* (hostnames, IPs, open ports, service versions) to before. Credentials rotate (they must differ). Lab-data artifacts are gone.

### Parity tests

- Extract the set of CLI flags, env vars, and prompt keys from `setup.sh` and `setup.ps1` via a deterministic grep-based parser. Diff must be empty.
- Extract exit codes from each preflight script and verify they match the table in `docs/troubleshooting.md`.

### Test hygiene

- Every fix lands with a regression test in the **same commit**.
- Tests must be deterministic. Any randomness requires a seed read from an env var with a documented default.
- A flaky test is quarantined (`@skip(reason=…)`) and filed as an issue within the same day.
- Never commit a test that requires manual steps to reproduce. CI must be able to run it unattended.

## Interfaces with other skills

- **Defers to:** every other skill on the *what* (the rule under test). This skill owns *how* we verify.
- **Is deferred to by:** every skill whose work needs verification (i.e., all of them).
- **Enforces:** the `shell-scripting` exit-code contract via `tests/parity/` and `tests/preflight/`.

## Anti-patterns

- `sleep 60` in a smoke test because "the VM takes a while." Poll with a deadline.
- Mocking only the happy path — failure-mode tests are more valuable.
- A test that passes on the maintainer's laptop but nowhere else (network- or time-dependent).
- Skipping destroy-recreate tests because they're slow. They catch the most expensive bugs.
- A fix without a regression test — forbidden by CLAUDE.md's "idempotent and tested" invariant.
- Tests that print secrets on failure. Use redacted fixtures.
