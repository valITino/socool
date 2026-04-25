#Requires -Version 7.0
# scripts/preflight/checks/check-disk.ps1
# Verifies host has enough free disk on the Packer box output volume
# for the non-optional lab VMs plus 20 GB headroom.
# Exit 0 on pass; exit 15 on fail.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..' '..' 'lib' 'common.ps1')

$configFile = Join-Path $script:SocoolRepoRoot 'config/lab.yml'
$pyScript = @'
import sys, yaml
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)
print(sum(v['disk_gb'] for v in data.get('vms', []) if not v.get('optional', False)))
'@
try {
    $requiredGb = [int](& python3 -c $pyScript $configFile)
} catch {
    Exit-Socool 15 ("unable to parse config/lab.yml via python3: {0}. Ensure python3 + PyYAML are installed." -f $_.Exception.Message)
}
$headroomGb  = 20
$thresholdGb = $requiredGb + $headroomGb

$targetDir = $env:SOCOOL_BOX_OUTPUT_DIR
if ([string]::IsNullOrEmpty($targetDir)) {
    $targetDir = Join-Path $script:SocoolRepoRoot '.socool-cache'
}

# Walk up to the nearest existing ancestor so Get-PSDrive sees a path.
$probeDir = $targetDir
while (-not (Test-Path -LiteralPath $probeDir)) {
    $parent = Split-Path -Parent $probeDir
    if ([string]::IsNullOrEmpty($parent) -or $parent -eq $probeDir) { break }
    $probeDir = $parent
}

try {
    $driveLetter = (Split-Path -Qualifier $probeDir).TrimEnd(':')
    $drive = Get-PSDrive -Name $driveLetter -ErrorAction Stop
} catch {
    Exit-Socool 15 ("unable to determine free disk on {0}: {1}" -f $probeDir, $_.Exception.Message)
}
$freeGb = [int]([long]$drive.Free / 1GB)

if ($freeGb -lt $thresholdGb) {
    Exit-Socool 15 ("insufficient free disk on {0}: {1} GB free, lab needs {2} GB + {3} GB headroom = {4} GB. Free space, or set SOCOOL_BOX_OUTPUT_DIR to a larger volume." -f $probeDir, $freeGb, $requiredGb, $headroomGb, $thresholdGb)
}

Write-SocoolInfo ("disk: {0} GB free on {1}, needs {2} GB" -f $freeGb, $probeDir, $thresholdGb)
