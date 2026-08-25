[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [string]$PackagePath,

    [Parameter(Mandatory = $true)]
    [string]$CertificatePath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$principal = [Security.Principal.WindowsPrincipal]::new(
    [Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Development MSIX installation must be run from an administrator PowerShell window because the test certificate is trusted machine-wide.'
}

$package = (Resolve-Path -LiteralPath $PackagePath).Path
$certificate = (Resolve-Path -LiteralPath $CertificatePath).Path
$signature = Get-AuthenticodeSignature -LiteralPath $package
if ($null -eq $signature.SignerCertificate) {
    throw "Package is not signed: $package"
}
$certificateObject = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($certificate)
if ($certificateObject.Thumbprint -ne $signature.SignerCertificate.Thumbprint) {
    throw 'The supplied certificate does not match the MSIX package signature.'
}

if ($PSCmdlet.ShouldProcess($certificateObject.Subject, 'Trust development certificate for this machine')) {
    $trusted = Get-ChildItem -LiteralPath Cert:\LocalMachine\TrustedPeople |
        Where-Object Thumbprint -eq $certificateObject.Thumbprint |
        Select-Object -First 1
    if ($null -eq $trusted) {
        Import-Certificate `
            -FilePath $certificate `
            -CertStoreLocation Cert:\LocalMachine\TrustedPeople | Out-Null
    }
}

if ($PSCmdlet.ShouldProcess($package, 'Install or update MSIX package')) {
    Add-AppxPackage -Path $package -ForceApplicationShutdown
}

Get-AppxPackage |
    Where-Object { $_.SignatureKind -ne 'None' -and $_.Publisher -eq $certificateObject.Subject } |
    Sort-Object InstallDate -Descending |
    Select-Object -First 1 Name, PackageFullName, Version, InstallLocation, Status
