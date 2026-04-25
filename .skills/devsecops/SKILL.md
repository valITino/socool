# devsecops

## Role

Owns secret handling, supply-chain verification, lab firewall policy, and hardening defaults for every VM SOCool produces.

## When to invoke

Read this skill before touching:

- Any code that downloads an artifact (ISO, Vagrant box, installer, checksum, signing key)
- Any place a credential (license key, password, API token) is collected, stored, rotated, or displayed
- Default firewall rules in pfSense's `config.xml` seed
- Wazuh agent enrollment, keys, and secure-by-default settings
- Any opt-in to bridged networking, open ports, or relaxed auth
- `.env.example` contents and `.gitignore` rules around secrets

Trigger keywords: *checksum, signature, license, credential, password, secret, firewall, CVE, supply chain, bridged*.

## Conventions & checklists

### No secrets in the repo — ever

- `.env` is gitignored. `.env.example` has only placeholder values like `CHANGE_ME_AT_RUNTIME`, never realistic-looking fakes that could be confused for real secrets.
- No secret ever echoed to stdout unless the user is the intended recipient and we're at the post-provision summary.
- No secret written to a log file. If a provisioner needs to log "credential rotated," it logs the fact, not the value.
- Pre-commit: `git diff` grep for `BEGIN (RSA|OPENSSH|PGP)`, `password=`, `api_key=`, ≥20-char high-entropy strings. A weak heuristic, but worth running.

### Checksum & signature verification

- Every downloaded artifact verifies a SHA-256 (or stronger) checksum.
- The checksum is **fetched from the publisher's own HTTPS endpoint** at build/run time — never pasted as a literal into the repo. Literals go stale silently.
- Where the publisher offers a signed checksum file (pfSense, Debian/Ubuntu, Wazuh), verify the signature before trusting the checksum. Pin the signing key fingerprint in `config/lab.yml` under `credentials_policy.signing_keys`.
- If a publisher does *not* publish a checksum, stop. Do not ship that artifact. Escalate to `software-architect`.

### Default-credential rotation contract

Every VM provisioned from an image with a documented default credential must:

1. Rotate the credential during the Packer build (preferred) or first-boot provisioner (fallback).
2. Generate the new credential with a CSPRNG — `openssl rand -base64 24` (bash), `[System.Web.Security.Membership]::GeneratePassword(32, 6)` is *banned* (non-CSPRNG); use `System.Security.Cryptography.RandomNumberGenerator` in PowerShell.
3. Emit the new credential to the Packer artifact manifest (`packer/<vm>/artifacts/credentials.json`, gitignored).
4. `setup.sh`/`setup.ps1` reads the manifest and prints the credentials in the **final summary only**, never mid-run.
5. A smoke test verifies the **old default password no longer works**.

### Lab firewall policy (pfSense seed)

- Default deny on WAN.
- `management` ↔ `lan`: deny by default, allow only the ports Wazuh/scanner need for their role (and log the rest).
- `lan` → `wan-sim`: allow (attacker needs Internet-sim for realistic traffic).
- `wan-sim` → `lan`: default deny; explicit allows only for traffic the lab scenarios need.
- webConfigurator never bound to WAN. Management only on `management`.

### Network isolation

- Bridged networking requires `SOCOOL_ALLOW_BRIDGED=1` **and** a confirmation prompt **and** a printed warning that explains the risk.
- The lab's default CIDRs are RFC1918 ranges chosen to minimize collision with common home/office networks; a preflight check rejects overlap with the host's existing routes.

### Supply-chain watchlist (re-check every Phase 1)

- Kali Vagrant box publisher: `kalilinux/rolling` (official) — verify fingerprint each release.
- pfSense ISO: Netgate only (no third-party mirrors).
- Windows dev VM: Microsoft Edge/Windows Dev Center only.
- Wazuh: official RPM/DEB repos with GPG key pinned.
- Nessus Essentials: Tenable only, license-gated.
- OpenVAS/GVM: Greenbone official.

## Interfaces with other skills

- **Overrides:** `devops` and `software-engineer` on any security tradeoff (stricter-rule principle).
- **Collaborates with:** `secure-coding` on how secrets move through code (this skill defines *what* is a secret and *where* it comes from; `secure-coding` ensures the code path is safe).
- **Is deferred to by:** every skill that touches the network, downloads, or credentials.

## Anti-patterns

- "Temporary" hardcoded checksum literals. They outlive the person who added them.
- `curl -sSL ... | sudo bash` anywhere in the codebase.
- Generating passwords with Bash `$RANDOM` or PowerShell `Get-Random` — not CSPRNGs.
- Printing the final credentials during the build ("for debugging") and forgetting to remove the line.
- A `.env.example` that contains a plausible-looking fake key like `sk-proj-abc123...` — confusing for users, and sometimes accidentally valid.
- Opening `any→any` on any pfSense rule "to unblock the demo." Fix the rule.
- Trusting a Vagrant box from Vagrant Cloud without checking the publisher namespace.
