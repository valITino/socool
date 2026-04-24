# scripts/lib/hypervisor.ps1 — hypervisor detection and resolution (pwsh).
#
# Implements the algorithm from docs/adr/0002-hypervisor-matrix.md.
# Public ABI:
#   Resolve-SocoolHypervisor  -> returns 'virtualbox' or 'libvirt', or
#                                exits 30..39 on conflict.
# Must be dot-sourced AFTER common.ps1 and AFTER Get-SocoolHost ran.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($script:SocoolHypervisorLoaded) { return }
$script:SocoolHypervisorLoaded = $true

# ────────────────────────────────────────────────────────────────────────
# Conflict probes
# ────────────────────────────────────────────────────────────────────────

function script:Test-KvmAvailable {
    if (-not $IsLinux) { return $false }
    return (Test-Path '/sys/module/kvm_intel/parameters/nested') -or `
           (Test-Path '/sys/module/kvm_amd/parameters/nested')
}

function script:Test-VBoxManageAvailable {
    return [bool](Get-Command VBoxManage -ErrorAction SilentlyContinue)
}

function script:Test-QemuAvailable {
    return [bool]((Get-Command qemu-system-x86_64 -ErrorAction SilentlyContinue) -or
                  (Get-Command qemu-system-aarch64 -ErrorAction SilentlyContinue))
}

# Windows-only: detect conflicts that make VirtualBox unreliable.
# Returns a list of conflict names; empty list means no conflict.
function script:Get-WindowsHypervisorConflicts {
    if (-not $IsWindows) { return @() }
    $conflicts = @()

    # Hyper-V feature state.
    try {
        $hv = Get-WindowsOptionalFeature -Online -FeatureName 'Microsoft-Hyper-V-All' -ErrorAction SilentlyContinue
        if ($null -ne $hv -and $hv.State -eq 'Enabled') { $conflicts += 'Hyper-V' }
    } catch {
        Write-SocoolDebug ("Hyper-V feature probe failed: {0}" -f $_.Exception.Message)
    }

    # bcdedit hypervisorlaunchtype. Even with the feature present,
    # `off` means Hyper-V is dormant and VirtualBox can run.
    try {
        $bcd = & bcdedit /enum '{current}' 2>$null | Select-String 'hypervisorlaunchtype'
        if ($bcd -and ($bcd -match 'Auto')) { $conflicts += 'hypervisorlaunchtype=Auto' }
    } catch {
        Write-SocoolDebug ("bcdedit probe failed: {0}" -f $_.Exception.Message)
    }

    # WSL2 backed by Hyper-V.
    try {
        $wslVer = & wsl.exe --version 2>$null
        if ($LASTEXITCODE -eq 0 -and $wslVer) { $conflicts += 'WSL2' }
    } catch {
        Write-SocoolDebug ("wsl --version probe failed: {0}" -f $_.Exception.Message)
    }

    # Docker Desktop with WSL2 backend.
    $dockerDesktopExe = Join-Path $env:ProgramFiles 'Docker\Docker\Docker Desktop.exe'
    if (Test-Path -LiteralPath $dockerDesktopExe) { $conflicts += 'Docker Desktop' }

    return ,$conflicts
}

# ────────────────────────────────────────────────────────────────────────
# Matrix-driven resolution
# ────────────────────────────────────────────────────────────────────────

function script:Get-SocoolMatrixPrimaryFallback {
    $os   = $env:SOCOOL_OS
    $arch = $env:SOCOOL_ARCH
    switch ("$os`:$arch") {
        'linux:x86_64'   { return @{ Primary='virtualbox'; Fallback='libvirt' } }
        'linux:aarch64'  { return @{ Primary='libvirt';    Fallback=$null } }
        'darwin:x86_64'  { return @{ Primary='virtualbox'; Fallback='libvirt' } }
        'darwin:aarch64' { return @{ Primary='libvirt';    Fallback=$null } }
        'windows:x86_64' { return @{ Primary='virtualbox'; Fallback=$null } }
        'windows:aarch64'{ Exit-Socool 30 'Windows on aarch64 is unsupported by SOCool. Use an x86_64 Windows host or switch to Linux/macOS.' }
        default          { Exit-Socool 30 ("unsupported host: os={0} arch={1}" -f $os, $arch) }
    }
}

function script:Assert-SocoolHypervisorChoice {
    param([Parameter(Mandatory)][string]$Choice)
    $key = "{0}:{1}:{2}" -f $env:SOCOOL_OS, $env:SOCOOL_ARCH, $Choice
    switch ($key) {
        'linux:x86_64:virtualbox'    { return }
        'linux:x86_64:libvirt'       { return }
        'linux:aarch64:libvirt'      { return }
        'linux:aarch64:virtualbox'   { Exit-Socool 30 'VirtualBox does not support aarch64 Linux hosts. Use SOCOOL_HYPERVISOR=libvirt.' }
        'darwin:x86_64:virtualbox'   { return }
        'darwin:x86_64:libvirt'      { return }
        'darwin:aarch64:libvirt'     { return }
        'darwin:aarch64:virtualbox'  {
            Write-SocoolWarn 'VirtualBox on Apple Silicon: pfSense and the Windows victim are x86_64 and will run under x86 emulation (slow). VirtualBox 7.2.4 has known Windows-guest crash bugs. QEMU is recommended (SOCOOL_HYPERVISOR=libvirt).'
            return
        }
        'windows:x86_64:virtualbox'  { return }
        'windows:x86_64:libvirt'     { Exit-Socool 30 'libvirt/QEMU on Windows is not supported by SOCool. Use VirtualBox.' }
        default                      { Exit-Socool 30 ("unsupported host/hypervisor combination: {0}" -f $key) }
    }
}

