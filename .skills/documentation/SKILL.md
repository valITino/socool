# documentation

## Role

Owns every user-visible word in the repo: `README.md`, ADRs, per-VM runbooks, troubleshooting guide, network topology doc, changelog, and the in-script help text/prompts.

## When to invoke

Read this skill before:

- Creating or editing `README.md`, `CHANGELOG.md`, any file under `docs/`
- Writing or editing a prompt, help text, or failure message in `setup.sh`/`setup.ps1` (because those strings are user-facing docs)
- Adding a new VM (needs a runbook), a new preflight check (needs a troubleshooting entry), or a new exit code (needs a troubleshooting entry)
- Authoring an ADR (`software-architect` owns the decision; this skill owns the prose)

Trigger keywords: *README, docs, ADR, runbook, troubleshooting, changelog, help text, error message*.

## Conventions & checklists

### Voice & style

- Second person, present tense: *"Run `setup.sh`. The script detects your OS…"*.
- Short paragraphs; prefer lists and tables over prose when listing parallel items.
- Every command shown is copy-pasteable. Prefix `$` only when needed for disambiguation; the code block's language tag is the signal.
- No ASCII art banners, no gratuitous emoji, no marketing adjectives. The tone is "technical teammate writing for another technical teammate."
- Flag unknowns honestly. If a step hasn't been validated on macOS aarch64, say so — don't imply blanket support.

### File templates

- **README.md** sections: What SOCool is · Components table · Quickstart · Requirements · Lab topology diagram · Troubleshooting index (links out) · Contributing · License.
- **ADR** (`docs/adr/NNNN-kebab-title.md`): Status · Context · Decision · Consequences · Alternatives considered · References. Keep each under ~500 lines.
- **Runbook** (`docs/runbooks/<vm>.md`): Purpose · Image source (with URL and publisher) · Default credential policy · Where rotated creds appear · How to reach it (command) · How to reset it · Known gotchas · Log locations.
- **Troubleshooting** (`docs/troubleshooting.md`): one row per exit code (table columns: `code`, `meaning`, `most likely cause`, `remediation command`). Cross-linked from the preflight scripts by `#ec-NN` anchors.
- **CHANGELOG.md**: keep-a-changelog format, `Unreleased` section at top, dated releases below. First release: `0.1.0`.

### Linking rules

- Every ADR that references another ADR uses a relative link: `[ADR-0002](./0002-hypervisor-matrix.md)`.
- Every runbook links to the VM's Packer template directory and its `config/lab.yml` entry (via line anchor).
- Every troubleshooting entry links to the preflight script that emits the code and the runbook (if any) for the affected VM.

### In-script strings

- Every `echo`/`Write-Host` that a user might see is a doc artifact; it obeys the voice rules above.
- Prompts follow the pause-for-activation template from `shell-scripting`'s `SKILL.md`.
- Failure messages are triples: *what failed · why · what to do next*. Never just "failed."

### Diagrams

- Topology diagram in `docs/network-topology.md` is Mermaid (`flowchart LR`/`TB`) primary, ASCII-art fallback in a `<details>` block for terminal viewers.
- IPs and CIDRs referenced in diagrams come from `config/lab.yml`. If the YAML changes, the diagram changes in the same commit.

### Changelog discipline

- Every user-visible change (new flag, breaking schema change, new VM, changed default) gets a `CHANGELOG.md` entry in the same commit.
- Entries grouped: `Added`, `Changed`, `Deprecated`, `Removed`, `Fixed`, `Security`.

## Interfaces with other skills

- **Collaborates with:** every skill that ships user-visible output. Each skill owns the *correctness* of its domain; this skill owns the *prose*.
- **Defers to:** `software-architect` on ADR decision content; `devsecops` on how to phrase anything security-sensitive (don't accidentally leak advice that normalises risk).
- **Is deferred to by:** `shell-scripting` on prompt wording, `qa-tester` on failure-message assertions.

## Anti-patterns

- A runbook that says "default credentials: admin/admin" — runbooks describe **policy**, not values. The values come from the rotated-credential summary at the end of `setup.sh`.
- Documentation that reads like vendor marketing ("seamlessly provisions a state-of-the-art SOC lab"). Cut it.
- An undocumented exit code. An undocumented flag. An undocumented prompt. Each is a doc bug.
- Linking to a vendor URL without noting the date checked — URLs rot; our Phase 1 research must be anchored in time.
- A changelog entry added "in the next release PR" — must land with the change itself.
- A diagram that contradicts `config/lab.yml` because one was updated and the other wasn't.
