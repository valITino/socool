# scripts/uninstall/run-all.ps1 — undo what setup.ps1 did, in dependency order.
#
# Parity counterpart: scripts/uninstall/run-all.sh. Every flag, prompt,
# env var, and exit code here MUST have an equivalent there.
#
# Phases mirror the bash side:
#   1. vagrant destroy -f             (stops & removes the lab VMs)
#   2. vagrant box remove socool-*    (purges the local box store)
#   3. vagrant plugin uninstall       (libvirt only, plus other socool plugins)
#   4. cache + artifact cleanup       (.socool-cache, packer_cache, packer/*/artifacts)
#   5. .env removal                   (sensitive — extra confirmation)
#   6. host package uninstall         (packer/vagrant/hypervisor — OPT-IN only)
#   7. repo deletion hint             (we never delete the repo we run from)
#
# Exit codes:
#   0     success
#   80    vagrant destroy failed
#   81    vagrant box remove failed
#   82    vagrant plugin uninstall failed
#   83    cache/artifact cleanup failed
#   84    user aborted at confirmation
#   85    package uninstall failed
#   86    .env removal blocked / failed

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

if ($script:SocoolUninstallLoaded) { return }
$script:SocoolUninstallLoaded = $true

# ────────────────────────────────────────────────────────────────────────
# Helpers
# ────────────────────────────────────────────────────────────────────────

function script:Test-DryRun {
    return ($env:SOCOOL_UNINSTALL_DRY_RUN -eq '1')
}

# Show a command, then either run it (real) or skip it (dry-run).
function script:Invoke-ShowOrRun {
    param(
        [Parameter(Mandatory)][string]$Description,
        [Parameter(Mandatory)][scriptblock]$Action
    )
    if (Test-DryRun) {
        Write-SocoolInfo ("[dry-run] {0}" -f $Description)
        return
    }
    Write-SocoolInfo $Description
    & $Action
}

# Refuses to act on empty paths or paths outside the repo root. Idempotent.
function script:Remove-SafeRepoPath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        Exit-Socool 1 'Remove-SafeRepoPath: empty path (refusing)'
    }
    if (-not (Test-Path -LiteralPath $Path)) {
        Write-SocoolDebug ("rm: skip (absent): {0}" -f $Path)
        return
    }
    $abs = (Resolve-Path -LiteralPath $Path).Path
    $repo = $script:SocoolRepoRoot
    if (-not $abs.StartsWith($repo)) {
        Exit-Socool 1 ("Remove-SafeRepoPath: '{0}' is outside repo root '{1}' (refusing)" -f $abs, $repo)
    }
    if (Test-DryRun) {
        Write-SocoolInfo ("[dry-run] Remove-Item -Recurse -Force -- {0}" -f $abs)
        return
    }
    Write-SocoolInfo ("Remove-Item -Recurse -Force -- {0}" -f $abs)
    Remove-Item -LiteralPath $abs -Recurse -Force
}

# ────────────────────────────────────────────────────────────────────────
# Phase 1: vagrant destroy
# ────────────────────────────────────────────────────────────────────────

function Invoke-SocoolUninstallVms {
    if ($env:SOCOOL_UNINSTALL_VMS -eq '0') {
        Write-SocoolInfo 'skip: vagrant destroy (SOCOOL_UNINSTALL_VMS=0)'
        return
    }
    $vagrantfile = Join-Path $script:SocoolRepoRoot 'vagrant/Vagrantfile'
    if (-not (Test-Path -LiteralPath $vagrantfile)) {
        Write-SocoolInfo ("skip: no Vagrantfile at {0}" -f $vagrantfile)
        return
    }
    if (-not (Get-Command vagrant -ErrorAction SilentlyContinue)) {
        Write-SocoolWarn 'vagrant not on PATH -- assuming no VMs are registered. Re-run with --packages skipped if you want to keep host tools.'
        return
    }

    Write-SocoolBanner 'Uninstall: vagrant destroy'

    Push-Location -LiteralPath (Join-Path $script:SocoolRepoRoot 'vagrant')
    try {
        if (Test-DryRun) {
            Write-SocoolInfo '[dry-run] cd vagrant; vagrant destroy -f'
        } else {
            $rc = 0
            try { & vagrant destroy -f } catch { $rc = 1 }
            if ($LASTEXITCODE -ne 0) { $rc = $LASTEXITCODE }
            if ($rc -ne 0) {
                $machinesDir = Join-Path $script:SocoolRepoRoot 'vagrant/.vagrant/machines'
                if (-not (Test-Path -LiteralPath $machinesDir)) {
                    Write-SocoolInfo ("no Vagrant machines registered (vagrant exited {0}); continuing" -f $rc)
                } else {
                    Exit-Socool 80 ("vagrant destroy failed (exit {0}); resolve manually with 'cd vagrant; vagrant status' before re-running" -f $rc)
                }
            }
        }
    } finally {
        Pop-Location
    }

    $vagrantState = Join-Path $script:SocoolRepoRoot 'vagrant/.vagrant'
    if (Test-Path -LiteralPath $vagrantState) {
        Remove-SafeRepoPath -Path $vagrantState
    }
}

