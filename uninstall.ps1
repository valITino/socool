#Requires -Version 7.0
<#
.SYNOPSIS
    SOCool uninstall entry point for Windows (and cross-platform PowerShell 7).
.DESCRIPTION
    Tears down what setup.ps1 installed: VMs, boxes, caches, plugins, and
    (opt-in) host packages.
    Parity counterpart: uninstall.sh. Every parameter, prompt, env var, and
    exit code here MUST have an equivalent there.
.NOTES
    Exit codes: 0 success; 80-86 documented in scripts/uninstall/run-all.ps1.
#>
[CmdletBinding()]
param(
    [switch]$Help,
    [switch]$Version,
    [Alias('y')][switch]$Yes,
    [switch]$DryRun,
    [switch]$KeepVms,
    [switch]$KeepBoxes,
    [switch]$KeepPlugins,
    [switch]$KeepCache,
    [Alias('Env')][switch]$EnvFile,
    [switch]$Packages,
    [switch]$All,
    [ValidateSet('virtualbox','libvirt')][string]$Hypervisor,
    [ValidateSet('debug','info','warn','error')][string]$LogLevel
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

$SocoolVersion = '0.1.0-dev'
$ScriptDir = $PSScriptRoot

. (Join-Path $ScriptDir 'scripts/lib/common.ps1')
. (Join-Path $ScriptDir 'scripts/lib/deps.ps1')
. (Join-Path $ScriptDir 'scripts/uninstall/run-all.ps1')

function Show-Usage {
    @"
uninstall.ps1 -- SOCool $SocoolVersion

Usage: ./uninstall.ps1 [flags]

Removes the SOCool lab from this host. By default this:
  - destroys lab VMs (vagrant destroy -f)
  - removes the local socool-* Vagrant boxes
  - uninstalls the vagrant-libvirt plugin (if present)
  - clears caches and rotated-credential artifacts under the repo

By default this does NOT:
  - delete .env (pass -EnvFile)
  - uninstall host packages like packer, vagrant, virtualbox (pass -Packages)
  - delete the repo itself (instructions printed at the end)

Flags:
  -Help                      Show this help and exit.
  -Version                   Show version and exit.
  -Yes (-y)                  Non-interactive mode. Skips every confirmation.
                             Required for CI. (SOCOOL_YES=1)
  -DryRun                    Print what would happen, but make no changes.
                             (SOCOOL_UNINSTALL_DRY_RUN=1)
  -KeepVms                   Skip the vagrant destroy phase.
                             (SOCOOL_UNINSTALL_VMS=0)
  -KeepBoxes                 Skip the vagrant box remove phase.
                             (SOCOOL_UNINSTALL_BOXES=0)
  -KeepPlugins               Skip the vagrant plugin uninstall phase.
                             (SOCOOL_UNINSTALL_VAGRANT_PLUGINS=0)
  -KeepCache                 Skip the cache and artifacts phase.
                             (SOCOOL_UNINSTALL_CACHES=0)
  -EnvFile                   Also remove .env (with extra confirmation).
                             (SOCOOL_UNINSTALL_ENV=1)
  -Packages                  Also uninstall host packages (packer, vagrant,
                             hypervisor). Will break other projects that
                             rely on these tools -- use carefully.
                             (SOCOOL_UNINSTALL_PACKAGES=1)
  -All                       Remove everything: VMs + boxes + plugins +
                             cache + .env + host packages.
  -Hypervisor <v>            virtualbox | libvirt. Tells the package phase
                             which hypervisor stack to remove. If unset
                             when -Packages is on, both are attempted.
                             (SOCOOL_HYPERVISOR)
  -LogLevel <l>              debug | info | warn | error. (SOCOOL_LOG_LEVEL)

Environment variables are read from .env if present; flags override them.

Exit codes: 0 success; 80-86 documented in scripts/uninstall/run-all.ps1.
"@
}

if ($Help)    { Show-Usage; exit 0 }
if ($Version) { "SOCool $SocoolVersion (uninstall)"; exit 0 }

if ($Yes)         { $env:SOCOOL_YES = '1' }
if ($DryRun)      { $env:SOCOOL_UNINSTALL_DRY_RUN = '1' }
if ($KeepVms)     { $env:SOCOOL_UNINSTALL_VMS = '0' }
if ($KeepBoxes)   { $env:SOCOOL_UNINSTALL_BOXES = '0' }
if ($KeepPlugins) { $env:SOCOOL_UNINSTALL_VAGRANT_PLUGINS = '0' }
if ($KeepCache)   { $env:SOCOOL_UNINSTALL_CACHES = '0' }
if ($EnvFile)     { $env:SOCOOL_UNINSTALL_ENV = '1' }
if ($Packages)    { $env:SOCOOL_UNINSTALL_PACKAGES = '1' }
if ($All) {
    $env:SOCOOL_UNINSTALL_VMS             = '1'
    $env:SOCOOL_UNINSTALL_BOXES           = '1'
    $env:SOCOOL_UNINSTALL_VAGRANT_PLUGINS = '1'
    $env:SOCOOL_UNINSTALL_CACHES          = '1'
    $env:SOCOOL_UNINSTALL_ENV             = '1'
    $env:SOCOOL_UNINSTALL_PACKAGES        = '1'
}
if ($Hypervisor)  { $env:SOCOOL_HYPERVISOR = $Hypervisor }
if ($LogLevel)    { $env:SOCOOL_LOG_LEVEL = $LogLevel }

function Invoke-Main {
    Import-SocoolEnvFile
    Write-SocoolBanner ("SOCool {0} (uninstall)" -f $SocoolVersion)
    Get-SocoolHost
    Invoke-SocoolUninstall
}

Invoke-Main
