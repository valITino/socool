#Requires -Version 7.0
# scripts/preflight/checks/check-hypervisor-conflict.ps1
# Windows: detect Hyper-V / WSL2 / Docker Desktop which degrade or
# destabilise VirtualBox.
# Exit 0 on pass; exit 16 on fail.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..' '..' 'lib' 'common.ps1')

if (-not $IsWindows) {
    Write-SocoolInfo 'hypervisor-conflict: n/a on non-Windows hosts'
    exit 0
}

$conflicts = Test-SocoolWindowsHypervisorConflict

if ($conflicts.Count -eq 0) {
    Write-SocoolInfo 'hypervisor-conflict: no Windows conflicts detected'
    exit 0
}

$remediation = ("VirtualBox on Windows conflicts with: {0}. Disable Hyper-V with 'bcdedit /set hypervisorlaunchtype off' (as Administrator, then reboot) OR move SOCool to a Linux host. See docs/adr/0002-hypervisor-matrix.md." -f ($conflicts -join ', '))
Exit-Socool 16 $remediation