function Resolve-SocoolHypervisor {
    [CmdletBinding()]
    param()

    # 1. Explicit override.
    $explicit = [Environment]::GetEnvironmentVariable('SOCOOL_HYPERVISOR')
    if (-not [string]::IsNullOrEmpty($explicit)) {
        if ($explicit -notin @('virtualbox','libvirt')) {
            Exit-Socool 2 ("invalid SOCOOL_HYPERVISOR='{0}' (expected virtualbox or libvirt)" -f $explicit)
        }
        Assert-SocoolHypervisorChoice -Choice $explicit
        if ($IsWindows -and $explicit -eq 'virtualbox') {
            $conflicts = Get-WindowsHypervisorConflicts
            if ($conflicts.Count -gt 0) {
                Exit-Socool 30 ("VirtualBox is chosen but Windows reports conflicts: {0}. See docs/adr/0002-hypervisor-matrix.md for remediation." -f ($conflicts -join ', '))
            }
        }
        Write-SocoolInfo ("hypervisor: {0} (from SOCOOL_HYPERVISOR)" -f $explicit)
        return $explicit
    }

    # 2. Matrix walk.
    $matrix  = Get-SocoolMatrixPrimaryFallback
    $primary = $matrix.Primary
    $fallback = $matrix.Fallback

    # 3. Windows: hard-block on Hyper-V / WSL2 / Docker Desktop BEFORE picking.
    if ($IsWindows) {
        $conflicts = Get-WindowsHypervisorConflicts
        if ($conflicts.Count -gt 0) {
            $msg = @(
                ("VirtualBox on Windows conflicts with: {0}." -f ($conflicts -join ', ')),
                '',
                'Options:',
                "  1. Disable Hyper-V (breaks WSL2 and Docker Desktop until re-enabled):",
                "     bcdedit /set hypervisorlaunchtype off    (run as Administrator, then reboot)",
                '  2. Move SOCool to a Linux host (recommended for the full scanner workload).',
                '  3. See docs/adr/0002-hypervisor-matrix.md for full reasoning.'
            ) -join [Environment]::NewLine
            Exit-Socool 30 $msg
        }
    }

    # 4. Detection.
    $havePrimary  = $false
    $haveFallback = $false
    switch ($primary) {
        'virtualbox' { $havePrimary  = Test-VBoxManageAvailable }
        'libvirt'    {
            $havePrimary = Test-QemuAvailable
            if ($IsLinux -and -not (Test-KvmAvailable)) { $havePrimary = $false }
        }
    }
    if ($fallback) {
        switch ($fallback) {
            'virtualbox' { $haveFallback = Test-VBoxManageAvailable }
            'libvirt'    {
                $haveFallback = Test-QemuAvailable
                if ($IsLinux -and -not (Test-KvmAvailable)) { $haveFallback = $false }
            }
        }
    }

    # 5. Ambiguity -> prompt.
    if ($havePrimary -and $haveFallback) {
        Show-SocoolAction `
            -Title  'Choose hypervisor' `
            -What   ("Both {0} and {1} are installed. Pick one." -f $primary, $fallback) `
            -Where  '<no external resource>' `
            -Paste  'virtualbox or libvirt' `
            -EnvName 'SOCOOL_HYPERVISOR'
        $chosen = Read-SocoolPrompt -Label 'hypervisor' -Question 'Hypervisor' -Default $primary -EnvName 'SOCOOL_HYPERVISOR'
        if ($chosen -notin @('virtualbox','libvirt')) {
            Exit-Socool 2 ("invalid choice: '{0}'" -f $chosen)
        }
        Assert-SocoolHypervisorChoice -Choice $chosen
        Write-SocoolInfo ("hypervisor: {0} (chosen)" -f $chosen)
        return $chosen
    }

    if ($havePrimary)  { Assert-SocoolHypervisorChoice -Choice $primary;  Write-SocoolInfo ("hypervisor: {0} (primary, detected)" -f $primary);  return $primary }
    if ($haveFallback) { Assert-SocoolHypervisorChoice -Choice $fallback; Write-SocoolWarn ("primary hypervisor '{0}' not detected; using fallback '{1}'" -f $primary, $fallback); return $fallback }

    # 6. Nothing installed -> deps layer will install the primary.
    Assert-SocoolHypervisorChoice -Choice $primary
    Write-SocoolWarn ("no hypervisor detected; will install {0}" -f $primary)
    return $primary
}