# ────────────────────────────────────────────────────────────────────────
# Phase 2: vagrant box remove socool-*
# ────────────────────────────────────────────────────────────────────────

function Invoke-SocoolUninstallBoxes {
    if ($env:SOCOOL_UNINSTALL_BOXES -eq '0') {
        Write-SocoolInfo 'skip: vagrant box remove (SOCOOL_UNINSTALL_BOXES=0)'
        return
    }
    if (-not (Get-Command vagrant -ErrorAction SilentlyContinue)) {
        Write-SocoolDebug 'vagrant not on PATH; nothing to remove from box store'
        return
    }

    Write-SocoolBanner 'Uninstall: vagrant box remove'

    $list = ''
    try { $list = & vagrant box list 2>$null } catch { $list = '' }
    if ([string]::IsNullOrWhiteSpace($list)) {
        Write-SocoolInfo 'vagrant box store is empty'
        return
    }

    $removed = 0
    foreach ($line in ($list -split "`r?`n")) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        # Format: "name (provider, version)"
        $name = ($line -split ' ', 2)[0]
        if (-not $name.StartsWith('socool-')) { continue }
        if (Test-DryRun) {
            Write-SocoolInfo ("[dry-run] vagrant box remove --force --all -- {0}" -f $name)
            $removed++
            continue
        }
        Write-SocoolInfo ("vagrant box remove --force --all -- {0}" -f $name)
        & vagrant box remove --force --all -- $name
        if ($LASTEXITCODE -ne 0) {
            Exit-Socool 81 ("vagrant box remove failed for '{0}'" -f $name)
        }
        $removed++
    }
    if ($removed -eq 0) {
        Write-SocoolInfo 'no socool-* boxes registered'
    } else {
        Write-SocoolInfo ("removed {0} socool-* box(es) from the local store" -f $removed)
    }
}

# ────────────────────────────────────────────────────────────────────────
# Phase 3: vagrant plugin uninstall (libvirt path)
# ────────────────────────────────────────────────────────────────────────

function Invoke-SocoolUninstallVagrantPlugins {
    if ($env:SOCOOL_UNINSTALL_VAGRANT_PLUGINS -eq '0') {
        Write-SocoolInfo 'skip: vagrant plugin uninstall (SOCOOL_UNINSTALL_VAGRANT_PLUGINS=0)'
        return
    }
    if (-not (Get-Command vagrant -ErrorAction SilentlyContinue)) { return }

    Write-SocoolBanner 'Uninstall: vagrant plugins'

    $plugins = ''
    try { $plugins = & vagrant plugin list 2>$null } catch { $plugins = '' }
    if ($plugins -notmatch '(?m)^vagrant-libvirt\b') {
        Write-SocoolInfo 'vagrant-libvirt plugin not installed; nothing to do'
        return
    }
    if (Test-DryRun) {
        Write-SocoolInfo '[dry-run] vagrant plugin uninstall vagrant-libvirt'
        return
    }
    Write-SocoolInfo 'vagrant plugin uninstall vagrant-libvirt'
    & vagrant plugin uninstall vagrant-libvirt
    if ($LASTEXITCODE -ne 0) {
        Exit-Socool 82 'vagrant plugin uninstall failed for vagrant-libvirt'
    }
}

# ────────────────────────────────────────────────────────────────────────
# Phase 4: cache + artifact cleanup
# ────────────────────────────────────────────────────────────────────────

