# scripts/provision/run-pipeline.ps1 — per-VM Packer build + vagrant up.
#
# Mirrors scripts/provision/run-pipeline.sh. Packer templates and
# vagrant/Vagrantfile land in Steps 5 and 6; absence is reported
# cleanly.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

. (Join-Path $PSScriptRoot '..' 'lib' 'common.ps1')

function script:Get-VagrantProvider {
    param([Parameter(Mandatory)][ValidateSet('virtualbox','libvirt')][string]$Hypervisor)
    return $Hypervisor
}

function script:Get-LabVmIndex {
    param([Parameter(Mandatory)][string]$Hostname)
    $configFile = Join-Path $script:SocoolRepoRoot 'config/lab.yml'
    $pyScript = @'
import sys, yaml
with open(sys.argv[1], 'r') as f:
    data = yaml.safe_load(f)
for i, vm in enumerate(data.get('vms', [])):
    if vm['hostname'] == sys.argv[2]:
        print(i); sys.exit(0)
sys.exit(1)
'@
    $idx = & python3 -c $pyScript $configFile $Hostname
    if ($LASTEXITCODE -ne 0) { Exit-Socool 1 ("vm not found in config: {0}" -f $Hostname) }
    return [int]$idx
}

function Invoke-SocoolProvisionPipeline {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('virtualbox','libvirt')][string]$Hypervisor,
        [Parameter(Mandatory)][ValidateSet('nessus','openvas','none')][string]$Scanner,
        [Parameter(Mandatory)][ValidateSet('msdev','iso')][string]$WindowsSource
    )

    Write-SocoolInfo ("provision pipeline: hv={0} scanner={1} windows={2}" -f $Hypervisor, $Scanner, $WindowsSource)

    $repoRoot = $script:SocoolRepoRoot
    $built = 0; $skipped = 0; $missing = 0

    $outputDir = $env:SOCOOL_BOX_OUTPUT_DIR
    if ([string]::IsNullOrEmpty($outputDir)) { $outputDir = Join-Path $repoRoot '.socool-cache/boxes' }
    New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

    foreach ($vm in (Get-SocoolVmHostnames)) {
        if ([string]::IsNullOrWhiteSpace($vm)) { continue }
        Assert-SocoolHostnameToken -Value $vm

        if ($vm -eq 'nessus'  -and $Scanner -ne 'nessus')  { Write-SocoolInfo ("skip vm={0} (scanner={1})" -f $vm, $Scanner); $skipped++; continue }
        if ($vm -eq 'openvas' -and $Scanner -ne 'openvas') { Write-SocoolInfo ("skip vm={0} (scanner={1})" -f $vm, $Scanner); $skipped++; continue }

        $template = Join-Path $repoRoot (Join-Path 'packer' (Join-Path $vm 'template.pkr.hcl'))
        $idx = Get-LabVmIndex -Hostname $vm
        $boxName = Get-SocoolLabConfig -Path ("vms.{0}.box" -f $idx)
        $boxFile = Join-Path $outputDir ("{0}.box" -f $boxName)

        if (-not (Test-Path -LiteralPath $template)) {
            Write-SocoolWarn ("packer template missing: {0} (Step 5 pending for vm={1})" -f $template, $vm)
            $missing++
            continue
        }
        if (Test-Path -LiteralPath $boxFile) {
            Write-SocoolInfo ("box already built, skipping: {0}" -f $boxFile)
            $skipped++
            continue
        }

        Write-SocoolBanner ("Packer build: {0}" -f $vm)
        Push-Location -LiteralPath (Join-Path $repoRoot "packer/$vm")
        try {
            & packer init -- $template
            if ($LASTEXITCODE -ne 0) { Exit-Socool 40 ("packer init failed for {0}" -f $vm) }
            & packer build `
                ("-var=hypervisor={0}" -f $Hypervisor) `
                ("-var=windows_source={0}" -f $WindowsSource) `
                ("-var=output_dir={0}" -f $outputDir) `
                -- $template
            if ($LASTEXITCODE -ne 0) { Exit-Socool 40 ("packer build failed for {0}" -f $vm) }
            $built++
        } finally {
            Pop-Location
        }
    }

    Write-SocoolInfo ("pipeline summary: built={0} skipped={1} template-missing={2}" -f $built, $skipped, $missing)

    $vagrantfile = Join-Path $repoRoot 'vagrant/Vagrantfile'
    if (-not (Test-Path -LiteralPath $vagrantfile)) {
        Write-SocoolWarn ("Vagrantfile missing: {0} (Step 6 pending). The lab cannot be started yet." -f $vagrantfile)
        return
    }
    Write-SocoolBanner 'vagrant up'
    Push-Location -LiteralPath (Join-Path $repoRoot 'vagrant')
    try {
        & vagrant up --provider (Get-VagrantProvider -Hypervisor $Hypervisor)
        if ($LASTEXITCODE -ne 0) { Exit-Socool 50 'vagrant up failed' }
    } finally {
        Pop-Location
    }
}
