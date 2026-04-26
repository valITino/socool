# Uninstall

Tears down what `setup.sh` / `setup.ps1` installed. The entry points are
[`uninstall.sh`](../../uninstall.sh) (Linux/macOS) and
[`uninstall.ps1`](../../uninstall.ps1) (Windows / cross-platform pwsh 7+).

## What gets removed by default

| Phase | What | Why it's safe by default |
|---|---|---|
| 1. VMs | `cd vagrant && vagrant destroy -f` | Only touches VMs declared in this repo's `Vagrantfile`. |
| 2. Boxes | `vagrant box remove --force --all socool-*` | Filtered to the `socool-` namespace. Other Vagrant boxes are untouched. |
| 3. Plugins | `vagrant plugin uninstall vagrant-libvirt` (libvirt path only) | Only the plugin SOCool would have installed. |
| 4. Caches | `.socool-cache/`, `packer/*/artifacts/`, `packer_cache/`, stray `*.box` | All inside the repo or under `SOCOOL_BOX_OUTPUT_DIR`. Gitignored — not your work. |

## What is NOT removed by default

| Phase | What | How to opt in |
|---|---|---|
| 5. `.env` | License keys, activation codes, ISO paths | `--env` (bash) / `-EnvFile` (pwsh). Confirms again before deletion. |
| 6. Host packages | packer, vagrant, virtualbox, qemu/libvirt | `--packages` (bash) / `-Packages` (pwsh). Confirms again before deletion. |
| 7. Repo directory | The clone itself | Never auto-deleted. The script prints `rm -rf` instructions and exits. |

The reason host packages are opt-in is the same reason `setup.*` does not
auto-disable Hyper-V or auto-configure HashiCorp's apt repo: those tools
are commonly used by other projects, and silently removing them would
break the user's workflow. The user must consent each time.

## Common invocations

```bash
# Default: VMs, boxes, plugins, caches. Leaves .env and host tools in place.
./uninstall.sh

# Preview only — show every command but make no changes.
./uninstall.sh --dry-run

# Non-interactive (CI). Skips every confirmation, including the top-level one.
./uninstall.sh --yes

# Total wipe: also removes .env and host packages.
./uninstall.sh --all --yes

# Keep host VMs and boxes, but clear caches and credentials artifacts.
# Useful if a build failed mid-way and you want to retry from scratch.
./uninstall.sh --keep-vms --keep-boxes
```

```powershell
# Same flag surface on Windows.
./uninstall.ps1
./uninstall.ps1 -DryRun
./uninstall.ps1 -Yes
./uninstall.ps1 -All -Yes
./uninstall.ps1 -KeepVms -KeepBoxes
```

## Safety rules the script follows

1. **Top-level confirmation.** Without `--yes` / `-Yes`, the script asks once
   before doing anything. With `--dry-run` it skips the prompt because nothing
   destructive happens.
2. **Path guards.** Every `rm -rf` / `Remove-Item` call goes through a helper
   that refuses empty paths and refuses any path outside the repo root or the
   user-set `SOCOOL_BOX_OUTPUT_DIR`. A bug that produces an empty `$cache_dir`
   exits with code 1 instead of deleting `/`.
3. **Filtered cleanup.** Boxes and networks are filtered to the `socool-`
   namespace. The script never enumerates "all Vagrant boxes" or "all libvirt
   networks" and removes them.
4. **Idempotent.** Re-running on a clean state is a no-op success. Phases that
   have nothing to do log "skip" and continue.
5. **Sensitive paths logged generically.** When removing
   `packer/*/artifacts/`, the log line says "removing packer artifacts
   (contains rotated credentials)" rather than enumerating files.
6. **Repo deletion is hinted, not done.** The script lives inside the repo
   and refuses to delete the directory it's running from. It prints the exact
   `rm -rf` / `Remove-Item` line for the user to copy.

## Exit codes

| Code | Meaning |
|---|---|
| `0` | success (or nothing to do) |
| `2` | invalid CLI usage (`--unknown-flag`) |
| `80` | `vagrant destroy` failed |
| `81` | `vagrant box remove` failed |
| `82` | `vagrant plugin uninstall` failed |
| `83` | cache / artifact cleanup failed (reserved; current paths exit 1 on guard violation) |
| `84` | user aborted at a confirmation prompt |
| `85` | host package uninstall failed |
| `86` | `.env` removal blocked / failed |

These codes are logged to `docs/troubleshooting.md`. A new code requires an
update there in the same commit (per `.skills/shell-scripting/SKILL.md`).

## Things the script intentionally does NOT touch

- **VirtualBox host-only adapters.** `vagrant destroy` does not remove these
  (Vagrant changed this default years ago because removing shared adapters
  broke other people's VMs). The script prints a hint at the end with the
  `VBoxManage list hostonlyifs` / `VBoxManage hostonlyif remove` commands so
  the user can clean them up manually.
- **libvirt named networks** (`socool-lan`, `socool-management`). They are
  scoped per-user storage pool, harmless to leave behind, and can be removed
  with `virsh net-undefine socool-lan` if desired. SOCool may add a flag for
  this in a future release once we've validated the cross-distro behaviour.
- **Files tracked by git.** Uninstall changes nothing under version control.
  If you want to start from a fresh clone, use `git clean -fdx` after the
  uninstall to wipe everything else, or just `cd .. && rm -rf socool/`.
