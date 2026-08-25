Set-StrictMode -Version Latest

function Get-BattutaWindowsSdkTool {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('makeappx.exe', 'signtool.exe')]
        [string]$Name
    )

    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($null -ne $command) {
        return $command.Source
    }

    $kitsRoot = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'
    if (-not (Test-Path -LiteralPath $kitsRoot -PathType Container)) {
        throw "Windows SDK bin directory was not found: $kitsRoot"
    }

    $candidate = Get-ChildItem -LiteralPath $kitsRoot -Directory |
        Where-Object { $_.Name -match '^\d+\.\d+\.\d+\.\d+$' } |
        Sort-Object { [version]$_.Name } -Descending |
        ForEach-Object { Join-Path $_.FullName "x64\$Name" } |
        Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
        Select-Object -First 1
    if ([string]::IsNullOrWhiteSpace($candidate)) {
        throw "$Name was not found in the installed Windows SDK."
    }

    return $candidate
}

function Get-BattutaSigningCertificate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Thumbprint
    )

    $normalized = $Thumbprint.Replace(' ', '').ToUpperInvariant()
    $certificate = Get-ChildItem -LiteralPath Cert:\CurrentUser\My |
        Where-Object { $_.Thumbprint -eq $normalized } |
        Select-Object -First 1
    if ($null -eq $certificate) {
        throw "Signing certificate '$normalized' was not found in Cert:\CurrentUser\My."
    }
    if (-not $certificate.HasPrivateKey) {
        throw "Signing certificate '$normalized' has no accessible private key."
    }
    if ($certificate.NotAfter -le [DateTime]::Now) {
        throw "Signing certificate '$normalized' has expired."
    }

    return $certificate
}

function Invoke-BattutaSignFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Thumbprint,

        [Uri]$TimestampUri
    )

    $signTool = Get-BattutaWindowsSdkTool -Name 'signtool.exe'
    $arguments = @(
        'sign',
        '/fd', 'SHA256',
        '/sha1', $Thumbprint.Replace(' ', ''),
        '/s', 'My'
    )
    if ($null -ne $TimestampUri) {
        $arguments += @('/tr', $TimestampUri.AbsoluteUri, '/td', 'SHA256')
    }
    $arguments += $Path

    & $signTool @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "SignTool failed for '$Path' with exit code $LASTEXITCODE."
    }
}

function ConvertTo-BattutaXmlAttribute {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Value
    )

    return [System.Security.SecurityElement]::Escape($Value)
}

function Assert-BattutaPackageIdentityName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if ($Name.Length -lt 3 -or $Name.Length -gt 50 -or $Name -notmatch '^[A-Za-z0-9.-]+$') {
        throw 'Package identity name must be 3-50 characters and contain only letters, digits, periods, or hyphens.'
    }
}
