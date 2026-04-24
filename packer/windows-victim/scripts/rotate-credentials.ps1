# packer/windows-victim/scripts/rotate-credentials.ps1
#
# Rotates the BUILD-ONLY 'vagrant' password to a CSPRNG-generated value.
# Uses System.Security.Cryptography.RandomNumberGenerator (NOT
# Get-Random, which is a PRNG — banned by .skills/devsecops/).
# Writes C:\Windows\Temp\socool-windows-victim-credentials.json which
# Packer's file provisioner pulls back to the host.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function New-SocoolPassword {
    param([int]$Length = 24)
    $bytes = New-Object byte[] $Length
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    return ([Convert]::ToBase64String($bytes) -replace '[+/=]','').Substring(0, $Length)
}

$vagrantPass = New-SocoolPassword -Length 24

Write-Host 'Rotating vagrant password...'
$sec = ConvertTo-SecureString -String $vagrantPass -AsPlainText -Force
Set-LocalUser -Name 'vagrant' -Password $sec

# Disable the FirstLogonCommands autologon so on subsequent boots the
# credentials we just rotated are authoritative.
reg add 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' /v AutoAdminLogon /t REG_SZ /d 0 /f | Out-Null
reg delete 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' /v DefaultPassword /f 2>$null

# Build the manifest. Restrictive ACL so only Administrators and SYSTEM
# can read it.
$manifestPath = 'C:\Windows\Temp\socool-windows-victim-credentials.json'
$ts = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
$manifest = @{
    vm = 'windows-victim'
    generated_utc = $ts
    accounts = @(
        @{ username = 'vagrant'; password = $vagrantPass; scope = 'RDP + WinRM + local' }
    )
    notes = 'Rotated during Packer build; BUILD-ONLY password is gone. Vagrant will override WinRM/SSH keys on first `vagrant up`.'
} | ConvertTo-Json -Depth 5

Set-Content -Path $manifestPath -Value $manifest -Encoding UTF8 -Force
$acl = Get-Acl $manifestPath
$acl.SetAccessRuleProtection($true, $false)
$acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
    'BUILTIN\Administrators', 'FullControl', 'Allow')))
$acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
    'NT AUTHORITY\SYSTEM', 'FullControl', 'Allow')))
Set-Acl -Path $manifestPath -AclObject $acl

Write-Host 'Credentials rotated; manifest written to C:\Windows\Temp.'
