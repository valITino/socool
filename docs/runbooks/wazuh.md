# Runbook — wazuh

The SIEM. Ubuntu 24.04 LTS with Wazuh 4.14 in the
assisted-all-in-one topology: Wazuh server + indexer (OpenSearch) +
dashboard, all on one VM. On `socool-management`.

## At-a-glance

| Field | Value |
|---|---|
| Hostname | `wazuh` |
| Role | `siem` |
| OS | Ubuntu Server 24.04 LTS |
| IP | `10.42.20.10` on `socool-management` |
| Sizing | 4 vCPU, 8192 MB RAM, 60 GB disk |
| Boot order | 30 |
| Optional? | no |
| Build template | [`packer/wazuh/`](../../packer/wazuh/) |

## How to reach it

| Method | Target | Notes |
|---|---|---|
| Wazuh dashboard | `https://10.42.20.10/` | HTTPS with self-signed cert; username `admin`, password in `credentials.json`. |
| Indexer API | `https://10.42.20.10:9200/` | OpenSearch. Username `admin`, same password as dashboard. |
| Wazuh API | `https://10.42.20.10:55000/` | For agent enrolment and rules management. User `wazuh`; see credential notes below. |
| SSH | `ssh vagrant@10.42.20.10` | Rotated password in credentials file. |
| Vagrant | `vagrant ssh wazuh` | |

## Default credentials policy

Rotated by
[`scripts/rotate-credentials.sh`](../../packer/wazuh/scripts/rotate-credentials.sh):

| Account | Where | Rotated at build? | Notes |
|---|---|---|---|
| `vagrant` | Linux (SSH + sudo) | yes | |
| `admin` | dashboard + indexer | yes (in-band when `wazuh-passwords-tool.sh` is present) | |
| `kibanaserver` | dashboard ↔ indexer internal | yes (in-band) | Never needed interactively; the dashboard uses it behind the scenes. |
| `wazuh` | Wazuh API | **generated but NOT applied on disk** | The Wazuh API does not hash the default user password at install time, so the rotation has to happen via the API after first boot. The manifest records the generated value. |

All values land in `packer/wazuh/artifacts/credentials.json` (gitignored, 0600).

## Apply the Wazuh API password on first boot

After first `vagrant up`, POST the rotated value to the Wazuh API.
The Wazuh package ships with a documented bootstrap username/password
(both literally `wazuh`) — we use it once below to rotate it, then it
stops working. Treat that bootstrap pair as a placeholder, not a
secret:

```bash
# One-time bootstrap pair shipped by the Wazuh package — public,
# documented, and immediately rotated below.
WAZUH_BOOTSTRAP_USER='wazuh'
WAZUH_BOOTSTRAP_PASS='wazuh'

NEW_PASS="$(jq -r '.accounts[] | select(.scope | startswith("Wazuh API")) | .password' \
           packer/wazuh/artifacts/credentials.json)"

curl -k -u "${WAZUH_BOOTSTRAP_USER}:${WAZUH_BOOTSTRAP_PASS}" -X PUT \
    "https://10.42.20.10:55000/security/users/1" \
    -H 'Content-Type: application/json' \
    -d "{\"password\": \"${NEW_PASS}\"}"
```

After this, the bootstrap pair stops working.

## How to reach agents

- **Windows victim** enrols automatically at build time (see its
  runbook). Confirm in the dashboard → *Agents* → should appear as
  `windows-victim` with status `active` once the manager is online.
- To add more agents by hand:
  ```bash
  # on a new endpoint:
  curl -sO https://packages.wazuh.com/4.x/linux/wazuh-agent-4.14.4-1_amd64.deb
  sudo WAZUH_MANAGER='10.42.20.10' dpkg -i ./wazuh-agent-*.deb
  sudo systemctl enable --now wazuh-agent
  ```

## How to reset it

```bash
cd vagrant
vagrant destroy -f wazuh
rm packer/wazuh/artifacts/credentials.json
rm .socool-cache/boxes/socool-wazuh-*.box
./setup.sh
```

To wipe just the indexed alerts (keep the agent enrolments):

```bash
vagrant ssh wazuh -c 'sudo systemctl stop wazuh-indexer && sudo rm -rf /var/lib/wazuh-indexer/nodes/0/indices/* && sudo systemctl start wazuh-indexer'
```

## Known gotchas

- **`wazuh-install.sh -a -i` takes 15–30 minutes.** The Packer
  build is slow. Use `SOCOOL_BOX_OUTPUT_DIR` pointing at an SSD
  and expect a one-time hit.
- **First-boot feed sync.** The indexer pulls vulnerability feeds
  on first boot; the dashboard is responsive after ~5 minutes but
  alert detail grows for 30–60 minutes.
- **Image is RAM-hungry.** OpenSearch alone wants ~2 GB. The 8 GB
  sizing in `config/lab.yml` is comfortable but not generous; do
  not reduce below 6 GB.
- **Subiquity autoinstall,** not preseed. Ubuntu 24.04 dropped
  preseed support in the installer; the template uses
  cloud-init `user-data` per the current Subiquity reference.

## References

- [`packer/wazuh/README.md`](../../packer/wazuh/README.md)
- [Wazuh quickstart](https://documentation.wazuh.com/current/quickstart.html)
- [Wazuh all-in-one installation](https://documentation.wazuh.com/current/installation-guide/wazuh-server/installation-assistant.html)
- [Wazuh API reference](https://documentation.wazuh.com/current/user-manual/api/reference.html)
