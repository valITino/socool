# packer/windows-victim/ — Windows 11 Enterprise Evaluation victim

Builds a Vagrant box of Windows 11 Enterprise Evaluation (90-day, no
product key required). The Wazuh agent is installed and pre-enrolled
pointing at the Wazuh manager VM at `10.42.20.10`.

## Inputs

| Variable | Default | Meaning |
|---|---|---|
| `hypervisor` | (required) | `virtualbox` or `libvirt` |
| `output_dir` | (required) | where the `.box` is written |
| `iso_cache_dir` | `""` | ISO cache |
| `box_version` | `0.1.0` | stamped into box name |
| `windows_iso_url` | **(required)** | URL or `file://` path to the Windows 11 Enterprise Evaluation ISO (session-gated at Microsoft Evaluation Center — user supplies) |
| `windows_iso_checksum` | `"none"` | Packer `iso_checksum` value (`file:...`, `sha256:...`, or `none`) |
| `cpus` | `2` | matches `lab.yml` |
| `ram_mb` | `4096` | matches `lab.yml` |
| `disk_gb` | `60` | matches `lab.yml` |
| `wazuh_manager_ip` | `10.42.20.10` | passed into the Wazuh agent install |
| `virtio_win_iso_path` | `""` | libvirt only: path to Fedora virtio-win ISO for drivers |
| `ovmf_code_path` | `/usr/share/OVMF/OVMF_CODE.fd` | libvirt only: UEFI firmware path |

## Outputs

- `<output_dir>/socool-windows-victim-<box_version>.box`
- `./artifacts/credentials.json` — rotated `vagrant` local-admin password
- `./artifacts/manifest.json`

## User-supplied inputs

The Microsoft Evaluation Center URLs are **session-gated** — Microsoft
generates a fresh URL per download session and the URLs rotate, so the
repo cannot ship a static URL. Two supported paths:

**Option A: user downloads to disk, Packer reads from `file://`.**
```
setup.sh --windows-source=iso --windows-iso /abs/path/to/Win11_Enterprise_Eval.iso
# setup.sh then runs Packer with:
#   -var="windows_iso_url=file:///abs/path/to/Win11_Enterprise_Eval.iso"
#   -var="windows_iso_checksum=none"
```

**Option B: user provides a URL they already have.**
```
SOCOOL_WINDOWS_ISO_URL="https://.../Win11_Enterprise_Eval.iso" \
SOCOOL_WINDOWS_ISO_CHECKSUM="sha256:<published-hash>" \
./setup.sh --windows-source eval
```

`checksum=none` is only safe when the user has already verified the
ISO integrity themselves (e.g., via the Evaluation Center download
page's published hash).

## Build story

1. `autounattend.xml` + `setup-winrm.ps1` are attached as a virtual
   CD labelled `CIDATA`; Windows Setup finds the answer file there.
2. Setup partitions the disk (UEFI + MSR + NTFS), installs Windows 11
   Enterprise Evaluation (Image index 1 — verify with
   `dism /Get-ImageInfo /ImageFile:install.wim` on the Eval ISO),
   creates the local `vagrant` admin account with the BUILD-ONLY
   password, enables autologon once.
3. At first logon, `setup-winrm.ps1` enables WinRM over HTTP with
   basic auth — safe because this is a throwaway Packer build with a
   NAT-only network; the cleanup step reverts these settings before
   packaging.
4. Packer connects over WinRM and runs three provisioners:
   - `install-wazuh-agent.ps1` — MSI-installs Wazuh 4.14.4 agent,
     enrols pointing at `SOCOOL_WAZUH_MANAGER_IP`.
   - `rotate-credentials.ps1` — rotates the `vagrant` password with
     `RandomNumberGenerator`, disables autologon, writes the manifest.
   - `cleanup.ps1` — disables WinRM unencrypted basic, clears
     Windows Update cache + temp + prefetch, zero-fills free disk
     with `cipher /w:C:\`.
5. Packer `file` provisioner pulls the manifest. `vagrant`
   post-processor packages the `.box`.

## Known gotchas

- **TPM / SecureBoot bypass** — `autounattend.xml` sets the
  `HKLM\SYSTEM\Setup\LabConfig` bypass flags. The Packer sources
  also attach a virtual TPM 2.0 + EFI, so both paths are open. If
  Setup complains about `BypassCPUCheck` requirement, add that
  registry setting to `RunSynchronous` as well.
- **Image edition index** — our `ImageInstall/MetaData/Key = /IMAGE/INDEX, Value = 1`
  picks the first WIM image. The Evaluation Center ISO has historically
  shipped Enterprise Evaluation as index 1, but verify with
  `dism /Get-WimInfo` per release.
- **Wazuh agent enrolment** will fail until the Wazuh manager VM
  is up. That's fine — the agent service retries indefinitely.
- **WinRM tightening** in cleanup may fail in unusual configurations
  (Group Policy overrides, domain join). A try/catch allows the
  build to continue; Vagrant re-asserts its own WinRM config on
  first `vagrant up`.
- **libvirt/QEMU path is scaffold-only** — Windows-on-QEMU without
  a virtio-win ISO will run under IDE+e1000 (slow but functional);
  users who want performant libvirt Windows need `virtio_win_iso_path`
  set. End-to-end libvirt Windows build has not been validated in
  this session.
