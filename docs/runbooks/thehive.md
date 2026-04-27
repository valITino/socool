# Runbook — thehive

The case-management / SOAR surface. Ubuntu 24.04 LTS hosting the
StrangeBee `prod1-thehive` Docker Compose stack: Cassandra +
Elasticsearch + TheHive 5 Community + Nginx, all on one VM. Sits on
`socool-management` next to Wazuh — the analyst pipeline is
*Wazuh detects → analyst opens a case in TheHive*.

## At-a-glance

| Field | Value |
|---|---|
| Hostname | `thehive` |
| Role | `soar` |
| OS | Ubuntu Server 24.04 LTS |
| IP | `10.42.20.30` on `socool-management` |
| Sizing | 4 vCPU, 8192 MB RAM, 60 GB disk |
| Boot order | 35 |
| Optional? | no |
| Build template | [`packer/thehive/`](../../packer/thehive/) |

## How to reach it

| Method | Target | Notes |
|---|---|---|
| Web UI (HTTPS) | `https://10.42.20.30/` | Nginx-fronted, self-signed cert. First reachable ~3 minutes after `vagrant up` (Cassandra + Elasticsearch warm-up). |
| Direct API | `http://127.0.0.1:9000/api/v1/` | Inside the VM only — Nginx is the only externally reachable port. |
| SSH | `ssh vagrant@10.42.20.30` | Rotated password in credentials file. |
| Vagrant | `vagrant ssh thehive` | |

## Default credentials policy

Rotated by
[`scripts/rotate-credentials.sh`](../../packer/thehive/scripts/rotate-credentials.sh):

| Account | Where | Rotated at build? | Notes |
|---|---|---|---|
| `vagrant` | Linux (SSH + sudo) | yes | |
| `admin@thehive.local` | TheHive web UI | **generated, applied on first boot** | Cassandra holds the credential; rotation can only happen via TheHive's REST API after the stack is up. `socool-thehive-firstboot.service` polls `/api/v1/status` for up to 10 minutes, then `POST`s the rotated value to `/api/v1/user/<id>/password/set`. |

All values land in `packer/thehive/artifacts/credentials.json` (gitignored, 0600).

## Activate the Community license (one-time, free)

TheHive 5.3+ runs in **read-only** mode without a Community license.
The license is free but per-deployment and not redistributable, so
the Packer build deliberately does **not** bake one in.

1. Sign up at <https://strangebee.com/community/> and request a
   Community license. You will receive a `.lic` file by email.
2. After first login, open *Settings → License* in the TheHive UI.
3. Paste the contents of the `.lic` file and save.

Until you do this, you can navigate the UI and read fixtures, but
case creation and most write operations are blocked.

## Connect Wazuh → TheHive (case automation)

Wazuh ships an integration script at
`/var/ossec/integrations/custom-thehive` that POSTs alerts as
TheHive alerts via the REST API. To wire it up:

1. In TheHive UI, *Organisation → API keys → New key*. Copy it.
2. SSH to the wazuh VM and append to `/var/ossec/etc/ossec.conf`:
   ```xml
   <integration>
     <name>custom-thehive</name>
     <hook_url>http://10.42.20.30:9000/api/v1/alert</hook_url>
     <api_key>PASTE-THE-KEY-HERE</api_key>
     <alert_format>json</alert_format>
     <level>10</level>
   </integration>
   ```
3. `sudo systemctl restart wazuh-manager`.

(Note: the URL points at port 9000 — the direct TheHive listener,
not Nginx — because Wazuh and TheHive share the management subnet
and don't need TLS termination between them.)

## How to reset it

```bash
cd vagrant
vagrant destroy -f thehive
rm packer/thehive/artifacts/credentials.json
rm .socool-cache/boxes/socool-thehive-*.box
./setup.sh
```

To wipe just the case data (keep the Cassandra schema):

```bash
vagrant ssh thehive -c '\
  sudo systemctl stop socool-thehive.service && \
  sudo rm -rf /opt/thehive/cassandra/data /opt/thehive/elasticsearch/data /opt/thehive/thehive/data && \
  sudo systemctl start socool-thehive.service'
```

…then re-apply the Community license via the UI.

## Known gotchas

- **First boot is slow.** ~3 minutes before the Web UI responds —
  Cassandra has to bootstrap its system keyspaces and Elasticsearch
  has to allocate its indices. The smoke probe gives the stack 60
  seconds to respond after the TCP port opens.
- **Heap caps are aggressive.** StrangeBee's defaults assume a
  16 GB host (3 GB heap × 3 services). The Packer build caps each
  at 1 GB so the stack fits in this VM's 8 GB. If you raise the
  VM's RAM in `config/lab.yml`, raise `cassandra_heap_mb` /
  `elasticsearch_heap_mb` / `thehive_heap_mb` in
  `packer/thehive/variables.pkr.hcl` to match.
- **Self-signed cert** on the Nginx that fronts TheHive — your
  browser will warn on first connection.
- **`vm.max_map_count`** is bumped to 262144 inside the VM
  (`/etc/sysctl.d/99-thehive.conf`) — Elasticsearch refuses to
  start otherwise.
- **Compose stack restart** on config change:
  ```bash
  sudo systemctl restart socool-thehive.service
  ```
  …or, for a deeper restart, `cd /opt/thehive && sudo docker compose down && sudo docker compose up -d`.
- **Read-only without a license** — see the license activation
  section above. New deployments hit this immediately.

## References

- [`packer/thehive/README.md`](../../packer/thehive/README.md)
- [TheHive 5 Docker installation](https://docs.strangebee.com/thehive/installation/docker/)
- [StrangeBeeCorp/docker — prod1-thehive profile](https://github.com/StrangeBeeCorp/docker)
- [Community license info](https://docs.strangebee.com/thehive/installation/licenses/about-licenses/)
- [Initial admin login docs](https://docs.strangebee.com/thehive/administration/perform-initial-setup-as-admin/)
- [Wazuh + TheHive integration](https://documentation.wazuh.com/current/proof-of-concept-guide/integration-incident-response.html)
