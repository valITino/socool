# Troubleshooting

Every failure path in SOCool exits with a specific code. Find the
code in the table below for a one-line diagnosis and the next step.
Ranges are defined in
[`.skills/shell-scripting/SKILL.md`](../.skills/shell-scripting/SKILL.md)
and duplicated here for quick reference.

## Exit-code index

| Code | Origin | What it means | First thing to try |
|---|---|---|---|
| `0` | any | success | — |
| `1` | any | generic runtime failure | Re-run with `SOCOOL_LOG_LEVEL=debug` to surface the real cause |
| `2` | `setup.*` argument parser | invalid CLI usage | `./setup.sh --help` |
| `10` | `scripts/preflight/run-all.sh` | aggregate preflight failure | See individual check codes above this one in the output |
| `11` | `check-os-arch` | unsupported host OS/arch | [ADR-0002](./adr/0002-hypervisor-matrix.md) matrix |
| `12` | `check-cpu-virt` | VT-x / AMD-V not enabled | Enable Intel VT-x or AMD-V in BIOS/UEFI, reboot |
| `13` | `check-nested-virt` | nested virt unavailable | Linux: `echo 'options kvm_intel nested=1' | sudo tee /etc/modprobe.d/kvm.conf && sudo modprobe -r kvm_intel && sudo modprobe kvm_intel`. Alternatively, skip the scanner with `SOCOOL_SCANNER=none`. |
| `14` | `check-memory` | host RAM below lab total | Close other apps, or reduce per-VM `ram_mb` in `config/lab.yml` |
| `15` | `check-disk` | host disk below lab total | Free space or set `SOCOOL_BOX_OUTPUT_DIR` to a bigger volume |
| `16` | `check-hypervisor-conflict` | Windows: Hyper-V / WSL2 / Docker Desktop enabled | See [Windows Hyper-V conflict](#windows-hyper-v-conflict) below |
| `17` | `check-tools-version` | git / python / packer / vagrant / hypervisor too old | Upgrade via `setup.sh` dep-install path or your package manager. Also fires when `/bin/bash` is 3.2 on macOS — use Homebrew bash. |
| `18` | `check-network-cidr` | lab CIDR overlaps with a host route | Disconnect the conflicting interface or edit `config/lab.yml` CIDRs |
| `19` | reserved | — | — |
| `20–29` | dependency install | a package manager failed | Error message includes the package and command; re-run interactively to see the prompt |
| `21` | `deps.{sh,ps1}` | package manager unsupported / HashiCorp repo refused | apt/dnf: see [HashiCorp repo](#hashicorp-apt-dnf-repo) below |
| `30` | `hypervisor.{sh,ps1}` | unsupported OS/arch/hypervisor combination | [ADR-0002](./adr/0002-hypervisor-matrix.md) |
| `40–49` | Packer build | Packer failed | Read the Packer log above the `✗` line. Most common: ISO download unreachable, boot_command timing wrong. |
| `50–59` | Vagrant lifecycle | `vagrant up/halt/destroy` failed | `cd vagrant && vagrant status`. Bring a single VM up with `vagrant up <name>` to get focused errors. |
| `60–63` | credentials | CSPRNG or manifest write failure | Check `umask`; verify `openssl` / `RandomNumberGenerator` is available |
| `64` | prompts (any) | non-interactive run missing a required `SOCOOL_*` var | The error line names the var — set it in `.env` or pass `--<flag>` |
| `70–79` | smoke tests | post-boot health probe failed | Named per VM; see [`tests/smoke/probes/`](../tests/smoke/probes/) |

## Common failure modes

### Windows Hyper-V conflict

**Symptom:** `setup.ps1` exits `30` with

> VirtualBox on Windows conflicts with: Hyper-V, WSL2, Docker Desktop.

**Why:** VirtualBox 7.1+ *can* co-run with Hyper-V via WHPX, but
performance drops up to 20×, and VirtualBox 7.2.4 has a known
Windows-guest crash bug under WHPX. SOCool refuses this config by
default.

**Three supported options:**

1. **Disable Hyper-V** (breaks WSL2 and Docker Desktop until
   re-enabled):
   ```
   bcdedit /set hypervisorlaunchtype off   # as Administrator
   shutdown /r /t 0
   ```
2. **Move SOCool to a Linux host** (recommended if you want nested
   virt for the scanner workload).
3. **Wait for a future SOCool release** with Hyper-V-native support
   (not currently on the roadmap).

We deliberately do **not** auto-disable Hyper-V; that would silently
break other tooling the user depends on. See
[ADR-0002](./adr/0002-hypervisor-matrix.md) for the full rationale.

### macOS `bash` 3.2

**Symptom:** `./setup.sh` exits 17 with

> setup.sh requires bash >= 4.0; detected 3.2 at /bin/bash.

**Why:** macOS ships Bash 3.2 for GPLv2 licensing reasons. Our
scripts need Bash 4+ for features like `BASH_VERSINFO[0] < 4` checks
themselves and some `read` flags.

**Fix:** install Homebrew's bash and re-run under it:

```bash
brew install bash
/opt/homebrew/bin/bash ./setup.sh     # Apple Silicon
/usr/local/bin/bash ./setup.sh        # Intel
```

The system `/bin/bash` is intentionally left alone.

### HashiCorp apt/dnf repo

**Symptom:** `setup.sh` exits 21 with an apt/dnf refusal message.

**Why:** SOCool does **not** auto-configure HashiCorp's third-party
package repository because that requires importing a new GPG key and
modifying `/etc/apt/sources.list.d/` — decisions the user should make
consciously. See
[`scripts/lib/deps.sh::_hashicorp_repo_refusal_message`](../scripts/lib/deps.sh)
for the rationale.

**Fix:** follow the commands in the error message. Abbreviated:

```bash
# Ubuntu / Debian
wget -O- https://apt.releases.hashicorp.com/gpg | \
    sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
    sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt-get update && sudo apt-get install -y packer vagrant

# Fedora / RHEL
sudo dnf install -y dnf-plugins-core
sudo dnf config-manager addrepo --from-repofile=https://rpm.releases.hashicorp.com/fedora/hashicorp.repo
sudo dnf install -y packer vagrant
```

Re-run `setup.sh` after.

### Network CIDR collision

**Symptom:** `check-network-cidr` exits 18 with

> lab CIDR conflicts with an existing host network.

**Why:** Your host already has a route in `10.42.10.0/24`,
`10.42.20.0/24`, or `198.18.0.0/24`. Commonly this is a VPN or
another Vagrant lab on the same host.

**Fix:** pick one of

- Disconnect the conflicting interface (VPN / other lab).
- Edit `config/lab.yml` to use different CIDRs. The parity + topology
  docs have to move with it — see
  [`docs/network-topology.md`](./network-topology.md) on that.

### Preflight isn't enforcing

**Symptom:** `setup.sh` prints

> [WARN] no preflight checks installed (scripts/preflight/checks/ is empty; Step 4 pending)

**Why:** you're on a branch before Step 4 landed, or the checks
directory has been emptied.

**Fix:** check that `ls scripts/preflight/checks/*.sh` shows 8 files.
If not, `git pull` or restore from `main`. To fail-fast rather than
warn-and-continue in this state, set `SOCOOL_STRICT_PREFLIGHT=1`.

### "I don't know what password to log in with"

Every rotated credential lands in `packer/<vm>/artifacts/credentials.json`
(mode 0600, gitignored). `setup.sh` prints the file path at the end
of a successful run. If you missed that:

```bash
ls packer/*/artifacts/credentials.json
cat packer/kali/artifacts/credentials.json   # adjust VM as needed
```

Never commit these files. See
[`.skills/devsecops/SKILL.md`](../.skills/devsecops/SKILL.md)
and the per-VM runbook under [`docs/runbooks/`](./runbooks/) for the
credentials policy.

## Getting more detail

Add `SOCOOL_LOG_LEVEL=debug` to any run to unlock `log_debug` lines
(host detection, prompt resolutions, env-var reads):

```bash
SOCOOL_LOG_LEVEL=debug ./setup.sh
```

For Packer, set `PACKER_LOG=1`. For Vagrant, `VAGRANT_LOG=debug`.

## Still stuck?

1. Run `bash tests/run-all.sh` — any failure there localises the problem.
2. Open an issue with the `[DEBUG]`-level log and the output of
   `bash scripts/preflight/run-all.sh`.