function Invoke-SocoolUninstallCaches {
    if ($env:SOCOOL_UNINSTALL_CACHES -eq '0') {
        Write-SocoolInfo 'skip: cache/artifact cleanup (SOCOOL_UNINSTALL_CACHES=0)'
        return
    }
    Write-SocoolBanner 'Uninstall: caches and artifacts'

    # 1. .socool-cache/
    $cacheDir = $env:SOCOOL_BOX_OUTPUT_DIR
    if ([string]::IsNullOrEmpty($cacheDir)) {
        $cacheDir = Join-Path $script:SocoolRepoRoot '.socool-cache'
    }
    $repo = $script:SocoolRepoRoot
    if ($cacheDir.StartsWith($repo)) {
        Remove-SafeRepoPath -Path $cacheDir
    } else {
        Write-SocoolWarn ("SOCOOL_BOX_OUTPUT_DIR='{0}' is outside the repo; skipping (remove manually if desired)" -f $cacheDir)
    }
    $defaultCache = Join-Path $repo '.socool-cache'
    if (Test-Path -LiteralPath $defaultCache) {
        Remove-SafeRepoPath -Path $defaultCache
    }

    # 2. packer/*/artifacts
    $packerRoot = Join-Path $repo 'packer'
    if (Test-Path -LiteralPath $packerRoot) {
        Get-ChildItem -LiteralPath $packerRoot -Directory -ErrorAction SilentlyContinue |
            ForEach-Object {
                $artifacts = Join-Path $_.FullName 'artifacts'
                if (Test-Path -LiteralPath $artifacts) {
                    Write-SocoolInfo 'removing packer artifacts (contains rotated credentials)'
                    Remove-SafeRepoPath -Path $artifacts
                }
            }
    }

    # 3. packer_cache/ (anywhere in repo)
    Get-ChildItem -LiteralPath $repo -Directory -Recurse -Force -Filter 'packer_cache' -ErrorAction SilentlyContinue |
        ForEach-Object { Remove-SafeRepoPath -Path $_.FullName }

    # 4. Stray *.box files within the repo (limit depth to avoid sweeping deep symlinks).
    Get-ChildItem -LiteralPath $repo -File -Recurse -Force -Filter '*.box' -Depth 4 -ErrorAction SilentlyContinue |
        ForEach-Object { Remove-SafeRepoPath -Path $_.FullName }

    Write-SocoolInfo 'cache + artifact cleanup done'
}

# ────────────────────────────────────────────────────────────────────────
# Phase 5: .env removal
# ────────────────────────────────────────────────────────────────────────

function Invoke-SocoolUninstallEnvFile {
    if ($env:SOCOOL_UNINSTALL_ENV -ne '1') {
        Write-SocoolInfo 'skip: .env removal (default; pass -EnvFile or SOCOOL_UNINSTALL_ENV=1 to remove)'
        return
    }
    $envFile = Join-Path $script:SocoolRepoRoot '.env'
    if (-not (Test-Path -LiteralPath $envFile)) {
        Write-SocoolInfo 'no .env to remove'
        return
    }

    Write-SocoolBanner 'Uninstall: .env'
    Write-SocoolWarn '.env may contain license keys, activation codes, or paths to sensitive ISOs.'
    Write-SocoolWarn 'It is gitignored, so this only affects your local copy. There is no backup.'

    $answer = Read-SocoolYesNo -Label 'env-remove' -Question ("Delete {0}?" -f $envFile) -Default 'n' -EnvName 'SOCOOL_YES'
    if ($answer -ne 'y') {
        Write-SocoolInfo 'leaving .env in place'
        return
    }
    if (Test-DryRun) {
        Write-SocoolInfo ("[dry-run] Remove-Item -- {0}" -f $envFile)
        return
    }
    try {
        Remove-Item -LiteralPath $envFile -Force
    } catch {
        Exit-Socool 86 ("failed to remove {0}: {1}" -f $envFile, $_.Exception.Message)
    }
    Write-SocoolInfo ("removed {0}" -f $envFile)
}

# ────────────────────────────────────────────────────────────────────────
# Phase 6: host package uninstall (opt-in)
# ────────────────────────────────────────────────────────────────────────

