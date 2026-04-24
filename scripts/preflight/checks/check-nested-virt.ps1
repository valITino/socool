#Requires -Version 7.0
# scripts/preflight/checks/check-nested-virt.ps1
# Verifies nested virtualization capability on Windows.
# Exit 0 on pass; exit 13 with a remediation sentence on fail.
#
# Strategy: VirtualBox exposes nested virt as a per-VM setting. We do
# a CPU-level capability probe via Win32_Processor.SecondLevelAddress
# TranslationExtensions (EPT/RVI) plus VMMonitorModeExtensions. If both
# are true, nested virt is typically available. If Hyper-V is active
# on the host, VirtualBox nested virt becomes unreliable — that case
# is caught by check-hypervisor-conflict, not here.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..' '..' 'lib' 'common.ps1')

if (-not $IsWindows) {
    Exit-Socool 13 'check-nested-virt.ps1 should not run on non-Windows hosts; use check-nested-virt.sh on Linux/macOS.'
}

try {
    $cpu = Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop | Select-Object -First 1
} catch {
    Exit-Socool 13 ("unable to query Win32_Processor: {0}. Re-run from an elevated PowerShell 7 prompt." -f $_.Exception.Message)
}

$slat = [bool]$cpu.SecondLevelAddressTranslationExtensions
$vmmonitor = [bool]$cpu.VMMonitorModeExtensions

if ($slat -and $vmmonitor) {
    Write-SocoolInfo 'nested-virt: likely supported (SLAT=True, VMMonitorModeExtensions=True). Scanner VM will probe per-VM at build time.'
    exit 0
}

Exit-Socool 13 'nested virtualization capability cannot be confirmed on this CPU (SLAT or VMMonitorModeExtensions missing); the Nessus / OpenVAS VM requires it. Run with SOCOOL_SCANNER=none or use a host CPU that supports EPT/RVI.'
