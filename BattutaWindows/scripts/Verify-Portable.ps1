[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PublishDirectory,

    [int]$ExpectedSoundCount = 237,

    [int]$ExpectedBundledPackAssetCount = 28,

    [switch]$RequireTrustedSignature
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$publishRoot = (Resolve-Path -LiteralPath $PublishDirectory).Path
$executable = Join-Path $publishRoot 'Battuta.exe'
$soundRoot = Join-Path $publishRoot 'Assets\Sounds'
$expectedBundledPackId = '15d04652-5265-4ea7-a376-8a7e11ff6813'
$bundledPackRoot = Join-Path $publishRoot "BundledSoundPacks\$expectedBundledPackId.simuboardpack"
$bundledManifest = Join-Path $bundledPackRoot 'manifest.json'
$bundledNotice = Join-Path $bundledPackRoot 'licenses\BCP-Suit80-PERMISSION.txt'
$notices = Join-Path $publishRoot 'THIRD_PARTY_NOTICES.md'
$license = Join-Path $publishRoot 'LICENSE'

if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) {
    throw "Portable build is missing Battuta.exe: $executable"
}
if (-not (Test-Path -LiteralPath $soundRoot -PathType Container)) {
    throw "Portable build is missing Assets\Sounds: $soundRoot"
}
if (-not (Test-Path -LiteralPath $bundledManifest -PathType Leaf)) {
    throw "Portable build is missing bundled BCP manifest: $bundledManifest"
}
if (-not (Test-Path -LiteralPath $bundledNotice -PathType Leaf)) {
    throw "Portable build is missing bundled BCP permission notice: $bundledNotice"
}
if (-not (Test-Path -LiteralPath $notices -PathType Leaf)) {
    throw "Portable build is missing THIRD_PARTY_NOTICES.md"
}
if (-not (Test-Path -LiteralPath $license -PathType Leaf)) {
    throw "Portable build is missing LICENSE"
}

$soundFiles = @(Get-ChildItem -LiteralPath $soundRoot -Recurse -File)
if ($soundFiles.Count -ne $ExpectedSoundCount) {
    throw "Expected $ExpectedSoundCount sound assets, found $($soundFiles.Count)."
}

$emptySound = $soundFiles | Where-Object Length -LE 0 | Select-Object -First 1
if ($null -ne $emptySound) {
    throw "Portable build contains an empty sound asset: $($emptySound.FullName)"
}

$bundledAssets = @(Get-ChildItem -LiteralPath (Join-Path $bundledPackRoot 'assets') -Recurse -File -Filter '*.wav')
if ($bundledAssets.Count -ne $ExpectedBundledPackAssetCount) {
    throw "Expected $ExpectedBundledPackAssetCount bundled BCP assets, found $($bundledAssets.Count)."
}

$emptyBundledAsset = $bundledAssets | Where-Object Length -LE 0 | Select-Object -First 1
if ($null -ne $emptyBundledAsset) {
    throw "Portable build contains an empty bundled BCP asset: $($emptyBundledAsset.FullName)"
}

$manifest = Get-Content -LiteralPath $bundledManifest -Raw | ConvertFrom-Json
if ($manifest.id -ne $expectedBundledPackId) {
    throw "Bundled BCP manifest has an unexpected id: $($manifest.id)"
}
if ($manifest.name -ne 'BCP (Suit80)') {
    throw "Bundled BCP manifest has an unexpected name: $($manifest.name)"
}

$manifestAssets = @($manifest.assets.PSObject.Properties)
if ($manifestAssets.Count -ne $ExpectedBundledPackAssetCount) {
    throw "Bundled BCP manifest declares $($manifestAssets.Count) assets; expected $ExpectedBundledPackAssetCount."
}
foreach ($entry in $manifestAssets) {
    $asset = $entry.Value
    if ($entry.Name -ne $asset.id -or $asset.id -ne $asset.sha256) {
        throw "Bundled BCP asset id/hash mismatch for '$($entry.Name)'."
    }
    if ($asset.relativePath -notmatch '^assets/[0-9a-f]{64}\.wav$') {
        throw "Bundled BCP asset has an unsafe path: $($asset.relativePath)"
    }

    $relativePath = $asset.relativePath.Replace(
        '/',
        [System.IO.Path]::DirectorySeparatorChar)
    $assetPath = Join-Path $bundledPackRoot $relativePath
    if (-not (Test-Path -LiteralPath $assetPath -PathType Leaf)) {
        throw "Bundled BCP manifest references a missing asset: $($asset.relativePath)"
    }

    $assetInfo = Get-Item -LiteralPath $assetPath
    if ($assetInfo.Length -ne [long]$asset.byteCount) {
        throw "Bundled BCP asset has an unexpected byte count: $($asset.relativePath)"
    }
    $actualHash = (Get-FileHash -LiteralPath $assetPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualHash -ne $asset.sha256) {
        throw "Bundled BCP asset failed SHA-256 validation: $($asset.relativePath)"
    }
}

$permissionAttribution = @($manifest.attributions) | Where-Object {
    $_.licenseName -eq 'Used with permission' -and
    $_.notice -match 'Redistribution authorized'
} | Select-Object -First 1
if ($null -eq $permissionAttribution) {
    throw 'Bundled BCP manifest is missing the redistribution permission attribution.'
}
$permissionNotice = Get-Content -LiteralPath $bundledNotice -Raw
if (-not $permissionNotice.Contains('Redistribution of the derived BCP (Suit80) audio assets') -or
    -not $permissionNotice.Contains('authorized')) {
    throw 'Bundled BCP permission notice does not record authorized redistribution.'
}

$executableInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($executable)
$signatureCommand = Get-Command 'Get-AuthenticodeSignature' -ErrorAction SilentlyContinue
if ($null -eq $signatureCommand) {
    if ($RequireTrustedSignature) {
        throw 'Trusted-signature validation requires Windows PowerShell.'
    }
    $signatureStatus = 'NotChecked (unsupported on this host)'
    $signer = $null
}
else {
    $signature = Get-AuthenticodeSignature -LiteralPath $executable
    if ($RequireTrustedSignature -and
        ($signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid)) {
        throw "Battuta.exe must have a trusted signature: $($signature.Status) - $($signature.StatusMessage)"
    }
    $signatureStatus = $signature.Status
    $signer = if ($null -eq $signature.SignerCertificate) {
        $null
    }
    else {
        $signature.SignerCertificate.Subject
    }
}
[pscustomobject]@{
    Executable = $executable
    ProductVersion = $executableInfo.ProductVersion
    FileVersion = $executableInfo.FileVersion
    SignatureStatus = $signatureStatus
    Signer = $signer
    SoundCount = $soundFiles.Count
    BundledPackAssetCount = $bundledAssets.Count
    TotalBytes = (Get-ChildItem -LiteralPath $publishRoot -Recurse -File |
        Measure-Object -Property Length -Sum).Sum
}