function Invoke-SocoolUninstallHostPackages {
    if ($env:SOCOOL_UNINSTALL_PACKAGES -ne '1') {
        Write-SocoolInfo 'skip: host package uninstall (default; pass --packages or SOCOOL_UNINSTALL_PACKAGES=1 to opt in)'
        return
    }
    Write-SocoolBanner 'Uninstall: host packages'
    Write-SocoolWarn 'About to remove packer, vagrant, and the hypervisor package(s) you used.'
    Write-SocoolWarn 'Other projects on this host that rely on these tools will break.'

    $answer = Read-SocoolYesNo -Label 'pkg-confirm' -Question 'Continue removing host packages?' -Default 'n' -EnvName 'SOCOOL_YES'
    if ($answer -ne 'y') {
        Exit-Socool 84 'aborted by user at host-package confirmation'
    }

    $pm = Get-SocoolPackageManager

    $hv = $env:SOCOOL_HYPERVISOR
    if ([string]::IsNullOrEmpty($hv)) {
        Write-SocoolWarn 'SOCOOL_HYPERVISOR not set; will attempt to remove every hypervisor stack we know about'
        $hv = 'all'
    }

    switch ($pm) {
        'winget' {
            $ids = @('Hashicorp.Packer', 'Hashicorp.Vagrant')
            if ($hv -in @('virtualbox','all')) { $ids += 'Oracle.VirtualBox' }
            foreach ($id in $ids) {
                if (Test-DryRun) {
                    Write-SocoolInfo ("[dry-run] winget uninstall --exact --id={0} --silent" -f $id)
                    continue
                }
                Write-SocoolInfo ("winget uninstall --exact --id={0} --silent" -f $id)
                & winget uninstall --exact --id $id --silent --accept-source-agreements
                # winget exit codes: 0 success, 0x8A150014 (= 2316632084) "no installed package matched"
                if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne 2316632084) {
                    Exit-Socool 85 ("winget uninstall failed for {0} (exit {1})" -f $id, $LASTEXITCODE)
                }
            }
        }
        'choco' {
            $names = @('packer','vagrant')
            if ($hv -in @('virtualbox','all')) { $names += 'virtualbox' }
            foreach ($n in $names) {
                if (Test-DryRun) {
                    Write-SocoolInfo ("[dry-run] choco uninstall -y {0}" -f $n)
                    continue
                }
                Write-SocoolInfo ("choco uninstall -y {0}" -f $n)
                & choco uninstall -y --no-progress $n
                # choco rc 0 = ok; rc 2 = "package not installed" — both fine.
                if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne 2) {
                    Exit-Socool 85 ("choco uninstall failed for {0} (exit {1})" -f $n, $LASTEXITCODE)
                }
            }
        }
        default {
            Exit-Socool 85 ("Invoke-SocoolUninstallHostPackages: use uninstall.sh on Linux/macOS (package manager: {0})" -f $pm)
        }
    }
    Write-SocoolInfo 'host packages removed'
}

# ────────────────────────────────────────────────────────────────────────
# Phase 7: repo deletion hint
# ────────────────────────────────────────────────────────────────────────

function script:Show-SocoolRepoDeletionHint {
    Write-SocoolBanner 'Final step: remove the repo directory'
    [Console]::Error.WriteLine('SOCool will not delete the directory it is running from.')
    [Console]::Error.WriteLine('When you are ready, run:')
    [Console]::Error.WriteLine('')
    [Console]::Error.WriteLine('  Set-Location ..')
    [Console]::Error.WriteLine(('  Remove-Item -Recurse -Force -- "{0}"' -f $script:SocoolRepoRoot))
    [Console]::Error.WriteLine('')
    [Console]::Error.WriteLine('VirtualBox host-only adapters created during the lab life are not')
    [Console]::Error.WriteLine('removed automatically (Vagrant leaves them in place by design).')
    [Console]::Error.WriteLine('Inspect with `VBoxManage list hostonlyifs` and remove any unused')
    [Console]::Error.WriteLine('ones with `VBoxManage hostonlyif remove <name>` if you wish.')
}

# ────────────────────────────────────────────────────────────────────────
# Top-level orchestrator
# ────────────────────────────────────────────────────────────────────────

function Invoke-SocoolUninstall {
    [CmdletBinding()]
    param()

    Write-SocoolBanner 'SOCool uninstall'
    if (Test-DryRun) {
        Write-SocoolWarn 'DRY RUN -- no changes will be made'
    }

    if ($env:SOCOOL_YES -ne '1' -and -not (Test-DryRun)) {
        Write-SocoolWarn 'This will destroy the SOCool lab VMs, remove built boxes, and clear local caches.'
        Write-SocoolWarn 'Repo files tracked by git are NOT modified. The .env file is left in place'
        Write-SocoolWarn 'unless you pass -EnvFile.'
        $answer = Read-SocoolYesNo -Label 'uninstall-confirm' -Question 'Proceed with uninstall?' -Default 'n' -EnvName 'SOCOOL_YES'
        if ($answer -ne 'y') {
            Exit-Socool 84 'aborted by user at top-level confirmation'
        }
    }

    Invoke-SocoolUninstallVms
    Invoke-SocoolUninstallBoxes
    Invoke-SocoolUninstallVagrantPlugins
    Invoke-SocoolUninstallCaches
    Invoke-SocoolUninstallEnvFile
    Invoke-SocoolUninstallHostPackages
    Show-SocoolRepoDeletionHint

    Write-SocoolBanner 'SOCool uninstall complete'
}
