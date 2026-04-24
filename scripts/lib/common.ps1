# scripts/lib/common.ps1 — shared PowerShell helpers for SOCool.
#
# Dot-sourced by setup.ps1 and scripts under scripts/. Public ABI
# (kept in parity with scripts/lib/common.sh):
#
#   Get-SocoolHost                       -> sets $env:SOCOOL_OS / SOCOOL_ARCH
#   Write-SocoolDebug / Info / Warn / Error <msg>
#   Exit-Socool <exit_code> <message>    -> print and exit
#   Write-SocoolBanner <title>
#   Show-SocoolAction <title> <what> <where> <paste> <envName>
#   Read-SocoolPrompt <label> <question> <default> <envName>
#   Read-SocoolYesNo <label> <question> <default:y|n> <envName>
#   Assert-TtyOrEnv <envName>
#   Import-SocoolEnvFile
#   Get-SocoolLabConfig <path>
#   Get-SocoolVmHostnames                -> boot-ordered list
#   Assert-SocoolHostnameToken <value>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

if ($script:SocoolCommonLoaded) { return }
$script:SocoolCommonLoaded = $true

$script:SocoolRepoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..' '..')).Path

# ────────────────────────────────────────────────────────────────────────
# Logging
# ────────────────────────────────────────────────────────────────────────

function script:Get-SocoolLogLevelNum {
    switch (($env:SOCOOL_LOG_LEVEL | ForEach-Object { if ($_) { $_ } else { 'info' } })) {
        'debug' { 10 }
        'info'  { 20 }
        'warn'  { 30 }
        'error' { 40 }
        default { 20 }
    }
}

function script:Write-SocoolLog {
    param([int]$LevelNum, [string]$Tag, [string]$Message)
    if ($LevelNum -lt (Get-SocoolLogLevelNum)) { return }
    # Write to the host's error stream so stdout stays clean for
    # machine-parseable output (final summary, return values).
    [Console]::Error.WriteLine(('[{0,-5}] {1}' -f $Tag, $Message))
}

function Write-SocoolDebug { param([string]$Message) Write-SocoolLog 10 'DEBUG' $Message }
function Write-SocoolInfo  { param([string]$Message) Write-SocoolLog 20 'INFO'  $Message }
function Write-SocoolWarn  { param([string]$Message) Write-SocoolLog 30 'WARN'  $Message }
function Write-SocoolError { param([string]$Message) Write-SocoolLog 40 'ERROR' $Message }

function Exit-Socool {
    param(
        [Parameter(Mandatory)][int]$Code,
        [Parameter(Mandatory)][string]$Message
    )
    Write-SocoolError $Message
    exit $Code
}

function Write-SocoolBanner {
    param([Parameter(Mandatory)][string]$Title)
    [Console]::Error.WriteLine('')
    [Console]::Error.WriteLine(('━━━ {0} ━━━' -f $Title))
}

# ────────────────────────────────────────────────────────────────────────
# Host detection
# ────────────────────────────────────────────────────────────────────────

function Get-SocoolHost {
    [CmdletBinding()]
    param()

    $os = 'unknown'
    if     ($IsWindows) { $os = 'windows' }
    elseif ($IsMacOS)   { $os = 'darwin' }
    elseif ($IsLinux)   { $os = 'linux' }

    $arch = switch ([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture) {
        'X64'   { 'x86_64' }
        'Arm64' { 'aarch64' }
        default { 'unknown' }
    }

    $env:SOCOOL_OS   = $os
    $env:SOCOOL_ARCH = $arch
    Write-SocoolDebug ("host: os={0} arch={1}" -f $os, $arch)
}

# ────────────────────────────────────────────────────────────────────────
# Environment
# ────────────────────────────────────────────────────────────────────────

function Import-SocoolEnvFile {
    $envFile = Join-Path $script:SocoolRepoRoot '.env'
    if (-not (Test-Path -LiteralPath $envFile)) { return }

    Write-SocoolDebug "sourcing $envFile"
    Get-Content -LiteralPath $envFile | ForEach-Object {
        $line = $_.Trim()
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('#')) { return }
        $eq = $line.IndexOf('=')
        if ($eq -lt 1) { return }
        $name  = $line.Substring(0, $eq).Trim()
        $value = $line.Substring($eq + 1).Trim().Trim('"').Trim("'")
        if ($name -notmatch '^[A-Z_][A-Z0-9_]*$') { return }
        Set-Item -Path ("env:{0}" -f $name) -Value $value
    }
}

function Assert-TtyOrEnv {
    param([Parameter(Mandatory)][string]$EnvName)
    $envVal = [Environment]::GetEnvironmentVariable($EnvName)
    $isInteractive = [Environment]::UserInteractive -and -not [Console]::IsInputRedirected
    if (-not $isInteractive -and [string]::IsNullOrEmpty($envVal)) {
        Exit-Socool 64 ("non-interactive run: set {0} to skip this prompt (see .env.example)" -f $EnvName)
    }
}

# ────────────────────────────────────────────────────────────────────────
# Prompts — pause-for-activation
# ────────────────────────────────────────────────────────────────────────

