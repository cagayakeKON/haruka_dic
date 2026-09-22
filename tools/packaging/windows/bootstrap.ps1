param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repository = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$lock = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'toolchain.json') -Raw | ConvertFrom-Json
$sdkVersion = (& dotnet --version).Trim()
if ($LASTEXITCODE -ne 0 -or $sdkVersion -ne $lock.dotnet_sdk) {
    throw "Expected .NET SDK $($lock.dotnet_sdk); found $sdkVersion"
}
$net6 = @(& dotnet --list-runtimes | Where-Object { $_ -match '^Microsoft.NETCore.App 6\.' } |
    ForEach-Object { [version](($_ -split ' ')[1]) } | Sort-Object -Descending)
if ($LASTEXITCODE -ne 0 -or $net6.Count -eq 0 -or $net6[0].ToString() -ne $lock.dotnet_runtime) {
    throw "Expected existing .NET 6 runtime patch $($lock.dotnet_runtime); no runtime is installed by this script."
}
$toolRoot = Join-Path $repository ('.tools\wix-' + $lock.wix.version)
$feed = Join-Path $toolRoot 'feed'
$toolPath = Join-Path $toolRoot 'tool'
$package = Join-Path $feed ('wix.' + $lock.wix.version + '.nupkg')
New-Item -ItemType Directory -Force -Path $feed | Out-Null
if (-not (Test-Path -LiteralPath $package)) {
    Invoke-WebRequest -Uri $lock.wix.package_url -OutFile $package
}
if ((Get-FileHash -LiteralPath $package -Algorithm SHA256).Hash.ToLowerInvariant() -ne $lock.wix.package_sha256) {
    throw 'WiX NuGet package digest differs from the lock; no tool has been executed.'
}
$env:DOTNET_SKIP_FIRST_TIME_EXPERIENCE = '1'
$env:DOTNET_CLI_TELEMETRY_OPTOUT = '1'
$env:DOTNET_GENERATE_ASPNET_CERTIFICATE = 'false'
$env:DOTNET_CLI_HOME = Join-Path $repository '.tools\dotnet-home'
& dotnet nuget verify $package --all --certificate-fingerprint $lock.wix.author_certificate_sha256
if ($LASTEXITCODE -ne 0) { throw 'WiX package signature validation failed.' }
$escapedFeed = [System.Security.SecurityElement]::Escape($feed)
$config = Join-Path $toolRoot 'NuGet.Config'
@"
<configuration>
  <packageSources><clear /><add key="locked-local-feed" value="$escapedFeed" /></packageSources>
  <config><add key="signatureValidationMode" value="require" /></config>
</configuration>
"@ | Set-Content -LiteralPath $config -Encoding utf8
$wix = Join-Path $toolPath 'wix.exe'
if (-not (Test-Path -LiteralPath $wix)) {
    # .NET's tool-path install only writes tool files here, with no Windows installer registration.
    & dotnet tool install wix --version $lock.wix.version --tool-path $toolPath --configfile $config
    if ($LASTEXITCODE -ne 0) { throw 'Workspace-local WiX tool restore failed.' }
}
$actual = (& $wix --version).Trim()
if ($LASTEXITCODE -ne 0 -or -not $actual.StartsWith($lock.wix.version + '+')) {
    throw "Unexpected WiX version: $actual"
}
Write-Output "Ready: workspace-local WiX $actual"
