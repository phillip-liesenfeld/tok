# shot.ps1 - screenshot a rectangle given in DIPs (for checking the body's look).
param([double]$X = 0, [double]$Y = 0, [double]$W = 240, [double]$H = 250, [string]$Out = "$env:TEMP\body-shot.png", [double]$DipWidth = 1707)
Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type -Namespace Shot -Name Dpi -MemberDefinition '[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();'
$null = [Shot.Dpi]::SetProcessDPIAware()
$scale = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Width / $DipWidth
$r = [System.Drawing.Rectangle]::new([int]($X * $scale), [int]($Y * $scale), [int]($W * $scale), [int]($H * $scale))
$bmp = [System.Drawing.Bitmap]::new($r.Width, $r.Height)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($r.Location, [System.Drawing.Point]::Empty, $r.Size)
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
"saved $Out (scale $scale)"
