# tests/smoke/

Post-boot smoke tests. Each VM has a probe script under `probes/` that
verifies its primary service is responding. Run together via
`./test-smoke.sh`.

These tests require a **live lab** — `vagrant up` must have completed
for the VMs the test is probing. `tests/run-all.sh` skips this
directory unless `SOCOOL_LAB_UP=1` or a `vagrant status` probe shows
VMs running.

## What each probe asserts

| VM | Probe | Primary signal |
|---|---|---|
| `pfsense` | `probes/pfsense.sh` | HTTPS 200/302 on `https://10.42.20.1/` (webConfigurator) |
| `kali` | `probes/kali.sh` | TCP 22 open on `10.42.10.10` (SSH) |
| `windows-victim` | `probes/windows-victim.sh` | TCP 3389 open on `10.42.10.20` (RDP) |
| `wazuh` | `probes/wazuh.sh` | HTTPS 200 on `https://10.42.20.10/` (dashboard) |
| `nessus` | `probes/nessus.sh` | HTTPS 200 on `https://10.42.20.20:8834/` (Nessus web UI) |
| `openvas` | `probes/openvas.sh` | HTTPS 200/301 on `https://10.42.20.20/` (Greenbone web UI) |

Each probe exits 0 on success, 70–79 on a documented failure (the
smoke-test range from `.skills/shell-scripting/SKILL.md`).

## Isolation guarantees verified

`test-smoke.sh` also runs a small negative-path check that verifies
**Kali cannot reach the management subnet directly**. If it can, pfSense's
filter rules are wrong and the lab's isolation promise is broken.
Expected result: attempt to TCP-connect from Kali to `10.42.20.10:443`
times out; if it succeeds, smoke fails with code 78.

## Running a single probe

```
SOCOOL_LAB_UP=1 bash tests/smoke/probes/wazuh.sh
```

## Adding a new VM

1. Add `probes/<vm>.sh`. Exit 0 on pass; 70–79 with a `[FAIL] <reason>`
   line on failure.
2. Add the VM's row to the table above.
3. `test-smoke.sh` auto-discovers every `*.sh` under `probes/`.
