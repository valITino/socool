# scripts/preflight/run-all.ps1 — runs every check under checks/.
#
# Each check is its own script in scripts/preflight/checks/<name>.ps1,
# exiting 10..19 on failure with a one-line remediation sentence.
#
# Exit codes mirror scripts/preflight/run-all.sh.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

$ScriptDir = $PSScriptRoot
. (Join-Path $ScriptDir '..' 'lib' 'common.ps1')

$checksDir = Join-Path $ScriptDir 'checks'
if (-not (Test-Path -LiteralPath $checksDir)) {
    Exit-Socool 10 ("preflight checks directory missing: {0}" -f $checksDir)
}

$checks = @(Get-ChildItem -LiteralPath $checksDir -Filter '*.ps1' -File -ErrorAction SilentlyContinue)

if ($checks.Count -eq 0) {
    Write-SocoolWarn 'no preflight checks installed (scripts/preflight/checks/ is empty; Step 4 pending)'
    Write-SocoolWarn 'proceeding without preflight. Set SOCOOL_STRICT_PREFLIGHT=1 to fail-fast instead.'
    if ($env:SOCOOL_STRICT_PREFLIGHT -eq '1') {
        Exit-Socool 10 'no preflight checks installed and SOCOOL_STRICT_PREFLIGHT=1'
    }
    exit 0
}

Write-SocoolInfo ("running {0} preflight check(s)" -f $checks.Count)
$failed = @()
foreach ($check in $checks) {
    $name = [IO.Path]::GetFileNameWithoutExtension($check.Name)
    Write-SocoolDebug ("preflight: {0}" -f $name)
    & pwsh -NoProfile -File $check.FullName
    if ($LASTEXITCODE -ne 0) {
        $failed += ('{0} ({1})' -f $name, $LASTEXITCODE)
    }
}

if ($failed.Count -gt 0) {
    foreach ($f in $failed) { Write-SocoolError ("preflight failed: {0}" -f $f) }
    Exit-Socool 10 ("{0} preflight check(s) failed; see messages above and docs/troubleshooting.md" -f $failed.Count)
}

Write-SocoolInfo 'all preflight checks passed'
