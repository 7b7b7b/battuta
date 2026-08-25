[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?$')]
    [string]$Version,

    [ValidateSet('win-x64', 'win-arm64')]
    [string]$Runtime = 'win-x64',

    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Release',

    [string]$OutputDirectory,

    [string]$SigningCertificateThumbprint,

    [Uri]$TimestampUri
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$scriptRoot = Split-Path -Parent $PSCommandPath
. (Join-Path $scriptRoot 'WindowsPackaging.Common.ps1')
$windowsRoot = (Resolve-Path -LiteralPath (Join-Path $scriptRoot '..')).Path
$repositoryRoot = (Resolve-Path -LiteralPath (Join-Path $windowsRoot '..')).Path
$project = Join-Path $windowsRoot 'src\Battuta.Windows\Battuta.Windows.csproj'
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $windowsRoot 'artifacts'
}
$outputRoot = [System.IO.Path]::GetFullPath($OutputDirectory)
$stagingRoot = Join-Path $outputRoot 'staging'
$stage = Join-Path $stagingRoot ([Guid]::NewGuid().ToString('N'))
$safeStagingPrefix = [System.IO.Path]::GetFullPath($stagingRoot).TrimEnd('\') + '\'

New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null
New-Item -ItemType Directory -Force -Path $stagingRoot | Out-Null
New-Item -ItemType Directory -Path $stage | Out-Null

try {
    & dotnet publish $project `
        --configuration $Configuration `
        --runtime $Runtime `
        --self-contained true `
        --output $stage `
        -p:Version=$Version `
        -p:PublishSingleFile=false `
        -p:PublishTrimmed=false
    if ($LASTEXITCODE -ne 0) {
        throw "dotnet publish failed with exit code $LASTEXITCODE"
    }

    Copy-Item -LiteralPath (Join-Path $repositoryRoot 'THIRD_PARTY_NOTICES.md') `
        -Destination (Join-Path $stage 'THIRD_PARTY_NOTICES.md')
    Copy-Item -LiteralPath (Join-Path $repositoryRoot 'LICENSE') `
        -Destination (Join-Path $stage 'LICENSE')

    $requireTrustedSignature = $false
    if (-not [string]::IsNullOrWhiteSpace($SigningCertificateThumbprint)) {
        if ($null -eq $TimestampUri) {
            throw 'TimestampUri is required when signing the portable executable.'
        }
        $certificate = Get-BattutaSigningCertificate -Thumbprint $SigningCertificateThumbprint
        Invoke-BattutaSignFile `
            -Path (Join-Path $stage 'Battuta.exe') `
            -Thumbprint $certificate.Thumbprint `
            -TimestampUri $TimestampUri
        $requireTrustedSignature = $true
    }

    & (Join-Path $scriptRoot 'Verify-Portable.ps1') `
        -PublishDirectory $stage `
        -RequireTrustedSignature:$requireTrustedSignature

    $archiveName = "Battuta-Windows-$Version-$Runtime.zip"
    $archivePath = Join-Path $outputRoot $archiveName
    if (Test-Path -LiteralPath $archivePath) {
        Remove-Item -LiteralPath $archivePath -Force
    }
    Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $archivePath -CompressionLevel Optimal

    $hash = Get-FileHash -LiteralPath $archivePath -Algorithm SHA256
    $hashPath = "$archivePath.sha256"
    Set-Content -LiteralPath $hashPath -Encoding ascii -NoNewline `
        -Value "$($hash.Hash.ToLowerInvariant())  $archiveName"

    [pscustomobject]@{
        Archive = $archivePath
        Sha256 = $hash.Hash.ToLowerInvariant()
        HashFile = $hashPath
    }
}
finally {
    $resolvedStage = [System.IO.Path]::GetFullPath($stage)
    if ($resolvedStage.StartsWith($safeStagingPrefix, [System.StringComparison]::OrdinalIgnoreCase) `
        -and (Test-Path -LiteralPath $resolvedStage)) {
        Remove-Item -LiteralPath $resolvedStage -Recurse -Force
    }
}
