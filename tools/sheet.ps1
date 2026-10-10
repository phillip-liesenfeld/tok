# sheet.ps1 - lays docs\looks\*.png out on one captioned contact sheet (docs\looks-sheet.png).
# Render the looks first: pwsh -STA -File tok.ps1 -RenderDir docs\looks
param([string]$Dir = (Join-Path (Split-Path $PSScriptRoot) 'docs\looks'), [string]$Out = (Join-Path (Split-Path $PSScriptRoot) 'docs\looks-sheet.png'), [int]$Cols = 5)
Add-Type -AssemblyName System.Drawing
$files = Get-ChildItem $Dir -Filter *.png | Sort-Object Name
$w = 320; $h = 310; $cap = 34
$rows = [math]::Ceiling($files.Count / $Cols)
$bmp = [Drawing.Bitmap]::new($Cols * $w, $rows * ($h + $cap))
$g = [Drawing.Graphics]::FromImage($bmp)
$g.InterpolationMode = 'HighQualityBicubic'; $g.TextRenderingHint = 'AntiAliasGridFit'
$g.Clear([Drawing.Color]::FromArgb(255, 244, 239, 233))
$font = [Drawing.Font]::new('Segoe UI Semibold', 11)
$fmt = [Drawing.StringFormat]::new(); $fmt.Alignment = 'Center'
$ink = [Drawing.SolidBrush]::new([Drawing.Color]::FromArgb(255, 90, 60, 48))
for ($i = 0; $i -lt $files.Count; $i++) {
    $x = ($i % $Cols) * $w; $y = [math]::Floor($i / $Cols) * ($h + $cap)
    $img = [Drawing.Image]::FromFile($files[$i].FullName)
    $g.DrawImage($img, $x, $y, $w, $h); $img.Dispose()
    $label = ($files[$i].BaseName -replace '^\d\d-', '') -replace '-', ' · '
    $g.DrawString($label, $font, $ink, [Drawing.RectangleF]::new($x, $y + $h, $w, $cap), $fmt)
}
$bmp.Save($Out, [Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
"$Out ($($files.Count) looks)"
