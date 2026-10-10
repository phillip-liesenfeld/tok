# Minions.ps1 - subagents, drawn as seeds: copies of Tok sent out, in each model's colour. They pop
# from the sprout, orbit while they work, and go back in through the "o" when they're done, leaving a
# little label of what they ate (sonnet +143k). No faces or badges: at 20 px those were noise.
#   haiku   deep green, small and zippy (gets the zoomies)  sonnet  blue, steady
#   opus    honey gold, bigger, floats higher at the back   fable   pale lilac, the lightest, drifts slow and high
#   other   orange, a curious stray
# The palette relies on brightness, not hue (Parliament session 7, for everyone): from light to dark fable 0.74, opus 0.59,
# other 0.45, sonnet 0.30, haiku 0.20 in relative luminance, each neighbour at least 1.2 apart in contrast ratio.
# The pure parts (kind, orbit, label) are tested; New-MinionVisual needs WPF loaded.

$script:MinionKinds = @{
    haiku  = @{ Name = 'haiku';  Seed = '#FF3F8A36'; Size = 18; Speed = 0.11;  Lift = 0;   Light = '#FFA9D99A'; Mid = '#FF4E9A43'; Edge = '#FF265A20'; Bob = 1.6; BobRate = 0.5;  Blink = 30 }
    sonnet = @{ Name = 'sonnet'; Seed = '#FF5E97DE'; Size = 22; Speed = 0.06;  Lift = 0;   Light = '#FFD4E7FC'; Mid = '#FF6FA8E8'; Edge = '#FF3466A8'; Bob = 1.2; BobRate = 0.22; Blink = 80 }
    opus   = @{ Name = 'opus';   Seed = '#FFF2C35A'; Size = 26; Speed = 0.035; Lift = -18; Light = '#FFFFF0C8'; Mid = '#FFF5CC6E'; Edge = '#FFC99A35'; Bob = 2.5; BobRate = 0.09; Blink = 0 }
    fable  = @{ Name = 'fable';  Seed = '#FFE4DAFB'; Size = 24; Speed = 0.045; Lift = -10; Light = '#FFF8F5FF'; Mid = '#FFEAE2FC'; Edge = '#FF9C86D6'; Bob = 2.0; BobRate = 0.12; Blink = 0 }
    other  = @{ Name = 'other';  Seed = '#FFF0A07F'; Size = 20; Speed = 0.06;  Lift = 0;   Light = '#FFFBD5C2'; Mid = '#FFF0A07F'; Edge = '#FFC0603F'; Bob = 1.2; BobRate = 0.25; Blink = 80 }
}

function Get-MinionKind([string]$Model) {
    foreach ($k in 'haiku', 'sonnet', 'opus', 'fable') { if ($Model -like "*$k*") { return $script:MinionKinds[$k] } }
    $script:MinionKinds.other
}

# Orbit around Tok's middle, in the Pet canvas (140x140). The bottom half of the ellipse is
# nearer the viewer: there the minion is drawn in front of Tok, larger; on the top half,
# behind Tok, smaller and a little faded.
$script:OrbitCx = 70; $script:OrbitCy = 86; $script:OrbitRx = 74; $script:OrbitRy = 22
function Get-OrbitPoint([double]$Angle, $Kind) {
    $sin = [math]::Sin($Angle)
    [pscustomobject]@{
        X     = $script:OrbitCx + $script:OrbitRx * [math]::Cos($Angle)
        # Lift (Opus floating) applies at the back, so it peeks over Tok's head but passes in front at belly height
        Y     = $script:OrbitCy + $Kind.Lift * (1 - $sin) / 2 + $script:OrbitRy * $sin
        Front = $sin -gt 0
        Depth = 0.82 + 0.3 * ($sin + 1) / 2     # scale: 0.82 at the back, 1.12 at the front
    }
}

function F([double]$v) { $v.ToString('0.##', [cultureinfo]::InvariantCulture) }

# Builds one seed. Returns the parts the animation loop moves (Look and Blink are kept for the loop's sake).
function New-MinionVisual($Kind) {
    $S = [double]$Kind.Size
    $bc = [Windows.Media.BrushConverter]::new()
    $root = [Windows.Controls.Canvas]@{ Width = $S; Height = $S; RenderTransformOrigin = [Windows.Point]::new(0.5, 0.5) }
    $scale = [Windows.Media.ScaleTransform]::new(0.01, 0.01)
    $spin = [Windows.Media.RotateTransform]::new(0)
    $tg = [Windows.Media.TransformGroup]::new(); $tg.Children.Add($scale); $tg.Children.Add($spin); $root.RenderTransform = $tg
    # the design's seed is a 15x15.5 teardrop around (0,0); scale it to fill the minion's box
    $k = $S / 16.5
    $seed = [Windows.Shapes.Path]@{ Fill = $bc.ConvertFromString($Kind.Seed); Stroke = $bc.ConvertFromString('#8C2B1B17'); StrokeThickness = 1.1; StrokeLineJoin = 'Round'
        Data = [Windows.Media.Geometry]::Parse('M0,-8 C6,-6 7.5,2 0,7.5 C-7.5,2 -6,-6 0,-8 Z') }
    $shine = [Windows.Shapes.Path]@{ Stroke = $bc.ConvertFromString('#73FFFFFF'); StrokeThickness = 1.4; StrokeStartLineCap = 'Round'; StrokeEndLineCap = 'Round'
        Data = [Windows.Media.Geometry]::Parse('M-2,-3 C-2.5,-1 -2.5,1 -1.5,3') }
    foreach ($el in $seed, $shine) {
        $t = [Windows.Media.TransformGroup]::new(); $t.Children.Add([Windows.Media.ScaleTransform]::new($k, $k)); $t.Children.Add([Windows.Media.TranslateTransform]::new($S / 2, $S / 2))
        $el.RenderTransform = $t; $null = $root.Children.Add($el)
    }
    @{ Root = $root; Scale = $scale; Spin = $spin; Look = [Windows.Media.TranslateTransform]::new(); Blink = [Windows.Media.ScaleTransform]::new(1, 1) }
}
