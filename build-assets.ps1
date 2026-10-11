<# Build device-sized Raven artwork while preserving its transparent alpha channel. #>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ImagePath
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$sourcePath = (Resolve-Path -LiteralPath $ImagePath).Path
$packagePath = Join-Path $PSScriptRoot 'package'
$null = New-Item -ItemType Directory -Path $packagePath -Force
$sourceImage = [System.Drawing.Bitmap]::new($sourcePath)

function Save-FittedImage {
    param([int]$Size, [string]$Destination)
    $bitmap = [System.Drawing.Bitmap]::new($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $attributes = [System.Drawing.Imaging.ImageAttributes]::new()
    try {
        $graphics.Clear([System.Drawing.Color]::Transparent)
        $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $attributes.SetWrapMode([System.Drawing.Drawing2D.WrapMode]::TileFlipXY)
        $scale = [Math]::Min($Size / $sourceImage.Width, $Size / $sourceImage.Height)
        $width = [int][Math]::Round($sourceImage.Width * $scale)
        $height = [int][Math]::Round($sourceImage.Height * $scale)
        $rectangle = [System.Drawing.Rectangle]::new([int](($Size - $width) / 2), [int](($Size - $height) / 2), $width, $height)
        $graphics.DrawImage($sourceImage, $rectangle, 0, 0, $sourceImage.Width, $sourceImage.Height, [System.Drawing.GraphicsUnit]::Pixel, $attributes)
        $bitmap.Save($Destination, [System.Drawing.Imaging.ImageFormat]::Png)
        Write-Output ("Built {0}: {1} x {1}" -f $Destination, $Size)
    } finally {
        $attributes.Dispose()
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

try {
    Save-FittedImage -Size 216 -Destination (Join-Path $packagePath 'raven.png')
    Save-FittedImage -Size 64 -Destination (Join-Path $packagePath 'main.png')
} finally {
    $sourceImage.Dispose()
}
