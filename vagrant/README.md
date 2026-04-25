# vagrant/

Reads [`config/lab.yml`](../config/lab.yml) and brings up each VM with
its networks wired to **host-only private networks** — never bridged
to the user's LAN by default (per
[`CLAUDE.md`](../CLAUDE.md) and
[ADR-0002](../docs/adr/0002-hypervisor-matrix.md)).

## How it's used

`scripts/provision/run-pipeline.*` `cd`s into `vagrant/` and runs:

```
vagrant up --provider virtualbox    # or libvirt
```

once all Packer boxes are present in `SOCOOL_BOX_OUTPUT_DIR`
(default `.socool-cache/boxes/`).

Standalone maintenance ops (same directory):

```
cd vagrant
vagrant status                # what's up / halted / not created
vagrant halt                  # shut down cleanly
vagrant destroy -f            # full teardown
vagrant up kali               # bring up one VM
vagrant ssh pfsense           # into the FreeBSD shell
```

## Environment knobs

| Variable | Default | Effect |
|---|---|---|
| `SOCOOL_SCANNER` | `none` | `nessus` or `openvas` to include that scanner; all others are filtered out at Vagrantfile load time. |
| `SOCOOL_BOX_OUTPUT_DIR` | `<repo>/.socool-cache/boxes` | Where the Vagrantfile looks for local `.box` files (Packer output). |
| `SOCOOL_ALLOW_BRIDGED` | unset | Must be `1` to let a bridged network pass CLAUDE.md's invariant. The Vagrantfile itself never creates bridged NICs — this flag exists so future provisioners can honour it with an audit trail. |

## Network model

Three networks, all host-only / internal. **Host can reach VMs**
(required so the operator can load Wazuh dashboard, pfSense
webConfigurator, Kali SSH, etc.) but the networks are **not bridged
to any physical interface**.

```
  [host] ─┬── VirtualBox NAT (NIC 0 on every VM, for SSH)
          │
          ├── socool-lan (10.42.10.0/24)
          │       pfSense   10.42.10.1   (LAN iface)
          │       kali      10.42.10.10
          │       windows   10.42.10.20
          │
          └── socool-management (10.42.20.0/24)
                  pfSense   10.42.20.1   (MGMT iface)
                  wazuh     10.42.20.10
                  nessus /
                  openvas   10.42.20.20  (mutually exclusive)
```

The `wan_sim` role (198.18.0.0/24) is served by Vagrant's default NAT
NIC on pfSense — the hypervisor gives pfSense outbound Internet through
the host, the way real firewalls see the Internet via their WAN uplink.

## Boot order

Vagrant launches VMs in the order they are declared in the
Vagrantfile. The file sorts `lab.yml`'s `vms[]` by `boot_order` up
front, so pfSense (`boot_order: 0`) is always defined first and
therefore booted first. Client VMs (`boot_order ≥ 10`) follow.

`lab.yml`'s `depends_on` field is not yet consumed here. It's
documented in the schema for a future enhancement that would wait
on SSH reachability on the dependency's primary NIC before starting
the dependant VM. Today, if pfSense takes longer to boot than Kali,
Kali will boot with its default route pointing at a not-yet-ready
gateway — but `dhclient -r && dhclient` at first login fixes it,
and no provisioners run from this layer.

## Files

| File | Purpose |
|---|---|
| `Vagrantfile` | the orchestration logic |
| (gitignored) `.vagrant/` | Vagrant's per-host state (VM IDs, private keys, etc.) |
| (gitignored) local `*.pkrvars.hcl` | per-user overrides (Packer, not Vagrant) |

## Known limitations

- **No cross-VM dependency-wait** — see "Boot order" above. A future
  enhancement (tracked for a later milestone) would implement a wait
  primitive and consume `depends_on`.
- **libvirt storage pool** — `vagrant-libvirt` uses the `default` pool
  unless overridden. If the host's default pool is `/var/lib/libvirt/images`
  and that volume is small, set `LIBVIRT_DEFAULT_URI` and
  `lv.storage_pool_name = "socool"` per
  [`.skills/devops/SKILL.md`](../.skills/devops/SKILL.md) in a
  user-local override.
- **Default gateway on client VMs** — by default each VM keeps two
  NICs (NAT + host-only), which means Kali's default route goes
  through the NAT NIC (directly to Internet) rather than through
  pfSense. The Packer build is where default-route-via-pfSense would
  be applied if you want realistic lab traffic flow; currently the
  scaffolded Packer templates do not set that, so host-only traffic
  goes through pfSense while Internet traffic bypasses it.
