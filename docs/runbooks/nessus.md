# Runbook — nessus

Optional vulnerability scanner. Tenable Nessus Essentials (free,
30-day license, 5-IP limit). Mutually exclusive with `openvas` —
only one scanner VM runs per lab.

## At-a-glance

| Field | Value |
|---|---|
| Hostname | `nessus` |
| Role | `scanner` |
| OS | Ubuntu Server 24.04 LTS |
| IP | `10.42.20.20` on `socool-management` |
| Sizing | 2 vCPU, 4096 MB RAM, 40 GB disk |
| Boot order | 40 |
| Optional? | **yes** — activates only when `SOCOOL_SCANNER=nessus` |
| Build template | [`packer/nessus/`](../../packer/nessus/) |

## User-supplied inputs

Nessus downloads are session-gated by Tenable; the activation code
is emailed per-user. Both required when `SOCOOL_SCANNER=nessus`:

| Env var | Where to get it |
|---|---|
| `SOCOOL_NESSUS_DEB_URL` | [Tenable.com download](https://www.tenable.com/products/nessus/nessus-essentials) — sign up, grab the `Nessus-*-debian10_amd64.deb` URL. `file://` paths accepted for a pre-downloaded copy. |
| `SOCOOL_NESSUS_ACTIVATION_CODE` | Emailed by Tenable on sign-up. |

Without both, Packer exits `40` with a specific diagnostic.

## How to reach it

| Method | Target | Notes |
|---|---|---|
| Nessus web UI | `https://10.42.20.20:8834/` | HTTPS with self-signed cert; admin creds in `credentials.json`. |
| SSH | `ssh vagrant@10.42.20.20` | |
| Vagrant | `vagrant ssh nessus` | |

## Default credentials policy

Rotated by
[`scripts/rotate-credentials.sh`](../../packer/nessus/scripts/rotate-credentials.sh):

- `vagrant` — Linux SSH, CSPRNG.
- `admin` — Nessus web UI, CSPRNG (created via `nessuscli adduser`).

Both in `packer/nessus/artifacts/credentials.json` (gitignored, 0600).

The activation code itself is **also** stored in the manifest (not
the passwords — the Tenable code). Treat the file accordingly.

## How the activation code flows

```
.env                         → setup.sh reads SOCOOL_NESSUS_ACTIVATION_CODE
setup.sh                     → passes as env to run-pipeline.sh
run-pipeline.sh              → -var="nessus_activation_code=..." to packer
packer template              → exposes to provisioner env as
                               SOCOOL_NESSUS_ACTIVATION_CODE
install-nessus.sh (on guest) → /opt/nessus/sbin/nessuscli fetch
                               --register "${SOCOOL_NESSUS_ACTIVATION_CODE}"
```

The code is **single-use**. A destroy-rebuild cycle needs a fresh
code from Tenable.

## How to reset it

```bash
cd vagrant
vagrant destroy -f nessus
rm packer/nessus/artifacts/credentials.json
rm .socool-cache/boxes/socool-nessus-*.box
# Get a fresh activation code from Tenable first, then:
export SOCOOL_NESSUS_ACTIVATION_CODE="new-code-here"
./setup.sh --scanner nessus
```

To swap from Nessus to OpenVAS:

```bash
cd vagrant
vagrant destroy -f nessus
./setup.sh --scanner openvas
```

## Known gotchas

- **Plugin download is slow.** After first boot, Nessus pulls ~2 GB
  of vulnerability plugins in the background. The web UI is slow
  for 20–60 minutes. Wait it out before reporting a bug.
- **Single-use activation code.** Do not destroy-rebuild casually —
  you burn a code each time.
- **5-IP limit.** Nessus Essentials is licensed for 5 IPs. Our lab
  has 3 non-scanner VMs — comfortably under. If you add more
  victims, you'll need to upgrade Tenable tier.
- **Tenable download URL rotates.** If you try re-running months
  later with a cached URL, it will 404. Grab a fresh one.
- **`nessuscli adduser`** accepts password stdin differently across
  Nessus versions. The script tries two forms and falls through to
  a first-boot rotation if both fail. Check `credentials.json`'s
  `notes` if the admin password isn't working.

## References

- [`packer/nessus/README.md`](../../packer/nessus/README.md)
- [Tenable Nessus Linux install](https://docs.tenable.com/nessus/Content/InstallNessusLinux.htm)
- [Nessus Essentials landing page](https://www.tenable.com/products/nessus/nessus-essentials)
- [nessuscli reference](https://docs.tenable.com/nessus/Content/NessusCLI.htm)
