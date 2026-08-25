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
$bundledPackRoot = Join-Path $publishRoot 'BundledSoundPacks\15d04652-5265-4ea7-a376-8a7e11ff6813.simuboardpack'
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

$executableInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($executable)
$signature = Get-AuthenticodeSignature -LiteralPath $executable
if ($RequireTrustedSignature -and
    ($signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid)) {
    throw "Battuta.exe must have a trusted signature: $($signature.Status) - $($signature.StatusMessage)"
}
[pscustomobject]@{
    Executable = $executable
    ProductVersion = $executableInfo.ProductVersion
    FileVersion = $executableInfo.FileVersion
    SignatureStatus = $signature.Status
    Signer = if ($null -eq $signature.SignerCertificate) { $null } else { $signature.SignerCertificate.Subject }
    SoundCount = $soundFiles.Count
    BundledPackAssetCount = $bundledAssets.Count
    TotalBytes = (Get-ChildItem -LiteralPath $publishRoot -Recurse -File |
        Measure-Object -Property Length -Sum).Sum
}
