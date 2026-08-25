[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?$')]
    [string]$Version,

    [ValidateRange(0, 65535)]
    [int]$BuildNumber = 0,

    [ValidateSet('win-x64', 'win-arm64')]
    [string]$Runtime = 'win-x64',

    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Release',

    [string]$PackageName = 'Wormforce.Battuta.Development',

    [string]$Publisher = 'CN=Wormforce Battuta Development',

    [string]$PublisherDisplayName = 'Wormforce',

    [ValidateSet('None', 'Development', 'CertificateStore')]
    [string]$SigningMode = 'Development',

    [switch]$StoreSubmission,

    [string]$SigningCertificateThumbprint,

    [Uri]$TimestampUri,

    [Uri]$AppInstallerBaseUri,

    [string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$scriptRoot = Split-Path -Parent $PSCommandPath
. (Join-Path $scriptRoot 'WindowsPackaging.Common.ps1')

$windowsRoot = (Resolve-Path -LiteralPath (Join-Path $scriptRoot '..')).Path
$project = Join-Path $windowsRoot 'src\Battuta.Windows\Battuta.Windows.csproj'
$packagingRoot = Join-Path $windowsRoot 'src\Battuta.Packaging'
$manifestTemplatePath = Join-Path $packagingRoot 'Package.appxmanifest.template'
$appInstallerTemplatePath = Join-Path $packagingRoot 'Battuta.appinstaller.template'
$assetRoot = Join-Path $packagingRoot 'Assets'
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $windowsRoot 'artifacts'
}
$outputRoot = [System.IO.Path]::GetFullPath($OutputDirectory)
$stagingRoot = Join-Path $outputRoot 'staging-msix'
$stage = Join-Path $stagingRoot ([Guid]::NewGuid().ToString('N'))
$directorySeparators = [char[]]@(
    [System.IO.Path]::DirectorySeparatorChar,
    [System.IO.Path]::AltDirectorySeparatorChar)
$safeStagingPrefix = [System.IO.Path]::GetFullPath($stagingRoot).TrimEnd($directorySeparators) +
    [System.IO.Path]::DirectorySeparatorChar

Assert-BattutaPackageIdentityName -Name $PackageName
if ([string]::IsNullOrWhiteSpace($Publisher) -or $Publisher -notmatch '=') {
    throw 'Publisher must be an X.500 distinguished name such as CN=Wormforce.'
}
if ([string]::IsNullOrWhiteSpace($PublisherDisplayName)) {
    throw 'PublisherDisplayName cannot be empty.'
}

$versionMatch = [regex]::Match($Version, '^(?<major>\d+)\.(?<minor>\d+)\.(?<patch>\d+)')
$versionParts = @(
    [int]$versionMatch.Groups['major'].Value,
    [int]$versionMatch.Groups['minor'].Value,
    [int]$versionMatch.Groups['patch'].Value
)
if ($versionParts | Where-Object { $_ -gt 65535 }) {
    throw 'MSIX version components must be between 0 and 65535.'
}
$packageVersion = "$($versionParts[0]).$($versionParts[1]).$($versionParts[2]).$BuildNumber"
$architecture = if ($Runtime -eq 'win-arm64') { 'arm64' } else { 'x64' }

if ($StoreSubmission) {
    if ($SigningMode -ne 'None') {
        throw 'StoreSubmission packages must use SigningMode None; Microsoft Store signs the certified package.'
    }
    if ($versionParts[0] -eq 0) {
        throw 'Microsoft Store package versions must have a non-zero first component.'
    }
    if ($BuildNumber -ne 0) {
        throw 'The fourth MSIX version component is reserved by Microsoft Store and must be 0.'
    }
    if ($null -ne $AppInstallerBaseUri) {
        throw 'StoreSubmission cannot generate an App Installer file; Microsoft Store manages distribution and updates.'
    }
}

$requiredAssets = @(
    'StoreLogo.png',
    'Square44x44Logo.png',
    'Square150x150Logo.png',
    'Wide310x150Logo.png'
)
foreach ($asset in $requiredAssets) {
    if (-not (Test-Path -LiteralPath (Join-Path $assetRoot $asset) -PathType Leaf)) {
        throw "MSIX asset '$asset' is missing. Run Generate-MsixAssets.ps1 first."
    }
}

$certificate = $null
if ($SigningMode -eq 'Development') {
    $certificate = Get-ChildItem -LiteralPath Cert:\CurrentUser\My |
        Where-Object {
            ($_.Subject -eq $Publisher) -and
            $_.HasPrivateKey -and
            ($_.NotAfter -gt [DateTime]::Now.AddDays(30))
        } |
        Sort-Object NotAfter -Descending |
        Select-Object -First 1
    if ($null -eq $certificate) {
        $certificate = New-SelfSignedCertificate `
            -Type Custom `
            -Subject $Publisher `
            -FriendlyName 'Battuta MSIX Development Signing' `
            -CertStoreLocation Cert:\CurrentUser\My `
            -KeyAlgorithm RSA `
            -KeyLength 3072 `
            -HashAlgorithm SHA256 `
            -KeyUsage DigitalSignature `
            -NotAfter ([DateTime]::Now.AddYears(5)) `
            -TextExtension @(
                '2.5.29.37={text}1.3.6.1.5.5.7.3.3',
                '2.5.29.19={text}ca=false')
    }
}
elseif ($SigningMode -eq 'CertificateStore') {
    if ([string]::IsNullOrWhiteSpace($SigningCertificateThumbprint)) {
        throw 'SigningCertificateThumbprint is required for CertificateStore signing.'
    }
    if ($null -eq $TimestampUri) {
        throw 'TimestampUri is required for production CertificateStore signing.'
    }
    $certificate = Get-BattutaSigningCertificate -Thumbprint $SigningCertificateThumbprint
    if ($certificate.Subject -ne $Publisher) {
        throw "Manifest Publisher '$Publisher' must exactly match signing certificate subject '$($certificate.Subject)'."
    }
}

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
        -p:FileVersion=$packageVersion `
        -p:PublishSingleFile=false `
        -p:PublishTrimmed=false `
        -p:DebugType=None `
        -p:DebugSymbols=false
    if ($LASTEXITCODE -ne 0) {
        throw "dotnet publish failed with exit code $LASTEXITCODE."
    }

    $stageAssets = Join-Path $stage 'Assets'
    New-Item -ItemType Directory -Force -Path $stageAssets | Out-Null
    foreach ($asset in $requiredAssets) {
        Copy-Item -LiteralPath (Join-Path $assetRoot $asset) -Destination (Join-Path $stageAssets $asset)
    }

    $tokens = [ordered]@{
        '{{PackageName}}' = ConvertTo-BattutaXmlAttribute $PackageName
        '{{Publisher}}' = ConvertTo-BattutaXmlAttribute $Publisher
        '{{PublisherDisplayName}}' = ConvertTo-BattutaXmlAttribute $PublisherDisplayName
        '{{PackageVersion}}' = $packageVersion
        '{{Architecture}}' = $architecture
    }
    $manifest = [System.IO.File]::ReadAllText($manifestTemplatePath, [System.Text.Encoding]::UTF8)
    foreach ($entry in $tokens.GetEnumerator()) {
        $manifest = $manifest.Replace($entry.Key, $entry.Value)
    }
    if ($manifest.IndexOf('{{', [System.StringComparison]::Ordinal) -ge 0) {
        throw 'The rendered AppxManifest.xml contains unresolved template tokens.'
    }
    [xml]$null = $manifest
    [System.IO.File]::WriteAllText(
        (Join-Path $stage 'AppxManifest.xml'),
        $manifest,
        [System.Text.UTF8Encoding]::new($false))

    $suffix = if ($StoreSubmission) {
        '-store'
    }
    elseif ($SigningMode -eq 'Development') {
        '-dev'
    }
    else {
        ''
    }
    $packageFileName = "Battuta-Windows-$Version-$Runtime$suffix.msix"
    $packagePath = Join-Path $outputRoot $packageFileName
    if (Test-Path -LiteralPath $packagePath) {
        Remove-Item -LiteralPath $packagePath -Force
    }
    $makeAppx = Get-BattutaWindowsSdkTool -Name 'makeappx.exe'
    $makeAppxOutput = @(& $makeAppx pack /d $stage /p $packagePath /o 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "MakeAppx failed with exit code $LASTEXITCODE.`n$($makeAppxOutput -join [Environment]::NewLine)"
    }

    $certificatePath = $null
    if ($null -ne $certificate) {
        Invoke-BattutaSignFile `
            -Path $packagePath `
            -Thumbprint $certificate.Thumbprint `
            -TimestampUri $TimestampUri
        if ($SigningMode -eq 'Development') {
            $certificatePath = Join-Path $outputRoot 'Battuta-Windows-Development.cer'
            Export-Certificate -Cert $certificate -FilePath $certificatePath -Force | Out-Null
        }
    }

    $appInstallerPath = $null
    if ($null -ne $AppInstallerBaseUri) {
        if ($AppInstallerBaseUri.Scheme -ne 'https') {
            throw 'AppInstallerBaseUri must use HTTPS for public distribution.'
        }
        $baseUri = $AppInstallerBaseUri.AbsoluteUri.TrimEnd('/')
        $appInstallerUri = "$baseUri/Battuta.appinstaller"
        $msixUri = "$baseUri/$packageFileName"
        $appInstaller = [System.IO.File]::ReadAllText(
            $appInstallerTemplatePath,
            [System.Text.Encoding]::UTF8)
        $appInstallerTokens = [ordered]@{
            '{{PackageName}}' = ConvertTo-BattutaXmlAttribute $PackageName
            '{{Publisher}}' = ConvertTo-BattutaXmlAttribute $Publisher
            '{{PackageVersion}}' = $packageVersion
            '{{Architecture}}' = $architecture
            '{{AppInstallerUri}}' = ConvertTo-BattutaXmlAttribute $appInstallerUri
            '{{MsixUri}}' = ConvertTo-BattutaXmlAttribute $msixUri
        }
        foreach ($entry in $appInstallerTokens.GetEnumerator()) {
            $appInstaller = $appInstaller.Replace($entry.Key, $entry.Value)
        }
        if ($appInstaller.IndexOf('{{', [System.StringComparison]::Ordinal) -ge 0) {
            throw 'The rendered Battuta.appinstaller contains unresolved template tokens.'
        }
        [xml]$null = $appInstaller
        $appInstallerPath = Join-Path $outputRoot 'Battuta.appinstaller'
        [System.IO.File]::WriteAllText(
            $appInstallerPath,
            $appInstaller,
            [System.Text.UTF8Encoding]::new($false))
    }

    $allowUnsigned = $SigningMode -eq 'None'
    $allowUntrusted = $SigningMode -eq 'Development'
    $verification = & (Join-Path $scriptRoot 'Verify-Msix.ps1') `
        -PackagePath $packagePath `
        -AllowUnsigned:$allowUnsigned `
        -AllowUntrustedSignature:$allowUntrusted

    $hash = Get-FileHash -LiteralPath $packagePath -Algorithm SHA256
    $hashPath = "$packagePath.sha256"
    [System.IO.File]::WriteAllText(
        $hashPath,
        "$($hash.Hash.ToLowerInvariant())  $packageFileName",
        [System.Text.Encoding]::ASCII)

    [pscustomobject]@{
        Package = $packagePath
        PackageVersion = $packageVersion
        Sha256 = $hash.Hash.ToLowerInvariant()
        HashFile = $hashPath
        Certificate = $certificatePath
        AppInstaller = $appInstallerPath
        SignatureStatus = $verification.SignatureStatus
        PackageName = $PackageName
        Publisher = $Publisher
        Distribution = if ($StoreSubmission) { 'MicrosoftStore' } else { 'Direct' }
    }
}
finally {
    $resolvedStage = [System.IO.Path]::GetFullPath($stage)
    if ($resolvedStage.StartsWith($safeStagingPrefix, [System.StringComparison]::OrdinalIgnoreCase) -and
        (Test-Path -LiteralPath $resolvedStage)) {
        Remove-Item -LiteralPath $resolvedStage -Recurse -Force
    }
}
