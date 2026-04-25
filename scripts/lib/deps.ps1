# scripts/lib/deps.ps1 — dependency detection & installation (pwsh).
#
# Public ABI:
#   Get-SocoolPackageManager   -> returns 'winget'|'choco'|'brew'|'apt'|'dnf'|'pacman' or exits 21
#   Install-SocoolDeps <hv>    -> ensures git, python3+yaml, packer, vagrant,
#                                 hypervisor are present. Idempotent.
#
# Design notes mirror scripts/lib/deps.sh: no third-party repo auto-config.
# Windows path is the primary focus; Linux/macOS fall back to delegating
# to setup.sh (users on those OSes should use setup.sh).

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

if ($script:SocoolDepsLoaded) { return }
$script:SocoolDepsLoaded = $true

# ────────────────────────────────────────────────────────────────────────
# Package manager detection
# ────────────────────────────────────────────────────────────────────────

function Get-SocoolPackageManager {
    if ($IsWindows) {
        if (Get-Command winget -ErrorAction SilentlyContinue) { return 'winget' }
        if (Get-Command choco  -ErrorAction SilentlyContinue) { return 'choco' }
        Exit-Socool 21 'No supported Windows package manager found. Install App Installer (winget) from the Microsoft Store, or Chocolatey from https://chocolatey.org/install, then re-run.'
    }
    if ($IsMacOS) {
        if (Get-Command brew -ErrorAction SilentlyContinue) { return 'brew' }
        Exit-Socool 21 'Homebrew not found. Install from https://brew.sh/ and re-run.'
    }
    if ($IsLinux) {
        if (Get-Command apt-get -ErrorAction SilentlyContinue) { return 'apt'    }
        if (Get-Command dnf     -ErrorAction SilentlyContinue) { return 'dnf'    }
        if (Get-Command pacman  -ErrorAction SilentlyContinue) { return 'pacman' }
        Exit-Socool 21 'No supported Linux package manager found.'
    }
    Exit-Socool 21 'Unrecognized host OS for dependency install.'
}

# ────────────────────────────────────────────────────────────────────────
# Admin / sudo handling
# ────────────────────────────────────────────────────────────────────────

$script:AdminVerified = $false

function script:Assert-WindowsAdmin {
    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Exit-Socool 21 'setup.ps1 must run as Administrator to install host packages. Right-click PowerShell 7 and "Run as Administrator".'
    }
    $script:AdminVerified = $true
}

# ────────────────────────────────────────────────────────────────────────
# Install primitives
# ────────────────────────────────────────────────────────────────────────

function script:Install-SocoolWingetPackage {
    param([Parameter(Mandatory)][string]$Id)
    Write-SocoolInfo ("winget install --id={0}" -f $Id)
    & winget install --exact --id $Id --silent --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) {
        Exit-Socool 21 ("winget install failed for {0} (exit {1})" -f $Id, $LASTEXITCODE)
    }
}

function script:Install-SocoolChocoPackage {
    param([Parameter(Mandatory)][string]$Name)
    Write-SocoolInfo ("choco install {0}" -f $Name)
    & choco install -y --no-progress $Name
    if ($LASTEXITCODE -ne 0) {
        Exit-Socool 21 ("choco install failed for {0} (exit {1})" -f $Name, $LASTEXITCODE)
    }
}

function script:Confirm-SocoolInstall {
    param([Parameter(Mandatory)][string]$Description)
    if ($env:SOCOOL_YES -eq '1') {
        Write-SocoolInfo ("installing {0} (SOCOOL_YES=1)" -f $Description)
        return
    }
    $answer = Read-SocoolYesNo -Label 'dep-install' `
                               -Question ("Install {0} now?" -f $Description) `
                               -Default 'y' -EnvName 'SOCOOL_YES'
    if ($answer -ne 'y') {
        Exit-Socool 21 ("aborted by user: {0} required" -f $Description)
    }
}

# ────────────────────────────────────────────────────────────────────────
# Per-dependency helpers (Windows-focused)
# ────────────────────────────────────────────────────────────────────────

