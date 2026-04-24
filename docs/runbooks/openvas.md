# Runbook — openvas

Optional vulnerability scanner. Greenbone Community Edition
("OpenVAS") via the official Greenbone Community Containers
docker-compose stack. Mutually exclusive with `nessus`.

## At-a-glance

| Field | Value |
|---|---|
| Hostname | `openvas` |
| Role | `scanner` |
| OS | Ubuntu Server 24.04 LTS + Docker CE + Greenbone containers |
| IP | `10.42.20.20` on `socool-management` (same slot as Nessus; they can't coexist) |
| Sizing | 2 vCPU, 4096 MB RAM, 40 GB disk |
| Boot order | 40 |
| Optional? | **yes** — activates only when `SOCOOL_SCANNER=openvas` |
| Build template | [`packer/openvas/`](../../packer/openvas/) |

## User-supplied inputs

None beyond `SOCOOL_SCANNER=openvas`. Greenbone's compose manifest
URL is pinned in [`packer/openvas/variables.pkr.hcl`](../../packer/openvas/variables.pkr.hcl);
override with `-var` if a newer major version is out.

## How to reach it

| Method | Target | Notes |
|---|---|---|
| Greenbone web UI | `https://10.42.20.20/` | HTTPS with self-signed cert; user `admin`, password in `credentials.json`. |
| SSH | `ssh vagrant@10.42.20.20` | |
| Vagrant | `vagrant ssh openvas` | |
| Container shell | `vagrant ssh openvas -c 'docker compose -f /opt/greenbone/docker-compose.yml exec gvmd bash'` | For `gvmd` CLI access. |

## Default credentials policy

Rotated by
[`scripts/rotate-credentials.sh`](../../packer/openvas/scripts/rotate-credentials.sh):

- `vagrant` — Linux SSH, CSPRNG — rotated in-band during the Packer
  build.
- `admin` — Greenbone web UI, CSPRNG — **staged** in
  `/etc/socool/greenbone-admin.env` at build time; applied at
  **first boot** by `socool-greenbone-firstboot.service`, which
  waits for the `gvmd` container to come up and then runs
  `gvmd --new-password`.

Both values land in `packer/openvas/artifacts/credentials.json`
(gitignored, 0600).

## How the admin password actually gets applied

The compose stack creates the initial `admin` user with an
install-time default. `gvmd --new-password` has to run **inside**
the `gvmd` container **after** `gvmd` starts. The systemd unit
installed by the rotation script handles this:

```
socool-greenbone.service            ← brings the stack up
socool-greenbone-firstboot.service  ← waits up to 5 min for gvmd,
                                      then applies the staged password,
                                      touches /var/lib/socool/greenbone-firstboot.done
```

On subsequent boots the `ConditionPathExists=!` guard skips the
firstboot unit.

If firstboot fails (log in to the VM, `journalctl -u socool-greenbone-firstboot`),
apply manually:

```bash
source /etc/socool/greenbone-admin.env
docker compose -f /opt/greenbone/docker-compose.yml exec -T gvmd \
    gvmd --user="${GREENBONE_ADMIN_USER}" --new-password="${GREENBONE_ADMIN_PASS}"
```

## How to reset it

```bash
cd vagrant
vagrant destroy -f openvas
rm packer/openvas/artifacts/credentials.json
rm .socool-cache/boxes/socool-openvas-*.box
./setup.sh --scanner openvas
```

Soft reset (redo first-boot rotation without rebuilding):

```bash
vagrant ssh openvas -c 'sudo rm -f /var/lib/socool/greenbone-firstboot.done && sudo systemctl restart socool-greenbone-firstboot'
```

## Known gotchas

- **NVT feed sync at first boot is slow** — Greenbone pulls ~3 GB
  of feeds. The UI is responsive after ~5 minutes but scan
  coverage grows for 30–90 minutes.
- **docker-compose v2 plugin**, not the legacy standalone binary.
  Invocation is `docker compose` (space), not `docker-compose`
  (dash). All of our scripts use the space form.
- **Compose manifest is pinned to a major version.** Newer major
  releases (e.g., 23.x) change service names and command flags;
  re-verify before bumping `greenbone_compose_url`.
- **First-boot password window.** Until firstboot's unit runs, the
  `admin` password is the upstream Greenbone default. That's the
  2–5 minute window between `vagrant up` and the unit completing;
  the VM is not network-reachable from outside the lab during that
  window anyway (host-only network), so the exposure is bounded.

## References

- [`packer/openvas/README.md`](../../packer/openvas/README.md)
- [Greenbone Community Documentation](https://greenbone.github.io/docs/latest/)
- [Greenbone Community Containers](https://greenbone.github.io/docs/latest/22.4/container/index.html)
- [`gvmd` user/password reset](https://greenbone.github.io/docs/latest/22.4/troubleshooting/user-password-reset.html)
