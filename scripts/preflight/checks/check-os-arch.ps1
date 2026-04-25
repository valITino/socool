#Requires -Version 7.0
# scripts/preflight/checks/check-os-arch.ps1
# Verifies the host OS + architecture is in the supported set.
# Exit 0 on pass; exit 11 with a remediation sentence on fail.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..' '..' 'lib' 'common.ps1')

Get-SocoolHost

$pair = "{0}:{1}" -f $env:SOCOOL_OS, $env:SOCOOL_ARCH
switch ($pair) {
    'windows:x86_64' { Write-SocoolInfo ("os-arch: {0} (supported)" -f $pair); exit 0 }
    'windows:aarch64' { Exit-Socool 11 'Windows on aarch64 is unsupported by SOCool; use an x86_64 Windows host or switch to Linux/macOS.' }
    default {
        if ($env:SOCOOL_OS -eq 'linux' -or $env:SOCOOL_OS -eq 'darwin') {
            Exit-Socool 11 ("setup.ps1 on {0} is not the recommended entry point; use setup.sh on Linux/macOS." -f $env:SOCOOL_OS)
        }
        Exit-Socool 11 ("unsupported host OS/arch '{0}'; see docs/adr/0002-hypervisor-matrix.md for the supported set." -f $pair)
    }
}
