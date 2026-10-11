# icon.ps1 - makes tok.ico (the Start menu shortcut's and Settings > Apps' icon) from a rendered look: the adult with its lantern
# half lit, cropped to Tok without its shadow, at 256, 48, 32 and 16 px (PNG-compressed icon entries, Windows Vista and later).
#   pwsh -STA -NoProfile -File tok.ps1 -RenderDir <dir>      (with TOK_DATA_DIR pointed at a temp folder)
#   pwsh -NoProfile -File tools\icon.ps1 -Png <dir>\06-adult-50.png
param([Parameter(Mandatory)][string]$Png, [string]$Out = (Join-Path (Split-Path $PSScriptRoot) 'tok.ico'))
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$src = [System.Drawing.Bitmap]::new($Png)
try {
    # Tok's bounds: pixels more opaque than the shadow (#33000000)
    $minX = $src.Width; $minY = $src.Height; $maxX = -1; $maxY = -1
    for ($y = 0; $y -lt $src.Height; $y++) {
        for ($x = 0; $x -lt $src.Width; $x++) {
            if ($src.GetPixel($x, $y).A -gt 80) { if ($x -lt $minX) { $minX = $x }; if ($x -gt $maxX) { $maxX = $x }; if ($y -lt $minY) { $minY = $y }; if ($y -gt $maxY) { $maxY = $y } }
        }
    }
    $w = $maxX - $minX + 1; $h = $maxY - $minY + 1; $side = [math]::Max($w, $h)
    $entries = foreach ($size in 256, 48, 32, 16) {
        $bmp = [System.Drawing.Bitmap]::new($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.InterpolationMode = 'HighQualityBicubic'; $g.PixelOffsetMode = 'HighQuality'; $g.SmoothingMode = 'HighQuality'
        $k = $size / $side
        $dw = $w * $k; $dh = $h * $k
        $g.DrawImage($src, [System.Drawing.RectangleF]::new(($size - $dw) / 2, ($size - $dh) / 2, $dw, $dh), [System.Drawing.RectangleF]::new($minX, $minY, $w, $h), 'Pixel')
        $g.Dispose()
        $ms = [IO.MemoryStream]::new(); $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
        @{ Size = $size; Bytes = $ms.ToArray() }
    }
} finally { $src.Dispose() }

# ICONDIR, one ICONDIRENTRY per size, then the PNGs
$fs = [IO.File]::Create($Out); $bw = [IO.BinaryWriter]::new($fs)
try {
    $bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]$entries.Count)
    $offset = 6 + 16 * $entries.Count
    foreach ($e in $entries) {
        $d = if ($e.Size -ge 256) { 0 } else { $e.Size }
        $bw.Write([byte]$d); $bw.Write([byte]$d); $bw.Write([byte]0); $bw.Write([byte]0)
        $bw.Write([uint16]1); $bw.Write([uint16]32); $bw.Write([uint32]$e.Bytes.Length); $bw.Write([uint32]$offset)
        $offset += $e.Bytes.Length
    }
    foreach ($e in $entries) { $bw.Write($e.Bytes) }
} finally { $bw.Dispose() }
"saved $Out ($((Get-Item $Out).Length) bytes)"
