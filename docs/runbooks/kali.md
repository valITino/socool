# Runbook — kali

The attacker workstation. Kali Linux rolling with the standard
`kali-linux-default` tool set, on `socool-lan`.

## At-a-glance

| Field | Value |
|---|---|
| Hostname | `kali` |
| Role | `attacker` |
| OS | Kali Linux (rolling, `2025.3` default) |
| IP | `10.42.10.10` on `socool-lan` |
| Sizing | 2 vCPU, 4096 MB RAM, 40 GB disk |
| Boot order | 10 |
| Optional? | no |
| Build template | [`packer/kali/`](../../packer/kali/) |

## How to reach it

| Method | Target | Notes |
|---|---|---|
| SSH | `ssh vagrant@10.42.10.10` | From the host. Vagrant's own key takes over on first `vagrant up`. |
| Vagrant | `vagrant ssh kali` (from `vagrant/`) | Preferred during development; uses Vagrant's keypair automatically. |
| Console | `VBoxManage controlvm socool-kali showvminfo` / `virt-viewer socool-kali` | For when SSH is wedged. |

## Default credentials policy

Rotated accounts are in
[`packer/kali/scripts/rotate-credentials.sh`](../../packer/kali/scripts/rotate-credentials.sh):

- `root` — password, CSPRNG (24 chars).
- `vagrant` — password, CSPRNG (24 chars). Vagrant replaces its own
  private key on first `vagrant up`, so the password is only needed
  for direct SSH (not via Vagrant).

Both land in `packer/kali/artifacts/credentials.json` with mode 0600.
Upstream Kali defaults never reach the shipped box.

## How to reach the lab's management network

You can't — that's by design. pfSense rule #2 blocks
`lan → management`. To confirm the isolation:

```bash
vagrant ssh kali -c 'timeout 3 bash -c "</dev/tcp/10.42.20.10/443"'
#   expected: connection timed out
```

If that succeeds, pfSense's filter is mis-applied — open a bug and
see [`docs/troubleshooting.md`](../troubleshooting.md#network-cidr-collision).

## How to reset it

```bash
cd vagrant
vagrant destroy -f kali
rm packer/kali/artifacts/credentials.json
rm .socool-cache/boxes/socool-kali-*.box
./setup.sh
```

Mid-session cleanup (keep the box, wipe state):

```bash
vagrant ssh kali -c 'sudo rm -rf /tmp/* /root/.bash_history; history -c'
vagrant halt kali && vagrant up kali
```

## Known gotchas

- **Image is large** — `kali-linux-default` brings in ~4 GB of
  attack tooling. If disk is tight, swap to `kali-linux-core` in
  [`packer/kali/http/preseed.cfg`](../../packer/kali/http/preseed.cfg)
  and rebuild.
- **Default route bypasses pfSense.** Kali has two NICs: NAT (for
  SSH + outbound Internet) and the `socool-lan` private. The
  default route goes via NAT, so Internet-bound traffic does not
  traverse pfSense. For realistic attack-traffic studies, change
  the default gateway to `10.42.10.1` with a Packer provisioner.
- **SSH banner grab** is the smoke-test's signal that Kali is up.
  If banner-probing is blocked at your firewall, the
  [`tests/smoke/probes/kali.sh`](../../tests/smoke/probes/kali.sh)
  probe will false-fail.
- **UEFI boot** is enabled in the Packer template. Legacy-BIOS
  requires edits to both the Packer template and `preseed.cfg`'s
  grub-installer stanza.

## References

- [`packer/kali/README.md`](../../packer/kali/README.md) — build details.
- [Kali preseed examples](https://gitlab.com/kalilinux/recipes/kali-preseed-examples).
- [Kali for Vagrant](https://www.kali.org/docs/virtualization/install-vagrant-guest-vm/).
