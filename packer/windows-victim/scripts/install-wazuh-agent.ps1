# packer/windows-victim/scripts/install-wazuh-agent.ps1
#
# Installs the Wazuh agent and enrols it with the Wazuh manager at the
# IP passed via env SOCOOL_WAZUH_MANAGER_IP (defaults to 10.42.20.10
# per config/lab.yml). Agent starts on boot.
#
# Reference: https://documentation.wazuh.com/current/installation-guide/wazuh-agent/wazuh-agent-package-windows.html

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$manager = if ($env:SOCOOL_WAZUH_MANAGER_IP) { $env:SOCOOL_WAZUH_MANAGER_IP } else { '10.42.20.10' }
Write-Host "Installing Wazuh agent (manager = $manager)..."

# Current Wazuh Windows agent URL (verified 2026-04-24). Pinned to
# the 4.14 series line to match the all-in-one server template.
$msiUrl = 'https://packages.wazuh.com/4.x/windows/wazuh-agent-4.14.4-1.msi'
$msiPath = Join-Path $env:TEMP 'wazuh-agent.msi'

Invoke-WebRequest -Uri $msiUrl -OutFile $msiPath -UseBasicParsing

# msiexec args: silent install, manager IP, agent name = host name.
$args = @(
    '/i', $msiPath,
    "/WAZUH_MANAGER=$manager",
    '/WAZUH_REGISTRATION_SERVER=' + $manager,
    '/WAZUH_AGENT_GROUP=windows-victims',
    '/quiet', '/norestart'
)
$p = Start-Process -FilePath 'msiexec.exe' -ArgumentList $args -Wait -PassThru
if ($p.ExitCode -ne 0) {
    throw "Wazuh agent MSI install failed: exit $($p.ExitCode)"
}

# Enable the service; it will fail to fully enrol until the Wazuh
# manager VM is online, which is fine — it retries on its own.
Set-Service -Name WazuhSvc -StartupType Automatic
Start-Service -Name WazuhSvc -ErrorAction SilentlyContinue

Remove-Item -LiteralPath $msiPath -Force -ErrorAction SilentlyContinue
Write-Host 'Wazuh agent installed and enabled.'
