# packer/wazuh/ — Wazuh all-in-one SIEM

Builds a Vagrant box of Ubuntu 24.04 LTS with Wazuh 4.14 (manager,
indexer, dashboard) installed via `wazuh-install.sh -a`. The all-in-
one topology supports up to 100 endpoints and 90 days of indexed
alerts, matching the lab's needs comfortably.

## Inputs

| Variable | Default | Meaning |
|---|---|---|
| `hypervisor` | (required) | `virtualbox` or `libvirt` |
| `output_dir` | (required) | where the `.box` is written |
| `iso_cache_dir` | `""` | ISO cache |
| `box_version` | `0.1.0` | stamped into box name |
| `ubuntu_release` | `24.04.1` | Ubuntu Server LTS point release |
| `wazuh_version` | `4.14` | major.minor line; installer pulls latest |
| `cpus` | `4` | matches `lab.yml` |
| `ram_mb` | `8192` | matches `lab.yml` |
| `disk_gb` | `60` | matches `lab.yml` |

## Outputs

- `<output_dir>/socool-wazuh-<box_version>.box`
- `./artifacts/credentials.json` — rotated `vagrant`, dashboard `admin`,
  indexer `kibanaserver`, and pending Wazuh API `wazuh` password
- `./artifacts/manifest.json`

## Build story

1. Packer downloads the Ubuntu 24.04 Live Server ISO, verifies via
   the publisher's `SHA256SUMS`.
2. Boots the ISO with `autoinstall 'ds=nocloud-net;s=http://...'`
   which points Subiquity at Packer's HTTP server; it reads
   `user-data` + `meta-data` there.
3. Subiquity runs unattended — LVM root, vagrant user with
   BUILD-ONLY password, SSH enabled, insecure Vagrant key authorized.
4. Post-install provisioners run as root:
   - `vagrant-user.sh` — re-assert sudoers + SSH config.
   - `install-wazuh.sh` — download `wazuh-install.sh` and run
     `-a -i` for all-in-one. Installer takes ~15–30 minutes.
   - `rotate-credentials.sh` — generates CSPRNG passwords for
     vagrant, admin, kibanaserver, and wazuh-api (API rotation
     deferred to first boot — see Known gotchas).
   - `cleanup.sh` — trim apt cache, scrub machine-id + SSH host
     keys (regenerated on first boot), zero free space.
5. Packer pulls `credentials.json`; `vagrant` post-processor packs.

## Known gotchas

- **Wazuh API password rotation happens at first boot**, not here.
  `wazuh-install.sh` does not expose a pre-start API-rotation hook.
  The generated value is recorded in `credentials.json` so
  `docs/runbooks/wazuh.md` can tell the operator to POST it to
  `/security/users` via the API on first login.
- **Subiquity autoinstall** does NOT accept preseed — the template
  deliberately uses the cloud-init `user-data` format. If you try to
  apply a preseed here, Subiquity will log the file and proceed
  with defaults.
- **`refresh-installer: update: no`** keeps the image deterministic.
  Change to `yes` for production mirrors with a snapshot mirror URL.
- **Image is large** — Wazuh indexer (OpenSearch) + dashboard
  (OpenSearch Dashboards) + manager total ~2 GB installed; the
  shipped box is ~4 GB after compression.
- **Not yet validated E2E** in this session; first build iteration
  needed to tune the Subiquity boot command timings and confirm
  `wazuh-install.sh -a -i` completes on a host with 8 GB RAM.

## References

- [Wazuh quickstart](https://documentation.wazuh.com/current/quickstart.html)
- [Installation assistant](https://documentation.wazuh.com/current/installation-guide/wazuh-server/installation-assistant.html)
- [Subiquity autoinstall reference](https://canonical-subiquity.readthedocs-hosted.com/en/latest/reference/autoinstall-reference.html)
- [Ubuntu Server Autoinstall docs](https://ubuntu.com/server/docs/install/autoinstall)
