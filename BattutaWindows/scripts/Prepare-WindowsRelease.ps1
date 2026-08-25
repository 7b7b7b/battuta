[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?$')]
    [string]$Version,

    [ValidateSet('win-x64', 'win-arm64')]
    [string]$Runtime = 'win-x64'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$scriptRoot = Split-Path -Parent $PSCommandPath
$windowsRoot = (Resolve-Path -LiteralPath (Join-Path $scriptRoot '..')).Path
$coreTests = Join-Path $windowsRoot 'tests\Battuta.Core.Tests\Battuta.Core.Tests.csproj'
$windowsTests = Join-Path $windowsRoot 'tests\Battuta.Windows.Tests\Battuta.Windows.Tests.csproj'

& dotnet test --project $coreTests --configuration Release
if ($LASTEXITCODE -ne 0) {
    throw "Battuta Core test suite failed with exit code $LASTEXITCODE"
}

& dotnet test --project $windowsTests --configuration Release
if ($LASTEXITCODE -ne 0) {
    throw "Battuta Windows test suite failed with exit code $LASTEXITCODE"
}

& (Join-Path $scriptRoot 'Publish-Portable.ps1') `
    -Version $Version `
    -Runtime $Runtime `
    -Configuration Release
