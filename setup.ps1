#Requires -Version 7.0
<#
.SYNOPSIS
    SOCool entry point for Windows (and cross-platform PowerShell 7).
.DESCRIPTION
    Runs preflight, installs deps, resolves hypervisor, drives provisioning.
    Parity counterpart: setup.sh. Every parameter, prompt, env var, and exit
    code here MUST have an equivalent there.
.NOTES
    Exit codes: see scripts/preflight/README.md and docs/troubleshooting.md.
#>
[CmdletBinding()]
param(
    [switch]$Help,
    [switch]$Version,
    [Alias('y')][switch]$Yes,
    [ValidateSet('virtualbox','libvirt')] [string]$Hypervisor,
    [ValidateSet('nessus','openvas','none')] [string]$Scanner,
    [ValidateSet('eval','iso')] [string]$WindowsSource,
    [string]$WindowsIso,
    [switch]$AllowBridged,
    [ValidateSet('debug','info','warn','error')] [string]$LogLevel
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

$SocoolVersion = '0.1.0-dev'
$ScriptDir = $PSScriptRoot

. (Join-Path $ScriptDir 'scripts/lib/common.ps1')
. (Join-Path $ScriptDir 'scripts/lib/hypervisor.ps1')
. (Join-Path $ScriptDir 'scripts/lib/deps.ps1')
. (Join-Path $ScriptDir 'scripts/provision/run-pipeline.ps1')

# ────────────────────────────────────────────────────────────────────────
# Help / version / flag → env-var fan-out
# ────────────────────────────────────────────────────────────────────────

function Show-Usage {
    @"
setup.ps1 -- SOCool $SocoolVersion

Usage: ./setup.ps1 [flags]

Flags:
  -Help                      Show this help and exit.
  -Version                   Show version and exit.
  -Yes (-y)                  Non-interactive mode (SOCOOL_YES=1). Fails
                             fast if any required env var is unset.
  -Hypervisor <v>            virtualbox | libvirt. (SOCOOL_HYPERVISOR)
  -Scanner <v>               nessus | openvas | none. (SOCOOL_SCANNER)
  -WindowsSource <v>         eval | iso. (SOCOOL_WINDOWS_SOURCE)
  -WindowsIso <path>         Absolute path to a Windows ISO, required
                             when -WindowsSource iso. (SOCOOL_WINDOWS_ISO_PATH)
  -AllowBridged              Permit bridged networking. Off by default;
                             the lab is host-only/internal to preserve
                             isolation. (SOCOOL_ALLOW_BRIDGED=1)
  -LogLevel <l>              debug | info | warn | error. (SOCOOL_LOG_LEVEL)

Environment variables are read from .env in the repo root if it exists;
command-line flags override env vars.

Exit codes: see scripts/preflight/README.md and docs/troubleshooting.md.
"@
}

if ($Help) { Show-Usage; exit 0 }
if ($Version) { "SOCool $SocoolVersion"; exit 0 }

if ($Yes)            { $env:SOCOOL_YES            = '1' }
if ($Hypervisor)     { $env:SOCOOL_HYPERVISOR     = $Hypervisor }
if ($Scanner)        { $env:SOCOOL_SCANNER        = $Scanner }
if ($WindowsSource)  { $env:SOCOOL_WINDOWS_SOURCE = $WindowsSource }
if ($WindowsIso)     { $env:SOCOOL_WINDOWS_ISO_PATH = $WindowsIso }
if ($AllowBridged)   { $env:SOCOOL_ALLOW_BRIDGED  = '1' }
if ($LogLevel)       { $env:SOCOOL_LOG_LEVEL      = $LogLevel }

# ────────────────────────────────────────────────────────────────────────
# High-level user decisions
# ────────────────────────────────────────────────────────────────────────

function Resolve-ScannerChoice {
    if (-not [string]::IsNullOrEmpty($env:SOCOOL_SCANNER)) {
        if ($env:SOCOOL_SCANNER -notin @('nessus','openvas','none')) {
            Exit-Socool 2 ("invalid SOCOOL_SCANNER='{0}' (expected nessus, openvas, or none)" -f $env:SOCOOL_SCANNER)
        }
        Write-SocoolInfo ("scanner: {0} (from env)" -f $env:SOCOOL_SCANNER)
        return
    }
    Show-SocoolAction `
        -Title   'Pick a vulnerability scanner' `
        -What    "SOCool can include one scanner VM: Nessus Essentials (Tenable, free with activation key) or OpenVAS/GVM (Greenbone, open source). Pick 'none' to skip." `
        -Where   'https://www.tenable.com/products/nessus/nessus-essentials  or  https://greenbone.github.io/docs/latest/' `
        -Paste   'nessus, openvas, or none' `
        -EnvName 'SOCOOL_SCANNER'
    $chosen = Read-SocoolPrompt -Label 'scanner' -Question 'Scanner' -Default 'openvas' -EnvName 'SOCOOL_SCANNER'
    if ($chosen -notin @('nessus','openvas','none')) {
        Exit-Socool 2 ("invalid scanner choice: '{0}'" -f $chosen)
    }
    $env:SOCOOL_SCANNER = $chosen
    Write-SocoolInfo ("scanner: {0}" -f $chosen)
}

function Resolve-WindowsSource {
    if (-not [string]::IsNullOrEmpty($env:SOCOOL_WINDOWS_SOURCE)) {
        switch ($env:SOCOOL_WINDOWS_SOURCE) {
            'eval'  { Write-SocoolInfo 'windows-source: eval (from env)'; return }
            'iso'   {
                if ([string]::IsNullOrEmpty($env:SOCOOL_WINDOWS_ISO_PATH)) {
                    Exit-Socool 2 'SOCOOL_WINDOWS_SOURCE=iso requires SOCOOL_WINDOWS_ISO_PATH'
                }
                if (-not (Test-Path -LiteralPath $env:SOCOOL_WINDOWS_ISO_PATH)) {
                    Exit-Socool 2 ("SOCOOL_WINDOWS_ISO_PATH does not exist: {0}" -f $env:SOCOOL_WINDOWS_ISO_PATH)
                }
                Write-SocoolInfo ("windows-source: iso ({0}, from env)" -f $env:SOCOOL_WINDOWS_ISO_PATH)
                return
            }
            'msdev' { Exit-Socool 2 "SOCOOL_WINDOWS_SOURCE=msdev is no longer supported: Microsoft's Windows dev VM page has been unavailable since October 2024. Use 'eval' (Evaluation Center ISO) or 'iso' (provide your own)." }
            default { Exit-Socool 2 ("invalid SOCOOL_WINDOWS_SOURCE='{0}' (expected eval or iso)" -f $env:SOCOOL_WINDOWS_SOURCE) }
        }
    }
    Show-SocoolAction `
        -Title   'Windows victim VM source' `
        -What    'SOCool can download the free Windows 11 Enterprise evaluation ISO (90-day, no product key required) and run an unattended install, or build from a Windows ISO you provide.' `
        -Where   'https://www.microsoft.com/en-us/evalcenter/evaluate-windows-11-enterprise' `
        -Paste   'eval (auto-download evaluation ISO) or iso (you provide a path)' `
        -EnvName 'SOCOOL_WINDOWS_SOURCE'
    $chosen = Read-SocoolPrompt -Label 'windows-source' -Question 'Source' -Default 'eval' -EnvName 'SOCOOL_WINDOWS_SOURCE'
    switch ($chosen) {
        'eval'  { $env:SOCOOL_WINDOWS_SOURCE = 'eval' }
        'iso'   {
            $env:SOCOOL_WINDOWS_SOURCE = 'iso'
            Show-SocoolAction `
                -Title   'Windows ISO path' `
                -What    'Absolute path to your Windows ISO (Microsoft Evaluation Center or your own licensed media).' `
                -Where   'https://www.microsoft.com/en-us/evalcenter/' `
                -Paste   'absolute path to the .iso file' `
                -EnvName 'SOCOOL_WINDOWS_ISO_PATH'
            $isoPath = Read-SocoolPrompt -Label 'windows-iso' -Question 'ISO path' -Default '' -EnvName 'SOCOOL_WINDOWS_ISO_PATH'
            if ([string]::IsNullOrEmpty($isoPath)) { Exit-Socool 2 'ISO path is required when -WindowsSource iso' }
            if (-not (Test-Path -LiteralPath $isoPath)) { Exit-Socool 2 ("ISO not found at: {0}" -f $isoPath) }
            $env:SOCOOL_WINDOWS_ISO_PATH = $isoPath
        }
        default { Exit-Socool 2 ("invalid windows-source choice: '{0}'" -f $chosen) }
    }
    Write-SocoolInfo ("windows-source: {0}" -f $env:SOCOOL_WINDOWS_SOURCE)
}

function Confirm-BridgedIfRequested {
    if ($env:SOCOOL_ALLOW_BRIDGED -ne '1') { return }
    Write-SocoolBanner 'Bridged networking enabled'
    Write-SocoolWarn 'SOCOOL_ALLOW_BRIDGED=1 -- the lab will bridge to your real LAN.'
    Write-SocoolWarn 'This undermines the default isolation. Attacker VM traffic may reach real hosts on your network.'
    $answer = Read-SocoolYesNo -Label 'bridged-confirm' `
                               -Question 'Are you sure you want to bridge the lab to your LAN?' `
                               -Default 'n' -EnvName 'SOCOOL_YES'
    if ($answer -ne 'y') { Exit-Socool 2 'bridged networking not confirmed; re-run without -AllowBridged' }
}

# ────────────────────────────────────────────────────────────────────────
# Final summary
# ────────────────────────────────────────────────────────────────────────

function Show-FinalSummary {
    Write-SocoolBanner 'SOCool setup complete'
    [Console]::Error.WriteLine('Lab components:')

    foreach ($vm in (Get-SocoolVmHostnames)) {
        if ([string]::IsNullOrWhiteSpace($vm)) { continue }
        if ($vm -eq 'nessus'  -and $env:SOCOOL_SCANNER -ne 'nessus')  { continue }
        if ($vm -eq 'openvas' -and $env:SOCOOL_SCANNER -ne 'openvas') { continue }

        $idx = Get-LabVmIndex -Hostname $vm
        $role = Get-SocoolLabConfig -Path ("vms.{0}.role" -f $idx)
        $ip = try { Get-SocoolLabConfig -Path ("vms.{0}.ip" -f $idx) } catch { '(multi-homed)' }

        [Console]::Error.WriteLine(('  {0,-16}  role={1,-9}  ip={2}' -f $vm, $role, $ip))

        $creds = Join-Path $script:SocoolRepoRoot ("packer/{0}/artifacts/credentials.json" -f $vm)
        if (Test-Path -LiteralPath $creds) {
            Write-SocoolInfo ("    credentials (rotated): {0}" -f $creds)
        } else {
            Write-SocoolWarn ("    credentials manifest not found: {0} (Step 5 will populate this)" -f $creds)
        }
    }

    [Console]::Error.WriteLine('')
    [Console]::Error.WriteLine('Next steps:')
    [Console]::Error.WriteLine('  - pfSense webConfigurator:  https://10.42.20.1/')
    [Console]::Error.WriteLine('  - Wazuh dashboard:          https://10.42.20.10/')
    [Console]::Error.WriteLine('  - Kali (SSH):               ssh vagrant@10.42.10.10')
    [Console]::Error.WriteLine('  - Windows victim (RDP):     10.42.10.20:3389')
    [Console]::Error.WriteLine('  - Destroy the lab:          Push-Location vagrant; vagrant destroy -f; Pop-Location')
}

# ────────────────────────────────────────────────────────────────────────
# Main
# ────────────────────────────────────────────────────────────────────────

function Invoke-Main {
    Import-SocoolEnvFile

    Write-SocoolBanner ("SOCool {0}" -f $SocoolVersion)
    Get-SocoolHost

    # Step 2: preflight.
    & pwsh -NoProfile -File (Join-Path $ScriptDir 'scripts/preflight/run-all.ps1')
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    # Step 4: hypervisor.
    $hv = Resolve-SocoolHypervisor
    $env:SOCOOL_HYPERVISOR = $hv

    # Step 5: Windows source.
    Resolve-WindowsSource

    # Step 6: scanner choice.
    Resolve-ScannerChoice

    # Step 3: deps (after hypervisor choice -- deps must target a
    # specific hypervisor package).
    Install-SocoolDeps -Hypervisor $hv

    # Safety check, not a numbered step: warn and re-confirm if the user
    # opted into bridged networking (breaks default isolation).
    Confirm-BridgedIfRequested

    # Step 7: provisioning pipeline (templates/Vagrantfile from Steps 5/6
    # land later; missing artifacts are reported cleanly).
    $scannerChoice = if ([string]::IsNullOrEmpty($env:SOCOOL_SCANNER)) { 'none' } else { $env:SOCOOL_SCANNER }
    Invoke-SocoolProvisionPipeline `
        -Hypervisor    $hv `
        -Scanner       $scannerChoice `
        -WindowsSource $env:SOCOOL_WINDOWS_SOURCE

    # Step 8: final summary.
    Show-FinalSummary
}

Invoke-Main
