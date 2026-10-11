<# Extract feathered eyelid patches from the aligned generated blink frame for the display. #>
[CmdletBinding()]
param(
    [string]$ClosedImagePath
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
if (-not $ClosedImagePath) { $ClosedImagePath = Join-Path $PSScriptRoot 'assets\raven-chibi-closed.png' }
$source = [System.Drawing.Bitmap]::new((Resolve-Path -LiteralPath $ClosedImagePath).Path)
$overlay = [System.Drawing.Bitmap]::new(1254, 1254, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$result = [System.Drawing.Bitmap]::new(216, 216, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$graphics = [System.Drawing.Graphics]::FromImage($result)

try {
    if ($source.Width -ne 1254 -or $source.Height -ne 1254) {
        throw 'The blink frame must align with the original 1254 x 1254 artwork'
    }
    $eyeRegions = @(
        [System.Drawing.Rectangle]::new(430, 475, 185, 158),
        [System.Drawing.Rectangle]::new(675, 405, 190, 166)
    )
    foreach ($region in $eyeRegions) {
        for ($y = $region.Top; $y -lt $region.Bottom; $y++) {
            for ($x = $region.Left; $x -lt $region.Right; $x++) {
                $edge = [Math]::Min([Math]::Min($x - $region.Left, $region.Right - 1 - $x), [Math]::Min($y - $region.Top, $region.Bottom - 1 - $y))
                $weight = [Math]::Min(1.0, $edge / 10.0)
                $color = $source.GetPixel($x, $y)
                $alpha = [int][Math]::Round($color.A * $weight)
                $overlay.SetPixel($x, $y, [System.Drawing.Color]::FromArgb($alpha, $color.R, $color.G, $color.B))
            }
        }
    }
    $graphics.Clear([System.Drawing.Color]::Transparent)
    $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $graphics.DrawImage($overlay, [System.Drawing.Rectangle]::new(0, 0, 216, 216), 0, 0, 1254, 1254, [System.Drawing.GraphicsUnit]::Pixel)
    $destination = Join-Path $PSScriptRoot 'package\raven-blink.png'
    $patch = $result.Clone([System.Drawing.Rectangle]::new(72, 68, 79, 43), [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    try { $patch.Save($destination, [System.Drawing.Imaging.ImageFormat]::Png) } finally { $patch.Dispose() }
    Write-Output ('Built eye overlay: ' + $destination)
} finally {
    $graphics.Dispose()
    $result.Dispose()
    $overlay.Dispose()
    $source.Dispose()
}
