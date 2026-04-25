# packer/nessus/ — Nessus Essentials vulnerability scanner

Builds a Vagrant box of Ubuntu 24.04 LTS with Nessus Essentials
(Tenable's free 30-day, 5-IP offering) installed and registered.

## User-supplied inputs

Nessus downloads are **session-gated** at Tenable — the repo cannot
pin a URL, and the activation code is emailed per-user.

| Variable | Source | Required |
|---|---|---|
| `nessus_deb_url` | User signs up at tenable.com/products/nessus/nessus-essentials, downloads Nessus-10.x-debian10_amd64.deb, supplies URL or `file://` path | yes when `SOCOOL_SCANNER=nessus` |
| `nessus_activation_code` | Emailed by Tenable at sign-up; `SOCOOL_NESSUS_ACTIVATION_CODE` env var | yes |

Other inputs follow the project-wide pattern (`hypervisor`, `output_dir`,
`box_version`, `ubuntu_release`, `cpus`, `ram_mb`, `disk_gb`).

## Outputs

- `<output_dir>/socool-nessus-<box_version>.box`
- `./artifacts/credentials.json` — rotated `vagrant` + web-UI `admin`
- `./artifacts/manifest.json`

## Build story

1. Ubuntu 24.04 autoinstall as in `packer/wazuh/`.
2. Post-install `install-nessus.sh` — pulls the .deb (HTTPS or
   `file://`), `dpkg -i`, starts `nessusd`, runs
   `nessuscli fetch --register <code>`.
3. `rotate-credentials.sh` — CSPRNG passwords for `vagrant` and
   Nessus web UI `admin` (created via `nessuscli adduser`).
4. `cleanup.sh` — standard Ubuntu image shrink.
5. `vagrant` post-processor packages.

## Known gotchas

- **Activation code is single-use.** Re-installing Nessus on the same
  box requires a new code from Tenable.
- **Plugin download happens in the background** after first boot and
  can take 20–60 minutes. The web UI at `https://10.42.20.20:8834/`
  will be slow during that window.
- **Tenable's .deb URL** rotates — if the user runs this months later
  their URL may have expired. They need to log into their Tenable
  account and fetch a fresh URL.
- **`nessuscli adduser`** accepts password input differently across
  Nessus versions. The script tries two forms and falls through to
  first-boot rotation if both fail.
- **Not validated E2E** — requires a real Tenable account to test.

## References

- [Tenable Nessus install on Linux (docs)](https://docs.tenable.com/nessus/Content/InstallNessusLinux.htm)
- [Nessus Essentials landing page](https://www.tenable.com/products/nessus/nessus-essentials)
- [nessuscli command reference](https://docs.tenable.com/nessus/Content/NessusCLI.htm)
