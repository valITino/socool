# tests/destroy-recreate/

Tears the lab down with `vagrant destroy -f` and re-runs `setup.sh`,
then asserts the new lab end-state matches the original in every way
that should be reproducible.

Requires a **live lab**. Gated on `SOCOOL_LAB_UP=1`.

## What it asserts

- `vagrant destroy -f` leaves **no VMs** and **no libvirt networks**
  named `socool-lan` / `socool-management`.
- A fresh `setup.sh --yes` completes without user prompts.
- Every smoke probe (`tests/smoke/probes/*.sh`) passes after the
  rebuild.
- The Packer manifests match bit-for-bit (same images built from same
  inputs — credentials manifests differ because they are CSPRNG-rotated
  per run, which is correct).

## Running

```bash
SOCOOL_LAB_UP=1 bash tests/destroy-recreate/test-destroy-recreate.sh
```

Exit 0 on success; 1 on any assertion failure; 77 on skip.

## Risk profile

**This test is destructive.** It removes the lab. Do not run on a
host where the lab is doing work you care about. The script refuses
to proceed unless `SOCOOL_DESTROY_CONFIRM=1` is also set, so a
casual `run-all.sh` can never trigger it by accident.
