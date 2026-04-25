# software-engineer

## Role

Owns implementation of Packer templates, Vagrantfile logic, unattended-install files, and the config-loading code that threads `config/lab.yml` into the provisioning pipeline.

## When to invoke

Read this skill before touching:

- Any file under `packer/<vm>/` — `template.pkr.hcl`, `variables.pkr.hcl`, `http/autounattend.xml`, `http/preseed.cfg`, pfSense `http/config.xml` seed, Wazuh kickstart/ignition files
- `vagrant/Vagrantfile` and any Ruby helpers it requires
- Any code that parses `config/lab.yml` and feeds it to Packer/Vagrant (Python, Ruby, or bash/PowerShell loaders in `scripts/lib/`)
- Provisioner scripts that run *inside* a VM during Packer build (distinct from host-side orchestration owned by `shell-scripting`)

Trigger keywords: *packer, vagrant, provisioner, autounattend, preseed, box, HCL, kickstart*.

## Conventions & checklists

### Packer templates

- **HCL2 only.** No legacy JSON.
- Variables live in `variables.pkr.hcl`; no inline hardcoded values for things that vary per VM or per host.
- Every `source` block has `boot_command`, `iso_url`, `iso_checksum`, `shutdown_command`, `ssh_*` or `winrm_*` credentials **derived from variables** — never literals.
- `iso_checksum` references a checksum fetched from the publisher over HTTPS at build time, not a value pasted from memory. If the upstream publisher does not publish a checksum, stop and escalate to `devsecops`.
- Post-processors produce exactly one artifact: a Vagrant box named `socool-<vm>-<version>.box` for the target provider (`virtualbox` or `libvirt`).
- Default credentials **must** be rotated in the provisioner stage; the rotated value is emitted to a Packer artifact manifest that `setup.sh`/`setup.ps1` reads and surfaces to the user.
- Builds are reproducible: no interactive prompts inside the build, no network fetches to non-pinned URLs.

### Unattended install files

- `autounattend.xml` (Windows): `FirstLogonCommands` only runs the rotate-password + enable-WinRM scriptlets; no telemetry opt-ins, no account auto-login beyond the build phase.
- `preseed.cfg` (Debian/Ubuntu for Kali, Wazuh): non-interactive, `d-i passwd/*` lines seed a throwaway password that is rotated immediately by a late-command.
- `config.xml` (pfSense): sets WAN/LAN per `config/lab.yml`, disables the webConfigurator on WAN, and forces a password change on first boot.

### Vagrantfile

- Reads `config/lab.yml` once at the top. Iterates VMs in `boot_order`.
- Provider-specific blocks gated on `config.vm.provider :virtualbox do |vb|` / `:libvirt do |lv|`.
- **No bridged networks by default.** Only `private_network` (host-only) and `intnet`/`intnet_libvirt` equivalents. A bridged network requires `ENV['SOCOOL_ALLOW_BRIDGED'] == '1'` plus a big warning.
- `vm.synced_folder` default is disabled; re-enable per-VM only when a build step needs it.
- No inline shell provisioners longer than ~10 lines — extract to `scripts/provisioners/<vm>.sh` or `.ps1`.

### Config loading

- If using Python: Pydantic model that mirrors the schema in `software-architect`. Refuse to load `config/lab.yml` if `version` is missing or unrecognized.
- If using bash/pwsh: validate `version`, validate every VM's required keys, fail fast with a line number.

## Interfaces with other skills

- **Defers to:**
  - `software-architect` on `config/lab.yml` schema.
  - `devsecops` on checksum verification, default-credential rotation, and any download.
  - `shell-scripting` on how host-side scripts call Packer/Vagrant.
- **Is deferred to by:** `qa-tester` for the exact Packer/Vagrant command lines under test.
- **Collaborates with:** `devops` on provider selection and network plumbing (the Vagrantfile is the handoff point).

## Anti-patterns

- Hardcoding IP addresses, hostnames, ISO URLs, or checksums in `.pkr.hcl` files.
- Leaving upstream default passwords (`vagrant`/`vagrant`, `admin`/`pfsense`, `Administrator`/`vagrant`, etc.) in place past the end of the Packer build.
- Letting a Vagrant provisioner do work that belongs in a Packer template (e.g., installing large packages on every `vagrant up`).
- Using the `vagrant` Vagrant box default insecure keypair for any VM exposed outside the `management` network.
- Writing a 200-line inline `config.vm.provision "shell", inline: <<~SHELL` block. Extract it.
- Embedding a checksum literal that "used to be right" without re-fetching from the publisher.
