# packer/windows-victim/http/setup-winrm.ps1
#
# FirstLogonCommands runs this right after Windows setup completes and
# logs in as 'vagrant'. It enables WinRM over HTTP (5985) in "basic-
# auth-allowed, unencrypted-allowed" mode so Packer's WinRM
# communicator can connect. This is acceptable for a throwaway Packer
# build environment; Vagrant will reconfigure WinRM with proper TLS
# when it boots the finished box.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host 'Enabling WinRM service for Packer...'

# Basic setup + open the firewall.
& winrm quickconfig -quiet -force

# Allow unencrypted basic auth over HTTP. ONLY safe because:
#   - this is a throwaway Packer build host,
#   - the only reachable network is the VirtualBox NAT back to Packer,
#   - rotate-credentials.ps1 and cleanup.ps1 invalidate these
#     credentials before the box is packaged.
& winrm set winrm/config/service                  '@{AllowUnencrypted="true"}'
& winrm set winrm/config/service/auth             '@{Basic="true"}'
& winrm set winrm/config/client/auth              '@{Basic="true"}'
& winrm set winrm/config/client                   '@{AllowUnencrypted="true"}'
& winrm set winrm/config/winrs                    '@{MaxMemoryPerShellMB="1024"}'

# Firewall rule for WinRM-HTTP.
& netsh advfirewall firewall set rule group="remote administration" new enable=yes
& netsh advfirewall firewall add rule name="WinRM-HTTP" dir=in localport=5985 protocol=TCP action=allow

Restart-Service winrm
Write-Host 'WinRM is ready for Packer.'