function Show-SocoolAction {
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$What,
        [Parameter(Mandatory)][string]$Where,
        [Parameter(Mandatory)][string]$Paste,
        [Parameter(Mandatory)][string]$EnvName
    )
    Write-SocoolBanner ("Action required: {0}" -f $Title)
    [Console]::Error.WriteLine(('What:  {0}' -f $What))
    [Console]::Error.WriteLine(('Where: {0}' -f $Where))
    [Console]::Error.WriteLine(('Paste: {0}' -f $Paste))
    [Console]::Error.WriteLine(('Env:   {0}' -f $EnvName))
}

function Read-SocoolPrompt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][string]$Question,
        [Parameter(Mandatory)][string]$Default,
        [Parameter(Mandatory)][string]$EnvName
    )
    $envVal = [Environment]::GetEnvironmentVariable($EnvName)
    if (-not [string]::IsNullOrEmpty($envVal)) {
        Write-SocoolDebug ("{0} <- {1}={2}" -f $Label, $EnvName, $envVal)
        return $envVal
    }
    Assert-TtyOrEnv -EnvName $EnvName
    $prompt = ("{0} [{1}]" -f $Question, $Default)
    $answer = Read-Host -Prompt $prompt
    if ([string]::IsNullOrEmpty($answer)) { return $Default }
    return $answer
}

function Read-SocoolYesNo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][string]$Question,
        [Parameter(Mandatory)][ValidateSet('y','n')][string]$Default,
        [Parameter(Mandatory)][string]$EnvName
    )
    $envVal = [Environment]::GetEnvironmentVariable($EnvName)
    if (-not [string]::IsNullOrEmpty($envVal)) {
        switch -regex ($envVal) {
            '^(1|true|yes|y|Y)$'  { return 'y' }
            '^(0|false|no|n|N)$'  { return 'n' }
            default               { Exit-Socool 2 ("invalid {0}='{1}' -- expected 0/1/yes/no" -f $EnvName, $envVal) }
        }
    }
    Assert-TtyOrEnv -EnvName $EnvName
    $hint = if ($Default -eq 'y') { '[Y/n]' } else { '[y/N]' }
    $answer = Read-Host -Prompt ("{0} {1}" -f $Question, $hint)
    if ([string]::IsNullOrEmpty($answer)) { return $Default }
    switch -regex ($answer) {
        '^(y|Y|yes|YES)$' { return 'y' }
        '^(n|N|no|NO)$'   { return 'n' }
        default           { return $Default }
    }
}

# ────────────────────────────────────────────────────────────────────────
# Config loading — reads config/lab.yml via python3 (same path as bash)
# to keep parity. Powershell-yaml is a valid alternative but pulling in an
# extra module for one call isn't worth the install time.
# ────────────────────────────────────────────────────────────────────────

function Get-SocoolLabConfig {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    $configFile = Join-Path $script:SocoolRepoRoot 'config/lab.yml'
    if (-not (Test-Path -LiteralPath $configFile)) {
        Exit-Socool 1 ("config not found: {0}" -f $configFile)
    }
    if (-not (Get-Command python3 -ErrorAction SilentlyContinue)) {
        Exit-Socool 21 'python3 required for config parsing -- install it or run scripts/preflight/run-all.ps1 first'
    }
    $pyScript = @'
import sys, yaml
cfg_path, key_path = sys.argv[1], sys.argv[2]
with open(cfg_path, 'r') as f:
    data = yaml.safe_load(f)
cur = data
for part in key_path.split('.'):
    if isinstance(cur, list):
        try:
            cur = cur[int(part)]
        except (ValueError, IndexError):
            print(f"Get-SocoolLabConfig: key '{key_path}' not found at '{part}'", file=sys.stderr)
            sys.exit(1)
    elif isinstance(cur, dict) and part in cur:
        cur = cur[part]
    else:
        print(f"Get-SocoolLabConfig: key '{key_path}' not found at '{part}'", file=sys.stderr)
        sys.exit(1)
if isinstance(cur, (dict, list)):
    print(yaml.safe_dump(cur, default_flow_style=False).rstrip())
else:
    print(cur)
'@
    $result = & python3 -c $pyScript $configFile $Path
    if ($LASTEXITCODE -ne 0) {
        Exit-Socool 1 ("config lookup failed for '{0}'" -f $Path)
    }
    return $result
}

function Get-SocoolVmHostnames {
    $configFile = Join-Path $script:SocoolRepoRoot 'config/lab.yml'
    $pyScript = @'
import sys, yaml
with open(sys.argv[1], 'r') as f:
    data = yaml.safe_load(f)
vms = sorted(data.get('vms', []), key=lambda v: v.get('boot_order', 0))
for vm in vms:
    print(vm['hostname'])
'@
    & python3 -c $pyScript $configFile
}

function Assert-SocoolHostnameToken {
    param([Parameter(Mandatory)][string]$Value)
    if ($Value -notmatch '^[a-z][a-z0-9-]{0,30}$') {
        Exit-Socool 1 ("invalid hostname token: '{0}' (must match ^[a-z][a-z0-9-]{{0,30}}$)" -f $Value)
    }
}