function script:Test-CommandPresent {
    param([string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Install-SocoolGit {
    if (Test-CommandPresent 'git') { Write-SocoolDebug 'git: present'; return }
    Confirm-SocoolInstall 'git'
    switch (Get-SocoolPackageManager) {
        'winget' { Install-SocoolWingetPackage -Id 'Git.Git' }
        'choco'  { Install-SocoolChocoPackage  -Name 'git' }
        default  { Exit-Socool 21 'use setup.sh on Linux/macOS to install git.' }
    }
}

function Install-SocoolPython {
    if ((Test-CommandPresent 'python3') -or (Test-CommandPresent 'python')) {
        $py = if (Test-CommandPresent 'python3') { 'python3' } else { 'python' }
        $yaml = & $py -c 'import yaml' 2>$null
        if ($LASTEXITCODE -eq 0) { Write-SocoolDebug 'python + PyYAML: present'; return }
    }
    Confirm-SocoolInstall 'python3 and PyYAML (for config parsing)'
    switch (Get-SocoolPackageManager) {
        'winget' {
            Install-SocoolWingetPackage -Id 'Python.Python.3.12'
            # PyYAML via pip.
            $py = if (Test-CommandPresent 'python3') { 'python3' } else { 'python' }
            & $py -m pip install --user --quiet pyyaml
        }
        'choco'  {
            Install-SocoolChocoPackage -Name 'python'
            $py = if (Test-CommandPresent 'python3') { 'python3' } else { 'python' }
            & $py -m pip install --user --quiet pyyaml
        }
        default  { Exit-Socool 21 'use setup.sh on Linux/macOS to install python3.' }
    }
}

function Install-SocoolPacker {
    if (Test-CommandPresent 'packer') { Write-SocoolDebug 'packer: present'; return }
    Confirm-SocoolInstall 'packer'
    switch (Get-SocoolPackageManager) {
        'winget' { Install-SocoolWingetPackage -Id 'Hashicorp.Packer' }
        'choco'  { Install-SocoolChocoPackage  -Name 'packer' }
        default  { Exit-Socool 21 'use setup.sh on Linux/macOS to install packer.' }
    }
}

function Install-SocoolVagrant {
    if (Test-CommandPresent 'vagrant') { Write-SocoolDebug 'vagrant: present'; return }
    Confirm-SocoolInstall 'vagrant'
    switch (Get-SocoolPackageManager) {
        'winget' { Install-SocoolWingetPackage -Id 'Hashicorp.Vagrant' }
        'choco'  { Install-SocoolChocoPackage  -Name 'vagrant' }
        default  { Exit-Socool 21 'use setup.sh on Linux/macOS to install vagrant.' }
    }
}

function Install-SocoolHypervisor {
    param([Parameter(Mandatory)][ValidateSet('virtualbox','libvirt')][string]$Hypervisor)
    switch ($Hypervisor) {
        'virtualbox' {
            if (Test-VBoxManageAvailable) { Write-SocoolDebug 'virtualbox: present'; return }
            Confirm-SocoolInstall 'virtualbox'
            switch (Get-SocoolPackageManager) {
                'winget' { Install-SocoolWingetPackage -Id 'Oracle.VirtualBox' }
                'choco'  { Install-SocoolChocoPackage  -Name 'virtualbox' }
                default  { Exit-Socool 21 'use setup.sh on Linux/macOS to install virtualbox.' }
            }
            # Re-scan PATH so subsequent VBoxManage calls see it.
            $env:PATH = ($env:PATH + ';' + (Join-Path $env:ProgramFiles 'Oracle/VirtualBox'))
        }
        'libvirt' {
            Exit-Socool 30 'libvirt/QEMU is not supported on Windows by SOCool. Switch to VirtualBox (SOCOOL_HYPERVISOR=virtualbox) or run on Linux/macOS.'
        }
    }
}

function Install-SocoolDeps {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateSet('virtualbox','libvirt')][string]$Hypervisor)
    if ($IsWindows) { Assert-WindowsAdmin }
    Write-SocoolInfo ("resolving dependencies (pkg manager: {0})" -f (Get-SocoolPackageManager))
    Install-SocoolGit
    Install-SocoolPython
    Install-SocoolHypervisor -Hypervisor $Hypervisor
    Install-SocoolPacker
    Install-SocoolVagrant
    Write-SocoolInfo 'dependencies ready'
}
