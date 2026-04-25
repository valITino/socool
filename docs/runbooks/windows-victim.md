# Runbook — windows-victim

The target endpoint. Windows 11 Enterprise Evaluation with the
Wazuh agent pre-enrolled pointing at the Wazuh manager VM.

## At-a-glance

| Field | Value |
|---|---|
| Hostname | `windows-victim` |
| Role | `victim` |
| OS | Windows 11 Enterprise Evaluation (90-day eval, no key) |
| IP | `10.42.10.20` on `socool-lan` |
| Sizing | 2 vCPU, 4096 MB RAM, 60 GB disk |
| Boot order | 20 |
| Optional? | no |
| Build template | [`packer/windows-victim/`](../../packer/windows-victim/) |

## User-supplied inputs

Microsoft rotates Evaluation Center URLs per session; the repo
cannot pin one. Either:

- **URL form** — paste the Evaluation Center download URL into
  `SOCOOL_WINDOWS_ISO_URL` and optionally
  `SOCOOL_WINDOWS_ISO_CHECKSUM`.
- **Local path** — pre-download the ISO, run
  `./setup.sh --windows-source iso --windows-iso /abs/path/Win11_Eval.iso`.

Without one of those, the Packer build for `windows-victim` exits
`40` with the diagnostic message.

## How to reach it

| Method | Target | Notes |
|---|---|---|
| RDP | `10.42.10.20:3389` | From the host. Credentials in `credentials.json`. |
| WinRM | `5985` (http) or `5986` (https) | Only until Vagrant re-establishes its own WinRM config. Cleanup.ps1 disables unencrypted basic auth. |
| Vagrant | `vagrant ssh windows-victim` | Only works if OpenSSH Server was enabled; otherwise use `vagrant winrm` subcommand. |

## Default credentials policy

One account rotated during Packer build by
[`scripts/rotate-credentials.ps1`](../../packer/windows-victim/scripts/rotate-credentials.ps1):

- `vagrant` (local Administrator) — CSPRNG via
  `System.Security.Cryptography.RandomNumberGenerator` (NOT
  `Get-Random`, which is a PRNG — banned by
  [`.skills/devsecops/`](../../.skills/devsecops/SKILL.md)).

Credentials file: `packer/windows-victim/artifacts/credentials.json`
(gitignored, mode 0600).

Autologon is enabled at first logon (for Packer's provisioner
session only) and disabled by `rotate-credentials.ps1` before the
box is packaged. A shipped box never autologons.

## Wazuh agent

The agent is installed and enrolled at build time pointing at the
Wazuh manager IP (`10.42.20.10` by default, overridable via
`SOCOOL_WAZUH_MANAGER_IP`). The `WazuhSvc` service is set to
Automatic start. It retries enrolment indefinitely, so the agent
comes online once the Wazuh manager VM is up — even if the Windows
VM boots first.

## How to reset it

```bash
cd vagrant
vagrant destroy -f windows-victim
rm packer/windows-victim/artifacts/credentials.json
rm .socool-cache/boxes/socool-windows-victim-*.box
./setup.sh
```

To re-enrol the Wazuh agent without rebuilding:

```powershell
# inside the VM
Restart-Service WazuhSvc
```

## Known gotchas

- **TPM / SecureBoot bypasses.** The autounattend.xml sets
  `BypassTPMCheck`, `BypassSecureBootCheck`, `BypassRAMCheck` in
  `HKLM\SYSTEM\Setup\LabConfig`, and the Packer source attaches a
  virtual TPM 2.0 + EFI firmware. If Setup still refuses the image
  on your host, add `BypassCPUCheck` to the `RunSynchronous` block.
- **Image index.** The autounattend.xml selects `/IMAGE/INDEX = 1`
  from the Evaluation Center ISO's `install.wim`. Historically
  this is Enterprise Evaluation, but Microsoft occasionally
  reorders. Verify with
  `dism /Get-WimInfo /WimFile:<mount>\sources\install.wim`.
- **libvirt / QEMU path is scaffold-only.** Without a
  `virtio_win_iso_path`, Windows on QEMU runs with IDE + e1000
  drivers — slow but functional. End-to-end libvirt Windows
  builds have not been tuned in this release.
- **WinRM is relaxed during the build.** `setup-winrm.ps1` enables
  unencrypted basic auth so Packer can connect; `cleanup.ps1`
  disables those switches before packaging. Vagrant re-asserts
  its own WinRM config on first `vagrant up`.

## References

- [`packer/windows-victim/README.md`](../../packer/windows-victim/README.md)
- [`packer/windows-victim/http/autounattend.xml`](../../packer/windows-victim/http/autounattend.xml)
- [Microsoft Windows 11 Enterprise Evaluation](https://www.microsoft.com/en-us/evalcenter/evaluate-windows-11-enterprise)
- [Wazuh agent — Windows packages](https://documentation.wazuh.com/current/installation-guide/wazuh-agent/wazuh-agent-package-windows.html)
