#Requires -Version 7.0
# scripts/preflight/checks/check-network-cidr.ps1
# Verifies none of the lab CIDRs overlap with an existing host network.
# Exit 0 on pass; exit 18 on fail.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..' '..' 'lib' 'common.ps1')

if (-not $IsWindows) {
    Exit-Socool 18 'check-network-cidr.ps1 should not run on non-Windows hosts; use check-network-cidr.sh.'
}

# Gather host routes. Get-NetRoute returns DestinationPrefix in
# "a.b.c.d/nn" form, which ipaddress can parse directly.
try {
    $hostNets = Get-NetRoute -AddressFamily IPv4 -ErrorAction Stop |
                Select-Object -ExpandProperty DestinationPrefix |
                Where-Object { $_ -and $_ -notmatch '^127\.' -and $_ -notmatch '/32$' }
} catch {
    Exit-Socool 18 ("unable to enumerate host routes: {0}" -f $_.Exception.Message)
}

$configFile = Join-Path $script:SocoolRepoRoot 'config/lab.yml'
$pyScript = @'
import ipaddress, sys, yaml
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)
lab_nets = []
for role, spec in (data.get('network') or {}).items():
    try:
        lab_nets.append((role, ipaddress.ip_network(spec['cidr'], strict=False)))
    except (ValueError, KeyError):
        continue

hits = []
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        hn = ipaddress.ip_network(line, strict=False)
    except ValueError:
        continue
    if hn.prefixlen in (32, 128):
        continue
    for role, ln in lab_nets:
        if hn.overlaps(ln):
            hits.append(f"{role}={ln} overlaps host route {hn}")
if hits:
    for h in hits:
        print(h)
    sys.exit(1)
'@

$overlap = ($hostNets | & python3 -c $pyScript $configFile)

if ($LASTEXITCODE -ne 0 -and -not [string]::IsNullOrWhiteSpace($overlap)) {
    foreach ($line in ($overlap -split [Environment]::NewLine)) {
        if (-not [string]::IsNullOrWhiteSpace($line)) { Write-SocoolError ("  {0}" -f $line) }
    }
    Exit-Socool 18 'lab CIDR conflicts with an existing host network; disconnect the conflicting interface, or edit config/lab.yml to pick different ranges.'
}

Write-SocoolInfo 'network-cidr: no overlaps with host routes'
