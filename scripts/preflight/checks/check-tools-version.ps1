#Requires -Version 7.0
# scripts/preflight/checks/check-tools-version.ps1
# Verifies every required host tool that is ALREADY INSTALLED meets
# its minimum version. Missing tools are not an error here — deps.ps1
# installs them.
# Exit 0 on pass; exit 17 on fail.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..' '..' 'lib' 'common.ps1')

function script:Test-MinVersion {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$MinVersion,
        [Parameter(Mandatory)][string]$Actual
    )
    # Strip non-numeric / non-dot prefixes (e.g. "v1.11.2", "7.1.4r165100").
    $cleanedActual = [regex]::Match($Actual, '\d+(\.\d+)+').Value
    if ([string]::IsNullOrEmpty($cleanedActual)) {
        Exit-Socool 17 ("{0} version string '{1}' did not parse; upgrade and re-run." -f $Name, $Actual)
    }
    try {
        $a = [version]$cleanedActual
        $m = [version]$MinVersion
    } catch {
        Exit-Socool 17 ("{0} version parse failed: '{1}' vs min '{2}'" -f $Name, $Actual, $MinVersion)
    }
    if ($a -lt $m) {
        Exit-Socool 17 ("{0} version {1} is older than the minimum {2}; upgrade via your package manager and re-run." -f $Name, $cleanedActual, $MinVersion)
    }
    Write-SocoolInfo ("{0}: {1} (>= {2})" -f $Name, $cleanedActual, $MinVersion)
}

function script:Test-CommandVersion {
    param(
        [Parameter(Mandatory)][string]$Command,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$MinVersion,
        [Parameter(Mandatory)][string[]]$VersionArgs,
        [Parameter(Mandatory)][scriptblock]$Extract
    )
    if (-not (Get-Command $Command -ErrorAction SilentlyContinue)) { return }
    try {
        $out = & $Command @VersionArgs 2>&1
    } catch {
        return  # Tool errored on --version; let deps.ps1 reinstall.
    }
    $actual = & $Extract $out
    if ([string]::IsNullOrEmpty($actual)) { return }
    Test-MinVersion -Name $Name -MinVersion $MinVersion -Actual $actual
}

# PowerShell itself — we already require >=7 via #Requires, but record.
Write-SocoolInfo ("powershell: {0} (>= 7.0)" -f $PSVersionTable.PSVersion)

Test-CommandVersion -Command 'git'     -Name 'git'        -MinVersion '2.30' `
    -VersionArgs @('--version') -Extract { param($o) ($o -split ' ')[2] }
Test-CommandVersion -Command 'python3' -Name 'python3'    -MinVersion '3.8' `
    -VersionArgs @('--version') -Extract { param($o) ($o -split ' ')[1] }
Test-CommandVersion -Command 'packer'  -Name 'packer'     -MinVersion '1.10' `
    -VersionArgs @('--version') -Extract { param($o) ($o | Select-Object -First 1) -replace '^v','' }
Test-CommandVersion -Command 'vagrant' -Name 'vagrant'    -MinVersion '2.3' `
    -VersionArgs @('--version') -Extract { param($o) ($o -split ' ')[1] }
Test-CommandVersion -Command 'VBoxManage' -Name 'VirtualBox' -MinVersion '7.0' `
    -VersionArgs @('--version') -Extract { param($o) $o -replace 'r.*$','' }

Write-SocoolInfo 'tools-version: all installed tools meet their minimums'
