#Requires -Version 7.0
# scripts/preflight/checks/check-memory.ps1
# Verifies host has enough free RAM for the non-optional lab VMs plus
# a 4 GB headroom.
# Exit 0 on pass; exit 14 on fail.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..' '..' 'lib' 'common.ps1')

$configFile = Join-Path $script:SocoolRepoRoot 'config/lab.yml'
$pyScript = @'
import sys, yaml
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)
print(sum(v['ram_mb'] for v in data.get('vms', []) if not v.get('optional', False)))
'@
try {
    $requiredMb = [int](& python3 -c $pyScript $configFile)
} catch {
    Exit-Socool 14 ("unable to parse config/lab.yml via python3: {0}. Ensure python3 + PyYAML are installed." -f $_.Exception.Message)
}
$headroomMb  = 4096
$thresholdMb = $requiredMb + $headroomMb

try {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
} catch {
    Exit-Socool 14 ("unable to query Win32_OperatingSystem: {0}" -f $_.Exception.Message)
}
# FreePhysicalMemory is in KB.
$freeMb = [int]([long]$os.FreePhysicalMemory / 1024)

if ($freeMb -lt $thresholdMb) {
    Exit-Socool 14 ("insufficient free RAM: host has {0} MB free, lab needs {1} MB + {2} MB headroom = {3} MB. Close other applications, or edit config/lab.yml to reduce per-VM ram_mb." -f $freeMb, $requiredMb, $headroomMb, $thresholdMb)
}

Write-SocoolInfo ("memory: {0} MB free, needs {1} MB (required {2} MB + {3} MB headroom)" -f $freeMb, $thresholdMb, $requiredMb, $headroomMb)
