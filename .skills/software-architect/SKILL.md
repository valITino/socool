# software-architect

## Role

Owns repo-wide structure, cross-cutting decisions, ADR authorship, and conflict resolution between other skills in SOCool.

## When to invoke

Read this skill before:

- Creating, moving, renaming, or deleting any top-level directory (`packer/`, `vagrant/`, `config/`, `scripts/`, `tests/`, `docs/`, `.skills/`)
- Changing the `config/lab.yml` schema (adding/removing fields, renaming keys, altering nesting)
- Authoring or amending any file under `docs/adr/`
- Any task that touches 3+ subsystems (e.g., "add a new scanner VM" spans `config/lab.yml`, `packer/`, `vagrant/`, `scripts/preflight/`, `tests/`, and `docs/runbooks/`)
- Resolving a disagreement between two other skills (typical example: `devops` wants a faster cached download path, `devsecops` insists on publisher-sourced checksum every run)
- Introducing a new language, framework, or major dependency
- Any change to the skill layer itself (`.skills/*/SKILL.md`)

Trigger keywords in a task description: *architecture, schema, ADR, restructure, cross-cutting, tradeoff, conflict between skills*.

## Conventions & checklists

### Directory layout (authoritative)

```
socool/
├── CLAUDE.md
├── README.md
├── CHANGELOG.md
├── .env.example
├── .gitignore
├── setup.sh
├── setup.ps1
├── .skills/<skill-name>/SKILL.md
├── config/
│   └── lab.yml
├── scripts/
│   ├── preflight/        # modular preflight checks, one file per check
│   └── lib/              # shared bash/pwsh helpers (parity enforced)
├── packer/<vm-name>/
│   ├── template.pkr.hcl
│   ├── variables.pkr.hcl
│   ├── http/             # autounattend.xml / preseed.cfg / config.xml
│   └── README.md
├── vagrant/
│   └── Vagrantfile
├── tests/
│   ├── preflight/
│   ├── smoke/
│   ├── idempotency/
│   └── destroy-recreate/
└── docs/
    ├── adr/0000-template.md, 0001-…, 0002-…
    ├── runbooks/<vm-name>.md
    ├── troubleshooting.md
    └── network-topology.md
```

Do not invent parallel hierarchies. If a new concept does not fit, write an ADR proposing the extension before creating the folder.

### `config/lab.yml` schema (v1 — bump on breaking change)

Top-level keys: `version`, `network`, `credentials_policy`, `vms`. Each VM entry: `hostname`, `role` (one of: `firewall`, `attacker`, `victim`, `siem`, `scanner`), `box` (Packer output box name), `ip`, `ram_mb`, `cpus`, `disk_gb`, `network_role` (one of: `wan`, `lan`, `dmz`, `management`), `boot_order` (integer; pfSense=0), optional `depends_on` (list of hostnames).

Every change to this schema requires a version bump and an ADR.

### ADR conventions

- File name: `docs/adr/NNNN-kebab-case-title.md`
- Sections: Status · Context · Decision · Consequences · Alternatives considered · References
- Never rewrite a merged ADR to change its decision — supersede it with a new ADR and mark the old one `Superseded by NNNN`.

### Conflict resolution rules

1. Hard invariants in `CLAUDE.md` beat every skill.
2. Between two skills, the **stricter** rule wins (e.g., `devsecops` checksum requirement beats `devops` cache shortcut).
3. Unresolvable conflicts become an ADR, not a silent pick.
4. Document the tradeoff in the commit message.

## Interfaces with other skills

- **Owns:** repo layout, `config/lab.yml` schema, ADR process, skill-layer integrity.
- **Defers to:**
  - `devsecops` on any security/supply-chain invariant (never overrule a security rule for architectural elegance).
  - `documentation` on doc file naming and structure once a folder exists.
- **Is deferred to by:** `software-engineer`, `devops`, `shell-scripting`, `qa-tester` when a change spans subsystems or alters a shared contract.

## Anti-patterns

- Adding a hardcoded IP, CIDR, or hostname anywhere *other* than `config/lab.yml`.
- Creating a new top-level directory without an ADR.
- Editing a merged ADR's Decision section instead of superseding it.
- Letting `setup.sh` and `setup.ps1` drift because "we'll fix parity later."
- Resolving skill conflicts by whichever argument was written last instead of applying the stricter-rule principle.
- Skipping an ADR because "it's just a small restructuring." Small restructurings compound into confusion.
