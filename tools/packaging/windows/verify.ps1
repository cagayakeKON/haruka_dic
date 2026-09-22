param([Parameter(Mandatory = $true)][string]$Manifest)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repository = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$artifactRoot = [IO.Path]::GetFullPath((Join-Path $repository 'artifacts\windows-installer'))
$manifestPath = (Resolve-Path -LiteralPath $Manifest).Path
if (-not $manifestPath.StartsWith($artifactRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Proof manifest must be inside artifacts/windows-installer.'
}
$output = Split-Path -Parent $manifestPath
$reportPath = Join-Path $output 'proof.json'
if (Test-Path -LiteralPath $reportPath) { throw 'A proof run already owns this output directory.' }
$manifestData = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$targetPath = Join-Path $repository 'frontend\config\build_targets.json'
$targets = Get-Content -LiteralPath $targetPath -Raw | ConvertFrom-Json
if ($manifestData.schema_version -ne 1 -or
    $manifestData.compiler -ne '5.0.2+aa65968c' -or
    $manifestData.build_targets_sha256 -ne (Get-FileHash -LiteralPath $targetPath -Algorithm SHA256).Hash.ToLowerInvariant()) {
    throw 'Manifest schema, compiler or build target digest differs.'
}
$packages = @($manifestData.packages)
if ($packages.Count -ne 3 -or
    (($packages | ForEach-Object { $_.environment + ':' + $_.version }) -join ',') -ne 'dev:0.1.0,production:0.1.0,dev:0.1.1') {
    throw 'Only the fixed three-package identity experiment is supported.'
}
$programs = [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'Programs'))
if ((Test-Path -LiteralPath $programs) -and
    ((Get-Item -LiteralPath $programs).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
    throw 'The per-user Programs directory must not be a reparse point.'
}
$installer = New-Object -ComObject WindowsInstaller.Installer
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class HarukaInstallerProofMsi {
    [DllImport("msi.dll", CharSet = CharSet.Unicode, EntryPoint = "MsiQueryProductStateW")]
    public static extern int State(string product);
    [DllImport("msi.dll", CharSet = CharSet.Unicode, EntryPoint = "MsiEnumRelatedProductsW")]
    private static extern uint Related(string upgrade, uint reserved, uint index, StringBuilder product);
    public static bool HasRelated(string upgrade) {
        var product = new StringBuilder(39);
        uint result = Related(upgrade, 0, 0, product);
        if (result == 259) return false;
        if (result != 0) throw new InvalidOperationException("MSI identity preflight failed: " + result);
        return true;
    }
}
'@
$records = @()
foreach ($package in $packages) {
    $environment = [string]$package.environment
    $source = $targets.platforms.windows.$environment
    $expectedId = if ($environment -eq 'dev') { 'haruka.dictionary.dev' } else { 'haruka.dictionary' }
    $expectedDirectory = if ($environment -eq 'dev') { 'Haruka Dev' } else { 'Haruka' }
    if ($package.application_id -ne $expectedId -or $package.installer_id -ne $expectedId -or
        $package.credential_service -ne $expectedId -or $package.product_directory -ne $expectedDirectory -or
        $source.application_id -ne $expectedId -or $source.installer_id -ne $expectedId -or
        $source.credential_service -ne $expectedId -or $source.product_directory -ne $expectedDirectory -or
        $package.payload_kind -ne 'no-network-identity-probe') { throw 'Unexpected environment identity.' }
    $packagePath = [IO.Path]::GetFullPath((Join-Path $output $package.package))
    if (-not $packagePath.StartsWith($output + '\', [StringComparison]::OrdinalIgnoreCase) -or
        (Get-Item -LiteralPath $packagePath).Attributes -band [IO.FileAttributes]::ReparsePoint -or
        (Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $package.package_sha256) {
        throw 'Package path or digest differs.'
    }
    $productCode = '{' + ([guid]$package.product_code).ToString().ToUpperInvariant() + '}'
    $upgradeCode = '{' + ([guid]$package.upgrade_code).ToString().ToUpperInvariant() + '}'
    $db = $installer.OpenDatabase($packagePath, 0)
    $view = $db.OpenView('SELECT `Property`, `Value` FROM `Property`')
    $view.Execute()
    $properties = @{}
    while ($row = $view.Fetch()) { $properties[$row.StringData(1)] = $row.StringData(2) }
    $view.Close()
    if ($properties.ProductCode -ne $productCode -or $properties.UpgradeCode -ne $upgradeCode -or
        $properties.ProductVersion -ne $package.version -or $properties.ContainsKey('ALLUSERS') -or
        $properties.MSIRESTARTMANAGERCONTROL -ne 'Disable') { throw 'MSI identity or user scope differs.' }
    $directory = Join-Path $programs $expectedDirectory
    $registry = 'HKCU:\Software\Haruka\Installations\' + $expectedId
    if ((Test-Path -LiteralPath $directory) -or (Test-Path -LiteralPath $registry) -or
        [HarukaInstallerProofMsi]::HasRelated($upgradeCode) -or
        [HarukaInstallerProofMsi]::State($productCode) -ne -1) {
        throw 'An existing installation or directory occupies an identity; no changes made.'
    }
    $records += [pscustomobject]@{
        Package = $package; Path = $packagePath; ProductCode = $productCode
        Directory = $directory; Registry = $registry; Payload = (Split-Path -Parent $packagePath)
    }
}
$runId = [guid]::NewGuid().ToString('N')
$events = [Collections.Generic.List[object]]::new()
$attempted = [Collections.Generic.List[object]]::new()
$credentialRecords = [Collections.Generic.List[object]]::new()
$failure = $null
$cleanupFailures = [Collections.Generic.List[string]]::new()
$dev = $records[0]; $production = $records[1]; $upgrade = $records[2]

function Assert-Installed($Record) {
    if ([HarukaInstallerProofMsi]::State($Record.ProductCode) -ne 5) { throw 'Expected MSI product is not installed.' }
    foreach ($filename in @('haruka-installation.json', 'identity-probe.ps1')) {
        $installed = Join-Path $Record.Directory $filename
        $original = Join-Path $Record.Payload $filename
        if ((Get-FileHash -LiteralPath $installed -Algorithm SHA256).Hash -ne
            (Get-FileHash -LiteralPath $original -Algorithm SHA256).Hash) { throw 'Installed payload differs.' }
    }
    if ((Get-ItemProperty -LiteralPath $Record.Registry).PrototypeVersion -ne $Record.Package.version) {
        throw 'Per-user registry version differs.'
    }
}

function Invoke-Msi($Record, [ValidateSet('install', 'uninstall')][string]$Operation) {
    $label = $Operation + '-' + $Record.Package.environment + '-' + $Record.Package.version
    $log = Join-Path $output ($label + '.log')
    if ($Operation -eq 'install') {
        $attempted.Add($Record)
        $arguments = '/i "' + $Record.Path + '" /qn /norestart REBOOT=ReallySuppress /L*v "' + $log + '"'
    } else {
        Assert-Installed $Record
        $arguments = '/x ' + $Record.ProductCode + ' /qn /norestart REBOOT=ReallySuppress /L*v "' + $log + '"'
    }
    # Scope comes from the reviewed perUser MSI; no elevation, trust changes or process termination.
    $process = Start-Process -FilePath (Join-Path $env:WINDIR 'System32\msiexec.exe') -ArgumentList $arguments -WindowStyle Hidden -Wait -PassThru
    $events.Add(@{ action = $label; exit_code = $process.ExitCode; log = [IO.Path]::GetFileName($log) })
    if ($process.ExitCode -ne 0) { throw "MSI $label failed with $($process.ExitCode)." }
}

function Invoke-Probe($Record, [ValidateSet('write', 'read', 'delete')][string]$Action, [bool]$Installed = $true) {
    $directory = if ($Installed) { $Record.Directory } else { $Record.Payload }
    $script = Join-Path $directory 'identity-probe.ps1'
    $probeHost = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $result = & $probeHost -NoProfile -NonInteractive -File $script -Action $Action -RunId $runId
    if ($LASTEXITCODE -ne 0) { throw "Credential $Action proof failed." }
    $value = $result | ConvertFrom-Json
    if (-not $value.passed -or $value.environment -ne $Record.Package.environment -or
        $value.credential_service -ne $Record.Package.credential_service) { throw 'Credential proof result differs.' }
    $events.Add($value)
}

try {
    Invoke-Msi $dev install
    Assert-Installed $dev
    Invoke-Msi $production install
    Assert-Installed $production
    foreach ($record in @($dev, $production)) {
        $credentialRecords.Add($record)
        Invoke-Probe $record write
        Invoke-Probe $record read
    }
    $events.Add(@{ assertion = 'dev and production installed simultaneously with separate credential targets'; passed = $true })
    Invoke-Msi $upgrade install
    Assert-Installed $upgrade
    if ([HarukaInstallerProofMsi]::State($dev.ProductCode) -ne -1) { throw 'Old dev ProductCode remains installed.' }
    Assert-Installed $production
    Invoke-Probe $upgrade read
    Invoke-Probe $production read
    $events.Add(@{ assertion = 'dev upgrade removed old dev registration and preserved production files and credentials'; passed = $true })
    Invoke-Msi $upgrade uninstall
    if ((Test-Path -LiteralPath $upgrade.Directory) -or (Test-Path -LiteralPath $upgrade.Registry)) {
        throw 'Development uninstall left the owned payload or registry key.'
    }
    Assert-Installed $production
    Invoke-Probe $production read
    $events.Add(@{ assertion = 'dev uninstall preserved production registration, payload and credential'; passed = $true })
} catch {
    $failure = $_.Exception.Message
} finally {
    foreach ($record in $credentialRecords) {
        try { Invoke-Probe $record delete $false } catch { $cleanupFailures.Add($_.Exception.Message) }
    }
    # Only products attempted by this exact run, absent in preflight and still matching our payload.
    foreach ($record in $attempted) {
        if ([HarukaInstallerProofMsi]::State($record.ProductCode) -eq 5) {
            try { Invoke-Msi $record uninstall } catch { $cleanupFailures.Add($_.Exception.Message) }
        }
    }
    foreach ($record in @($dev, $production)) {
        if ((Test-Path -LiteralPath $record.Directory) -or (Test-Path -LiteralPath $record.Registry) -or
            [HarukaInstallerProofMsi]::HasRelated('{' + $record.Package.upgrade_code + '}')) {
            $cleanupFailures.Add('Owned installation remains for ' + $record.Package.environment)
        }
    }
    @{
        schema_version = 1; run_id = $runId; completed_at_utc = [DateTime]::UtcNow.ToString('o')
        manifest_sha256 = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
        passed = ($null -eq $failure -and $cleanupFailures.Count -eq 0)
        failure = $failure; cleanup_failures = $cleanupFailures.ToArray(); events = $events.ToArray()
        scope = 'per-user unsigned MSI; synthetic offline payload and run-owned credentials only'
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding utf8
}
if ($failure -or $cleanupFailures.Count) { throw "Identity proof failed; see $reportPath" }
Write-Output "Identity proof passed with complete cleanup: $reportPath"
