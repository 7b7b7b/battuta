[CmdletBinding()]
param(
    [string]$SourceImage,
    [string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$scriptRoot = Split-Path -Parent $PSCommandPath
$windowsRoot = (Resolve-Path -LiteralPath (Join-Path $scriptRoot '..')).Path
$repositoryRoot = (Resolve-Path -LiteralPath (Join-Path $windowsRoot '..')).Path
if ([string]::IsNullOrWhiteSpace($SourceImage)) {
    $SourceImage = Join-Path $repositoryRoot 'SimuBoardMac\Design\AppIconSquare.png'
}
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $windowsRoot 'src\Battuta.Packaging\Assets'
}

$sourcePath = (Resolve-Path -LiteralPath $SourceImage).Path
$outputRoot = [System.IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null

Add-Type -AssemblyName System.Drawing

function Write-Logo {
    param(
        [Parameter(Mandatory = $true)]
        [System.Drawing.Image]$Source,
        [Parameter(Mandatory = $true)]
        [int]$Width,
        [Parameter(Mandatory = $true)]
        [int]$Height,
        [Parameter(Mandatory = $true)]
        [int]$IconSize,
        [Parameter(Mandatory = $true)]
        [string]$Destination
    )

    $bitmap = [System.Drawing.Bitmap]::new(
        $Width,
        $Height,
        [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    try {
        $bitmap.SetResolution(96, 96)
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        try {
            $graphics.Clear([System.Drawing.Color]::Transparent)
            $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceOver
            $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
            $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
            $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality

            $x = [int](($Width - $IconSize) / 2)
            $y = [int](($Height - $IconSize) / 2)
            $destinationRectangle = [System.Drawing.Rectangle]::new($x, $y, $IconSize, $IconSize)
            $sourceRectangle = [System.Drawing.Rectangle]::new(0, 0, $Source.Width, $Source.Height)
            $attributes = [System.Drawing.Imaging.ImageAttributes]::new()
            try {
                $attributes.SetWrapMode([System.Drawing.Drawing2D.WrapMode]::TileFlipXY)
                $graphics.DrawImage(
                    $Source,
                    $destinationRectangle,
                    $sourceRectangle.X,
                    $sourceRectangle.Y,
                    $sourceRectangle.Width,
                    $sourceRectangle.Height,
                    [System.Drawing.GraphicsUnit]::Pixel,
                    $attributes)
            }
            finally {
                $attributes.Dispose()
            }
        }
        finally {
            $graphics.Dispose()
        }

        $bitmap.Save($Destination, [System.Drawing.Imaging.ImageFormat]::Png)
    }
    finally {
        $bitmap.Dispose()
    }
}

$source = [System.Drawing.Image]::FromFile($sourcePath)
try {
    Write-Logo $source 50 50 44 (Join-Path $outputRoot 'StoreLogo.png')
    Write-Logo $source 1080 1080 950 (Join-Path $outputRoot 'StoreBoxArt1080.png')
    Write-Logo $source 71 71 62 (Join-Path $outputRoot 'StoreListingIcon71.png')
    Write-Logo $source 150 150 132 (Join-Path $outputRoot 'StoreListingIcon150.png')
    Write-Logo $source 300 300 264 (Join-Path $outputRoot 'StoreListingIcon.png')
    Write-Logo $source 44 44 38 (Join-Path $outputRoot 'Square44x44Logo.png')
    Write-Logo $source 150 150 132 (Join-Path $outputRoot 'Square150x150Logo.png')
    Write-Logo $source 310 150 132 (Join-Path $outputRoot 'Wide310x150Logo.png')
}
finally {
    $source.Dispose()
}

Get-ChildItem -LiteralPath $outputRoot -Filter '*.png' -File |
    Sort-Object Name |
    Select-Object Name, Length
