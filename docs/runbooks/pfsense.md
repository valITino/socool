# Runbook — pfsense

The lab's firewall + router. Three interfaces spanning `wan-sim`,
`lan`, `management`. Default-deny WAN, LAN → management blocked,
management egress allowed. webConfigurator bound to the management
interface only.

## At-a-glance

| Field | Value |
|---|---|
| Hostname | `pfsense` |
| Role | `firewall` |
| OS | pfSense CE 2.7.2 (FreeBSD 14-based) |
| IPs | `wan: 198.18.0.1`, `lan: 10.42.10.1`, `management: 10.42.20.1` |
| Sizing | 1 vCPU, 1024 MB RAM, 8 GB disk |
| Boot order | 0 (first) |
| Optional? | no |
| Build template | [`packer/pfsense/`](../../packer/pfsense/) |

## How to reach it

| Method | Target | Notes |
|---|---|---|
| webConfigurator | `https://10.42.20.1/` | HTTPS with pfSense's self-signed cert; accept in your browser. Reachable from the host; **not** reachable from Kali (rule #2). |
| SSH | `ssh root@10.42.20.1` | User `root`, rotated password in `packer/pfsense/artifacts/credentials.json`. |
| Console | `vagrant ssh pfsense` (from `vagrant/`) | FreeBSD `csh`. |

## Default credentials policy

Two accounts are rotated during the Packer build by
[`scripts/rotate-credentials.sh`](../../packer/pfsense/scripts/rotate-credentials.sh):

- `root` — used for SSH + console.
- `admin` — used for the webConfigurator at `https://10.42.20.1/`.

Both are CSPRNG-generated (24 base64-ish characters) and written to
`packer/pfsense/artifacts/credentials.json` (mode 0600, gitignored).
**Never commit this file.** Never paste its contents into issues.

The upstream pfSense defaults (`root:pfsense`, `admin:pfsense`) are
overwritten during build and are not valid on a shipped box.

## How to reset it

```bash
cd vagrant
vagrant destroy -f pfsense
# Rebuild the box from scratch (fresh rotated creds):
rm packer/pfsense/artifacts/credentials.json
rm .socool-cache/boxes/socool-pfsense-*.box
./setup.sh         # rebuilds pfSense, then brings up the lab
```

Quick factory-reset of rules without rebuilding the box: shell into
pfSense and run `/etc/rc.factory-reset` — this restores the seeded
`config.xml` but keeps the rotated credentials.

## Known gotchas

- **WAN DHCP from Vagrant NAT.** pfSense's WAN interface is
  Vagrant's NIC 0 (NAT), so it gets a 10.0.2.x-ish address from the
  hypervisor rather than a 198.18.0.x address. This is fine — the
  `wan-sim` CIDR in `config/lab.yml` is the conceptual label for
  that segment; the actual WAN IP is handed out by the hypervisor's
  NAT.
- **Rule #2 is the isolation guarantee.** `lan → management` is
  blocked — that's what keeps an attacker on Kali from pivoting
  straight into Wazuh. If you find yourself needing to test
  cross-subnet traffic, add a *specific, logged* rule rather than
  disabling rule #2.
- **Config.xml schema version.** The seed file claims `<version>21.7</version>`
  which pfSense 2.7.x accepts. If you hand-edit the seed for a newer
  release, bump to the matching schema version or pfSense will
  migrate noisily on first boot.
- **bsdinstall `boot_command` timing.** The Packer template drives
  bsdinstall via VNC keystrokes; the `<wait30s>` values were tuned
  on a specific host. Expect to adjust for your build host.

## References

- [`packer/pfsense/README.md`](../../packer/pfsense/README.md) — build details.
- [`packer/pfsense/http/config-seed.xml`](../../packer/pfsense/http/config-seed.xml) — the seeded configuration.
- [pfSense XML Configuration File](https://docs.netgate.com/pfsense/en/latest/config/xml-configuration-file.html)
- [`docs/network-topology.md`](../network-topology.md) — where pfSense fits.
