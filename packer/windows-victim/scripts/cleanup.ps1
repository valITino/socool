# packer/windows-victim/scripts/cleanup.ps1
#
# Final pre-packaging pass: disable WinRM unencrypted-basic (we turned
# it on only for Packer's own session), trim Windows Update cache,
# zero free disk space.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

Write-Host 'Tightening WinRM (disabling unencrypted basic auth used during build)...'
try {
    & winrm set winrm/config/service  '@{AllowUnencrypted="false"}'
    & winrm set winrm/config/service/auth '@{Basic="false"}'
    & winrm set winrm/config/client   '@{AllowUnencrypted="false"}'
    & winrm set winrm/config/client/auth '@{Basic="false"}'
} catch {
    Write-Warning "WinRM tightening failed; Vagrant will re-assert its own config on first 'vagrant up'."
}

Write-Host 'Clearing Windows Update cache...'
Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force -ErrorAction SilentlyContinue 'C:\Windows\SoftwareDistribution\Download\*'
Start-Service -Name wuauserv -ErrorAction SilentlyContinue

Write-Host 'Clearing temp + prefetch...'
Remove-Item -Recurse -Force -ErrorAction SilentlyContinue 'C:\Windows\Temp\*'
Remove-Item -Recurse -Force -ErrorAction SilentlyContinue 'C:\Windows\Prefetch\*'
Remove-Item -Recurse -Force -ErrorAction SilentlyContinue 'C:\Users\*\AppData\Local\Temp\*'

Write-Host 'Zeroing free space for better .box compression...'
# SDelete would be cleaner but requires a separate download; use cipher.
& cipher.exe /w:C:\ | Out-Null

Write-Host 'Cleanup complete.'
