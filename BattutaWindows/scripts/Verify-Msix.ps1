[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PackagePath,

    [int]$ExpectedSoundCount = 237,

    [switch]$AllowUnsigned,

    [switch]$AllowUntrustedSignature
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$scriptRoot = Split-Path -Parent $PSCommandPath
. (Join-Path $scriptRoot 'WindowsPackaging.Common.ps1')

$resolvedPackage = (Resolve-Path -LiteralPath $PackagePath).Path
$signature = Get-AuthenticodeSignature -LiteralPath $resolvedPackage
if ($signature.Status -eq [System.Management.Automation.SignatureStatus]::NotSigned) {
    if (-not $AllowUnsigned) {
        throw "MSIX package is not signed: $resolvedPackage"
    }
}
elseif ($signature.Status -eq [System.Management.Automation.SignatureStatus]::HashMismatch) {
    throw "MSIX signature hash validation failed: $resolvedPackage"
}
elseif (($signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid) -and
    (-not $AllowUntrustedSignature)) {
    throw "MSIX signature is not trusted: $($signature.Status) - $($signature.StatusMessage)"
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::OpenRead($resolvedPackage)
try {
    $entries = @{}
    foreach ($entry in $archive.Entries) {
        $entries[$entry.FullName.Replace('\', '/')] = $entry
    }
    foreach ($requiredEntry in @('AppxManifest.xml', 'Battuta.exe')) {
        if (-not $entries.ContainsKey($requiredEntry)) {
            throw "MSIX package is missing '$requiredEntry'."
        }
    }

    $manifestStream = $entries['AppxManifest.xml'].Open()
    try {
        $reader = [System.IO.StreamReader]::new($manifestStream, [System.Text.Encoding]::UTF8, $true)
        try {
            [xml]$manifest = $reader.ReadToEnd()
        }
        finally {
            $reader.Dispose()
        }
    }
    finally {
        $manifestStream.Dispose()
    }
    $namespace = [System.Xml.XmlNamespaceManager]::new($manifest.NameTable)
    $namespace.AddNamespace('f', 'http://schemas.microsoft.com/appx/manifest/foundation/windows10')
    $identity = $manifest.SelectSingleNode('/f:Package/f:Identity', $namespace)
    if ($null -eq $identity) {
        throw 'MSIX manifest has no package identity.'
    }

    $soundFiles = @($archive.Entries | Where-Object {
        $_.FullName.Replace('\', '/').StartsWith('Assets/Sounds/', [System.StringComparison]::Ordinal) -and
        (-not [string]::IsNullOrEmpty($_.Name))
    })
    if ($soundFiles.Count -ne $ExpectedSoundCount) {
        throw "Expected $ExpectedSoundCount sound assets, found $($soundFiles.Count)."
    }
    $emptySound = $soundFiles | Where-Object Length -LE 0 | Select-Object -First 1
    if ($null -ne $emptySound) {
        throw "MSIX contains an empty sound asset: $($emptySound.FullName)"
    }

    Add-Type -AssemblyName System.Drawing
    $expectedLogos = @{
        'StoreLogo.png' = @(50, 50)
        'Square44x44Logo.png' = @(44, 44)
        'Square150x150Logo.png' = @(150, 150)
        'Wide310x150Logo.png' = @(310, 150)
    }
    foreach ($logoName in $expectedLogos.Keys) {
        $logoEntryName = "Assets/$logoName"
        if (-not $entries.ContainsKey($logoEntryName)) {
            throw "MSIX package is missing logo '$logoName'."
        }
        $logoStream = $entries[$logoEntryName].Open()
        try {
            $image = [System.Drawing.Image]::FromStream($logoStream)
            try {
                $size = $expectedLogos[$logoName]
                if ($image.Width -ne $size[0] -or $image.Height -ne $size[1]) {
                    throw "Logo '$logoName' must be $($size[0])x$($size[1]), found $($image.Width)x$($image.Height)."
                }
            }
            finally {
                $image.Dispose()
            }
        }
        finally {
            $logoStream.Dispose()
        }
    }

    [pscustomobject]@{
        Package = $resolvedPackage
        PackageName = $identity.Name
        Publisher = $identity.Publisher
        Version = $identity.Version
        Architecture = $identity.ProcessorArchitecture
        SignatureStatus = $signature.Status
        Signer = if ($null -eq $signature.SignerCertificate) { $null } else { $signature.SignerCertificate.Subject }
        SoundCount = $soundFiles.Count
        TotalFiles = $archive.Entries.Count
    }
}
finally {
    $archive.Dispose()
}
