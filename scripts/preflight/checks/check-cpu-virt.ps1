#Requires -Version 7.0
# scripts/preflight/checks/check-cpu-virt.ps1
# Verifies hardware CPU virtualization is available and enabled.
# Exit 0 on pass; exit 12 with a remediation sentence on fail.
#
# Detection combines two Win32_Processor signals because either alone
# can be misleading:
#   VirtualizationFirmwareEnabled — BIOS/UEFI has enabled VT-x/AMD-V
#   VMMonitorModeExtensions      — CPU supports the Vanderpool/SVM
#                                   instruction set
# Both should be true on a host SOCool can use.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..' '..' 'lib' 'common.ps1')

if (-not $IsWindows) {
    Exit-Socool 12 'check-cpu-virt.ps1 should not run on non-Windows hosts; use check-cpu-virt.sh on Linux/macOS.'
}

try {
    $cpu = Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop | Select-Object -First 1
} catch {
    Exit-Socool 12 ("unable to query Win32_Processor: {0}. Re-run from an elevated PowerShell 7 prompt." -f $_.Exception.Message)
}

$firmware = [bool]$cpu.VirtualizationFirmwareEnabled
$vmmonitor = [bool]$cpu.VMMonitorModeExtensions

if ($firmware -and $vmmonitor) {
    Write-SocoolInfo 'cpu-virt: enabled (VirtualizationFirmwareEnabled=True, VMMonitorModeExtensions=True)'
    exit 0
}

if (-not $vmmonitor) {
    Exit-Socool 12 'CPU does not expose Vanderpool/SVM virtualization extensions (VMMonitorModeExtensions=False); the hardware is too old for SOCool.'
}

# Hardware can do it, but firmware has it disabled.
Exit-Socool 12 'CPU virtualization is disabled in firmware (VirtualizationFirmwareEnabled=False); enable Intel VT-x or AMD-V in your BIOS/UEFI and reboot.'
