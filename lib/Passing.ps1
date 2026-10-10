# Passing.ps1 - the set piece for a new model (port phase 4): a passing-on, not a coming back.
# An elder lets its petals go, its heart dries to a seed and drops, it waves goodbye to the seed, closes its eyes and
# pours its light into it, and the seed swells into an egg. A younger Tok just curls up into the egg. The egg then
# wobbles, cracks, the top flies off, the hatchling pops up inside the bottom half, and the bottom half falls away.
#
# It is all WPF animation: each phase is one Storyboard (one clock) of keyframe tracks over the real creature and an
# overlay canvas (Pass) drawn above it. The tick loop only watches that clock to say the hatch line on cue, to start
# the next phase, and (when recording) to seek the clock frame by frame so a slow frame doesn't speed the GIF up.
# The piece reads a plan (Get-MoltPlan in Lineage.ps1) and never touches the state; only the caller changes the state.

$script:Passing = $null        # the running piece, or $null
$script:StageHold = $null      # while it runs, Get-Stage answers with this (the creature must not shrink to an egg mid-piece)
$script:PassTint = $null       # the egg's spot colour while it runs (the plan's)
$script:PassBuilt = $false
$script:EggD = 'M70,26 C100,26 112,70 112,92 C112,118 94,132 70,132 C46,132 28,118 28,92 C28,70 40,26 70,26 Z'
$script:EggTopD = 'M31,74 L44,72 L54,80 L60,72 L68,82 L76,72 L84,80 L94,72 L109,74 C107,50 96,26 70,26 C44,26 33,50 31,74 Z'
$script:EggBotD = 'M31,74 L44,72 L54,80 L60,72 L68,82 L76,72 L84,80 L94,72 L109,74 C111,82 112,88 112,92 C112,118 94,132 70,132 C46,132 28,118 28,92 C28,88 29,82 31,74 Z'
$script:PassSeed = '#FFB07A45'
$script:PassGold = '#FFFFE07A'
$script:PassMotes = 26
$script:PassFps = 20
# Property paths, for a Storyboard aimed at an element. Pet and Creature keep their scale first in a TransformGroup.
$script:PP = @{
    Op = '(UIElement.Opacity)'; Vis = '(UIElement.Visibility)'
    Sx = '(UIElement.RenderTransform).(TransformGroup.Children)[0].(ScaleTransform.ScaleX)'
    Sy = '(UIElement.RenderTransform).(TransformGroup.Children)[0].(ScaleTransform.ScaleY)'
    Rot = '(UIElement.RenderTransform).(TransformGroup.Children)[1].(RotateTransform.Angle)'
    Tx = '(UIElement.RenderTransform).(TransformGroup.Children)[2].(TranslateTransform.X)'
    Ty = '(UIElement.RenderTransform).(TransformGroup.Children)[2].(TranslateTransform.Y)'
    HopY = '(UIElement.RenderTransform).(TransformGroup.Children)[2].(TranslateTransform.Y)'
    Angle = '(UIElement.RenderTransform).(RotateTransform.Angle)'
    PupX = '(UIElement.RenderTransform).(TranslateTransform.X)'; PupY = '(UIElement.RenderTransform).(TranslateTransform.Y)'
    SpecY = '(UIElement.RenderTransform).(TransformGroup.Children)[0].(TranslateTransform.Y)'
    SpecRot = '(UIElement.RenderTransform).(TransformGroup.Children)[1].(RotateTransform.Angle)'
}

# ---------------------------------------------------------------- the overlay (built once, drawn above everything in Pet)
# A group whose scale, rotation and translation can all be animated: children are drawn around (0,0) or wherever they like;
# Cx, Cy is the pivot for scale and rotation.
function Get-AnimGroupXaml([string]$Name, [double]$Cx, [double]$Cy, [string]$Inner, [string]$Extra = '') {
    "<Canvas x:Name='$Name' $Extra><Canvas.RenderTransform><TransformGroup><ScaleTransform CenterX='$(N $Cx)' CenterY='$(N $Cy)'/><RotateTransform CenterX='$(N $Cx)' CenterY='$(N $Cy)'/><TranslateTransform/></TransformGroup></Canvas.RenderTransform>$Inner</Canvas>"
}

function Get-PassingXaml {
    $shell = "<RadialGradientBrush GradientOrigin='0.35,0.3'><GradientStop Color='#FFFFF8EE' Offset='0'/><GradientStop Color='#FFEBD9C2' Offset='1'/></RadialGradientBrush>"
    $spot = { param($n, $cx, $cy, $rx, $ry) "<Path x:Name='$n' Fill='$script:EggSpotDefault'><Path.Data><EllipseGeometry Center='$cx,$cy' RadiusX='$rx' RadiusY='$ry'/></Path.Data></Path>" }
    $half = { param($n, $d, $spots) Get-AnimGroupXaml $n 70 74 "<Path Data='$d' Stroke='#FFC9B39A' StrokeThickness='1' StrokeLineJoin='Round'><Path.Fill>$shell</Path.Fill></Path>$spots" "Opacity='0'" }

    # the flower: the same two rings of petals as the elder's (lib\Art.ps1), each petal its own animatable group
    $petals = ''
    foreach ($i in 0..7) {
        $a = 45 * $i * [math]::PI / 180
        $petals += Get-AnimGroupXaml "PB$i" (9.7 * [math]::Sin($a)) (-9.7 * [math]::Cos($a)) (Get-PathXaml $script:PetalD $script:DeepGold $script:PetalEdge 1.1 @(@('r', (45 * $i)), @('s', 1.08, 1.08)))
    }
    foreach ($i in 0..7) {
        $a = (45 * $i + 22.5) * [math]::PI / 180
        $petals += Get-AnimGroupXaml "PF$i" (9 * [math]::Sin($a)) (-9 * [math]::Cos($a)) (Get-PathXaml $script:PetalD $script:Petal $script:PetalEdge 1.2 @(, @('r', (45 * $i + 22.5))))
    }
    $dots = (0..5 | ForEach-Object { $a = $_ * [math]::PI / 3; Get-EllXaml (2.6 * [math]::Cos($a)) (2.6 * [math]::Sin($a)) 0.9 0.9 $script:Seed }) -join ''
    $heart = Get-AnimGroupXaml 'PHeartG' 0 0 ((Get-EllXaml 0 0 6.4 6.4 $script:Heart $script:HeartEdge 1.1 $null "x:Name='PHeartDot'") + "<Canvas x:Name='PDots'>$dots$(Get-EllXaml 0 0 0.9 0.9 $script:Seed)</Canvas>")
    $flower = "<Canvas x:Name='PFlower'><Canvas.RenderTransform><TransformGroup><ScaleTransform ScaleX='0.82' ScaleY='0.82'/><TranslateTransform X='71' Y='13'/></TransformGroup></Canvas.RenderTransform>$petals$heart</Canvas>"

    $seedBody = "<Path Data='M0,-8 C6,-6 7.5,2 0,7.5 C-7.5,2 -6,-6 0,-8 Z' Fill='$script:PassSeed' Stroke='#802B1B17' StrokeThickness='1.1' StrokeLineJoin='Round'/>" +
                "<Path Data='M-2,-3 C-2.5,-1 -2.5,1 -1.5,3' Stroke='#73FFFFFF' StrokeThickness='1.4' StrokeStartLineCap='Round' StrokeEndLineCap='Round'/>"
    $glow = Get-AnimGroupXaml 'PGlow' 70 122 "<Path><Path.Data><EllipseGeometry Center='70,122' RadiusX='14' RadiusY='14'/></Path.Data><Path.Fill><RadialGradientBrush><GradientStop Color='#FFFFE07A' Offset='0'/><GradientStop Color='#00FFE07A' Offset='1'/></RadialGradientBrush></Path.Fill></Path>" "Opacity='0'"
    $motes = (0..($script:PassMotes - 1) | ForEach-Object { Get-AnimGroupXaml "PM$_" 0 0 "<Path Fill='$script:PassGold'><Path.Data><EllipseGeometry RadiusX='3' RadiusY='3'/></Path.Data></Path>" "Opacity='0'" }) -join ''
    $egg = Get-AnimGroupXaml 'PEgg' 70 140 ("<Path Data='$script:EggD'><Path.Fill>$shell</Path.Fill></Path>" + (& $spot 'PESp1' 55 63 7 5) + (& $spot 'PESp2' 89 90 9 6) + (& $spot 'PESp3' 57 108 5 4)) "Opacity='0'"
    $ring = "<Path x:Name='PRing' Stroke='#FFFFE7A8' StrokeThickness='3' Opacity='0'><Path.Data><EllipseGeometry Center='70,92' RadiusX='26' RadiusY='26'/></Path.Data></Path>"
    $pill = "<Border x:Name='PPill' Canvas.Left='92' Canvas.Top='14' Height='20' CornerRadius='10' Background='#FFFFF6E6' BorderBrush='#FF9C4630' BorderThickness='1.5' Padding='8,0' Opacity='0' RenderTransformOrigin='1,0.5'>" +
            "<Border.RenderTransform><ScaleTransform x:Name='PPillS'/></Border.RenderTransform>" +
            "<TextBlock x:Name='PPillText' HorizontalAlignment='Center' VerticalAlignment='Center' FontFamily='Segoe UI' FontSize='11' FontWeight='SemiBold' Foreground='#FF3A2018'/></Border>"
    @"
<Canvas xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation' xmlns:x='http://schemas.microsoft.com/winfx/2006/xaml'
        x:Name='Pass' Width='140' Height='140' Visibility='Collapsed' IsHitTestVisible='False'>
$flower
$glow
$egg
$(Get-AnimGroupXaml 'PSeed' 0 0 $seedBody "Opacity='0'")
$motes
$ring
$(& $half 'PTop' $script:EggTopD (& $spot 'PTSp1' 55 63 7 5))
$(& $half 'PBot' $script:EggBotD ((& $spot 'PBSp2' 89 90 9 6) + (& $spot 'PBSp3' 57 108 5 4)))
$pill
</Canvas>
"@
}

function Initialize-Passing {
    if ($script:PassBuilt) { return }
    $root = [Windows.Markup.XamlReader]::Parse((Get-PassingXaml))
    foreach ($m in [regex]::Matches((Get-PassingXaml), "x:Name='([A-Za-z0-9_]+)'")) { $ui[$m.Groups[1].Value] = $root.FindName($m.Groups[1].Value) }
    $ui['Pass'] = $root
    $null = $ui.Pet.Children.Add($root)
    $script:PassBuilt = $true
}

# The egg's spots, real and overlay. Coral by default; the plan's colour (the parent's flower) while a piece runs.
$script:EggSpotShown = $null
function Set-EggSpots([string]$Color) {
    if ($script:EggSpotShown -eq $Color) { return }
    $script:EggSpotShown = $Color
    $b = Get-Brush $Color
    foreach ($n in 'EggSpot1', 'EggSpot2', 'EggSpot3') { $ui[$n].Fill = $b }
    if ($script:PassBuilt) { foreach ($n in 'PESp1', 'PESp2', 'PESp3', 'PTSp1', 'PBSp2', 'PBSp3') { $ui[$n].Fill = (Get-Brush $Color) } }
}

# ---------------------------------------------------------------- tracks
# A track is a string of "seconds:value" keys, e.g. "0:1 0.4:1~ 3:0!". A trailing ~ eases into that key (smooth), a
# trailing ! jumps to it (discrete); anything else is linear. Visibility, colour and point tracks are always discrete
# (visibility, points) or linear (colour). Kind: d double, v visibility, c colour, p point.
function Add-Track($Sb, $El, [string]$Path, [string]$Keys, [string]$Kind = 'd') {
    $a = switch ($Kind) {
        'd' { [Windows.Media.Animation.DoubleAnimationUsingKeyFrames]::new() }
        'v' { [Windows.Media.Animation.ObjectAnimationUsingKeyFrames]::new() }
        'c' { [Windows.Media.Animation.ColorAnimationUsingKeyFrames]::new() }
        'p' { [Windows.Media.Animation.PointAnimationUsingKeyFrames]::new() }
    }
    $inv = [cultureinfo]::InvariantCulture
    foreach ($tok in $Keys.Split(' ', [StringSplitOptions]::RemoveEmptyEntries)) {
        $i = $tok.IndexOf(':'); $secs = [double]::Parse($tok.Substring(0, $i), $inv); $val = $tok.Substring($i + 1)
        $mode = 'L'
        if ($val.EndsWith('~')) { $mode = 'S'; $val = $val.TrimEnd('~') } elseif ($val.EndsWith('!')) { $mode = 'D'; $val = $val.TrimEnd('!') }
        $kt = [Windows.Media.Animation.KeyTime]::FromTimeSpan([TimeSpan]::FromSeconds($secs))
        $kf = switch ($Kind) {
            'd' {
                $v = [double]::Parse($val, $inv)
                if ($mode -eq 'D') { [Windows.Media.Animation.DiscreteDoubleKeyFrame]::new($v, $kt) }
                elseif ($mode -eq 'S') { [Windows.Media.Animation.EasingDoubleKeyFrame]::new($v, $kt, [Windows.Media.Animation.CubicEase]::new()) }
                else { [Windows.Media.Animation.LinearDoubleKeyFrame]::new($v, $kt) }
            }
            'v' { [Windows.Media.Animation.DiscreteObjectKeyFrame]::new([Windows.Visibility]$val, $kt) }
            'c' { [Windows.Media.Animation.LinearColorKeyFrame]::new([Windows.Media.ColorConverter]::ConvertFromString($val), $kt) }
            'p' { $xy = $val.Split(','); [Windows.Media.Animation.DiscretePointKeyFrame]::new([Windows.Point]::new([double]::Parse($xy[0], $inv), [double]::Parse($xy[1], $inv)), $kt) }
        }
        $null = $a.KeyFrames.Add($kf)
    }
    [Windows.Media.Animation.Storyboard]::SetTarget($a, $El)
    [Windows.Media.Animation.Storyboard]::SetTargetProperty($a, [Windows.PropertyPath]::new($Path))
    $null = $Sb.Children.Add($a)
}

# "t:f(q)" keys for q = 0..1 in N steps between seconds T0 and T1.
function Get-Samples([double]$T0, [double]$T1, [int]$N, [scriptblock]$F) {
    $out = for ($i = 0; $i -le $N; $i++) { $q = $i / $N; [string]::Format([cultureinfo]::InvariantCulture, '{0:0.###}:{1:0.####}', ($T0 + ($T1 - $T0) * $q), (& $F $q)) }
    $out -join ' '
}
function Get-Smooth([double]$Q) { $Q = [math]::Max(0.0, [math]::Min(1.0, $Q)); $Q * $Q * (3 - 2 * $Q) }

# ---------------------------------------------------------------- phases
# Each adds its tracks to a Storyboard and returns the length in seconds. $s0 is the scale the held stage had; the pet
# is scaled to the egg's 0.80 when the egg takes over, so the hand-off from the overlay egg to the real one is exact.
$script:EggScale = 0.80

function Add-PillTrack($Sb, [double]$Hold, [double]$Dur) {
    Add-Track $Sb $ui.PPill $script:PP.Op "0:0 0.4:1~ ${Hold}:1 $($Hold + 0.4):0~ ${Dur}:0"
}

# Eyes on the pill, then on the thing below: pupils are the real ones, moved by the same clock. Skipped in private mode (sunglasses).
function Add-LookTracks($Sb, [string]$Keys2D, [bool]$Private) {
    if ($Private) { return }
    $k = $script:PupilK
    foreach ($eye in $ui.EyeL, $ui.EyeR) {
        $pup = $eye.Children[1]
        $tx = $ui.PupilL.X; $ty = $ui.PupilL.Y
        $xs = @("0:$tx"); $ys = @("0:$ty")
        foreach ($step in $Keys2D.Split(' ', [StringSplitOptions]::RemoveEmptyEntries)) {
            $p = $step.Split(':'); $c = $p[1].Split(',')
            $xs += "$($p[0]):$([double]$c[0] * $k)~"; $ys += "$($p[0]):$([double]$c[1] * $k)~"
        }
        Add-Track $Sb $pup $script:PP.PupX ($xs -join ' ')
        Add-Track $Sb $pup $script:PP.PupY ($ys -join ' ')
    }
}

# The pet goes to the egg's scale and the real egg shows, at $T.
function Add-HandOffTracks($Sb, [double]$S0, [double]$T, [double]$EggFrom) {
    Add-Track $Sb $ui.Pet $script:PP.Sx "0:$S0 ${T}:$S0 $($T + 0.02):$($script:EggScale)!"
    Add-Track $Sb $ui.Pet $script:PP.Sy "0:$S0 ${T}:$S0 $($T + 0.02):$($script:EggScale)!"
    Add-Track $Sb $ui.Egg $script:PP.Vis "0:Collapsed! ${T}:Visible!" 'v'
    Add-Track $Sb $ui.EggCrack $script:PP.Vis '0:Collapsed!' 'v'
    Add-Track $Sb $ui.Creature $script:PP.Vis "0:Visible! ${T}:Collapsed!" 'v'
    Add-Track $Sb $ui.PEgg $script:PP.Op "0:0 ${EggFrom}:0 ${T}:1 $($T + 0.02):0!"
}

function Add-ElderPhase($Sb, [double]$S0, [bool]$Private) {
    $P = $script:PP
    $tW = 3.5; $tG = 5.3; $tH = $tG + 2.9; $dur = $tH + 0.4
    Add-PillTrack $Sb 3.0 $dur
    Add-LookTracks $Sb '0.3:3,-4 2.8:3,-4 3.2:0,3 3.5:0,4' $Private
    # the deep-gold back ring lets go, then the front petals fall one by one
    foreach ($i in 0..7) {
        Add-Track $Sb $ui["PB$i"] $P.Op '0:1 0.4:1 0.9:0'
        Add-Track $Sb $ui["PB$i"] $P.Ty "0:0 0.4:0 0.9:$(6 / 0.82)"
    }
    foreach ($k in 0..7) {
        $pang = (45 * $k + 22.5 - 90) * [math]::PI / 180; $t0 = 0.6 + 0.14 * $k
        $g = $ui["PF$k"]
        Add-Track $Sb $g $P.Tx ('0:0 ' + (Get-Samples $t0 ($t0 + 1.2) 8 { param($q) $e = Get-Smooth ($q / 0.15); ((4.6 * $e + 24 * $q) * [math]::Cos($pang) + 6 * [math]::Sin(6 * $q + $k) * [math]::Min(1, $q * 4)) / 0.82 }))
        Add-Track $Sb $g $P.Ty ('0:0 ' + (Get-Samples $t0 ($t0 + 1.2) 8 { param($q) $e = Get-Smooth ($q / 0.15); (4.6 * $e * [math]::Sin($pang) + 110 * $q * $q) / 0.82 }))
        Add-Track $Sb $g $P.Rot ('0:0 ' + (Get-Samples $t0 ($t0 + 1.2) 8 { param($q) 200 * $q }))
        Add-Track $Sb $g $P.Sx ('0:1 ' + (Get-Samples $t0 ($t0 + 1.2) 8 { param($q) 1 + ([math]::Abs([math]::Cos(4 * $q + $k)) * 0.7 + 0.3 - 1) * [math]::Min(1, $q * 5) }))
        Add-Track $Sb $g $P.Op ('0:1 ' + (Get-Samples $t0 ($t0 + 1.2) 8 { param($q) 1 - $q * $q }))
    }
    # the heart dries to a seed
    Add-Track $Sb $ui.PHeartDot '(Shape.Fill).(SolidColorBrush.Color)' "0:$script:Heart 1.9:$script:Heart 2.6:$script:PassSeed" 'c'
    Add-Track $Sb $ui.PHeartG $P.Sx '0:1 1.9:1 2.6:0.88'
    Add-Track $Sb $ui.PHeartG $P.Sy '0:1 1.9:1 2.6:0.88'
    Add-Track $Sb $ui.PDots $P.Op '0:1 1.9:1 2.4:0'
    Add-Track $Sb $ui.PHeartG $P.Op '0:1 2.7:1 2.9:0'
    # the seed drops in front of Tok
    Add-Track $Sb $ui.PSeed $P.Op "0:0 2.7:0 2.9:1 $($tG + 1.7):1 ${tH}:0"
    Add-Track $Sb $ui.PSeed $P.Tx ("0:71 " + (Get-Samples 2.8 3.5 5 { param($q) 71 - $q }))
    Add-Track $Sb $ui.PSeed $P.Ty ("0:13 " + (Get-Samples 2.8 3.5 5 { param($q) 13 + 111 * $q * $q }) + " 3.62:120 3.75:124")
    Add-Track $Sb $ui.PSeed $P.Rot ("0:0 " + (Get-Samples 2.8 3.5 5 { param($q) 25 * [math]::Sin([math]::PI * $q) }))
    Add-Track $Sb $ui.PSeed $P.Sx "0:0.8 $($tG + 1.7):0.8 ${tH}:3.2~"
    Add-Track $Sb $ui.PSeed $P.Sy "0:0.8 $($tG + 1.7):0.8 ${tH}:3.2~"
    if (-not $Private) {
        # happy eyes and a wave, spectacles on; then the eyes close (the spectacles slip) and the light pours out
        Add-Track $Sb $ui.EyeL $P.Vis "0:Visible! ${tW}:Collapsed!" 'v'
        Add-Track $Sb $ui.EyeR $P.Vis "0:Visible! ${tW}:Collapsed!" 'v'
        Add-Track $Sb $ui.HappyEyes $P.Vis "0:Collapsed! ${tW}:Visible! ${tG}:Collapsed!" 'v'
        Add-Track $Sb $ui.ClosedEyes $P.Vis "0:Collapsed! ${tG}:Visible!" 'v'
    }
    Add-Track $Sb $ui.Specs $P.SpecY "0:0 ${tG}:0 $($tG + 0.3):5~"
    Add-Track $Sb $ui.Specs $P.SpecRot "0:0 ${tG}:0 $($tG + 0.3):-7~"
    Add-Track $Sb $ui.ArmR '(Path.Data).(EllipseGeometry.Center)' "0:109,98 ${tW}:116,62! ${tG}:109,98!" 'p'
    Add-Track $Sb $ui.ArmR '(UIElement.RenderTransform).(RotateTransform.CenterX)' "0:109 ${tW}:116! ${tG}:109!"
    Add-Track $Sb $ui.ArmR '(UIElement.RenderTransform).(RotateTransform.CenterY)' "0:98 ${tW}:62! ${tG}:98!"
    $wave = "0:-22 ${tW}:17!"; $up = $true
    for ($t = $tW + 0.3; $t -lt $tG - 0.05; $t += 0.3) { $wave += " ${t}:$(if ($up) { '47' } else { '17' })~"; $up = -not $up }
    Add-Track $Sb $ui.ArmR $P.Angle "$wave ${tG}:-22!"
    # Tok fades as the motes leave it; the motes arc from all over its body into the seed
    Add-Track $Sb $ui.Creature $P.Op "0:1 $($tG + 0.6):1 $($tG + 1.7):0~"
    $rng = [System.Random]::new(7)
    foreach ($k in 0..($script:PassMotes - 1)) {
        $a0 = $tG + 0.3 + $rng.NextDouble() * 0.9
        $ang = $rng.NextDouble() * 2 * [math]::PI; $r = 15 + $rng.NextDouble() * 25
        $x0 = 70 + $r * [math]::Cos($ang); $y0 = 86 + $r * [math]::Sin($ang)
        $m = $ui["PM$k"]
        Add-Track $Sb $m $P.Tx ("0:$x0 " + (Get-Samples $a0 ($a0 + 0.9) 6 { param($q) $x0 + (70 - $x0) * (Get-Smooth $q) }))
        Add-Track $Sb $m $P.Ty ("0:$y0 " + (Get-Samples $a0 ($a0 + 0.9) 6 { param($q) $y0 + (122 - $y0) * (Get-Smooth $q) - 18 * [math]::Sin([math]::PI * $q) }))
        Add-Track $Sb $m $P.Sx "0:1 $($a0 + 0.9):0.45"
        Add-Track $Sb $m $P.Sy "0:1 $($a0 + 0.9):0.45"
        Add-Track $Sb $m $P.Op ("0:0 $($a0 - 0.01):0 " + (Get-Samples $a0 ($a0 + 0.9) 6 { param($q) 0.9 * (1 - $q * $q) }))
    }
    # the seed glows as the light arrives, then swells into the egg
    Add-Track $Sb $ui.PGlow $P.Op "0:0 $($tG + 0.6):0 $($tG + 1.7):0.35 ${tH}:0~"
    Add-Track $Sb $ui.PGlow $P.Sx "0:0.43 $($tG + 0.6):0.43 $($tG + 1.7):1"
    Add-Track $Sb $ui.PGlow $P.Sy "0:0.43 $($tG + 0.6):0.43 $($tG + 1.7):1"
    Add-Track $Sb $ui.PEgg $P.Sx "0:0.25 $($tG + 1.7):$(0.25 / $S0) ${tH}:$($script:EggScale / $S0)~"
    Add-Track $Sb $ui.PEgg $P.Sy "0:0.25 $($tG + 1.7):$(0.25 / $S0) ${tH}:$($script:EggScale / $S0)~"
    Add-HandOffTracks $Sb $S0 $tH ($tG + 1.7)
    $dur
}

function Add-YoungPhase($Sb, [double]$S0, [bool]$Private) {
    $P = $script:PP
    $tC = 3.6; $tT = 3.8; $tE = 4.9; $dur = $tE + 0.4
    Add-PillTrack $Sb 3.4 $dur
    Add-LookTracks $Sb '0.3:3,-4 3.4:3,-4' $Private
    if (-not $Private) {
        Add-Track $Sb $ui.EyeL $P.Vis "0:Visible! ${tC}:Collapsed!" 'v'
        Add-Track $Sb $ui.EyeR $P.Vis "0:Visible! ${tC}:Collapsed!" 'v'
        Add-Track $Sb $ui.ClosedEyes $P.Vis "0:Collapsed! ${tC}:Visible!" 'v'
    }
    # it curls up small, the shell closes around it, a ring flash
    Add-Track $Sb $ui.Creature $P.Sx "0:1 ${tT}:1 $($tT + 1.0):0.62~"
    Add-Track $Sb $ui.Creature $P.Sy "0:1 ${tT}:1 $($tT + 1.0):0.62~"
    Add-Track $Sb $ui.Creature $P.Op "0:1 $($tT + 0.3):1 $($tT + 1.0):0~"
    Add-Track $Sb $ui.PEgg $P.Sx "0:$(0.6 / $S0) $($tT + 0.3):$(0.6 / $S0) ${tE}:$($script:EggScale / $S0)~"
    Add-Track $Sb $ui.PEgg $P.Sy "0:$(0.6 / $S0) $($tT + 0.3):$(0.6 / $S0) ${tE}:$($script:EggScale / $S0)~"
    Add-Track $Sb $ui.PRing $P.Op "0:0 $($tT + 0.29):0 $($tT + 0.3):0.95 $($tT + 1.1):0"
    Add-Track $Sb $ui.PRing '(Path.Data).(EllipseGeometry.RadiusX)' "0:26 $($tT + 0.3):26 $($tT + 1.1):56"
    Add-Track $Sb $ui.PRing '(Path.Data).(EllipseGeometry.RadiusY)' "0:26 $($tT + 0.3):26 $($tT + 1.1):56"
    Add-Track $Sb $ui.PRing '(Shape.StrokeThickness)' "0:3 $($tT + 0.3):3 $($tT + 1.1):0.5"
    Add-HandOffTracks $Sb $S0 $tE ($tT + 0.3)
    $dur
}

# Not much to curl up: an egg meeting a new model only gets the flash.
function Add-EggPhase($Sb, [double]$S0, [bool]$Private) {
    $P = $script:PP
    Add-PillTrack $Sb 2.2 3.0
    Add-Track $Sb $ui.PRing $P.Op '0:0 2.39:0 2.4:0.95 3.1:0'
    Add-Track $Sb $ui.PRing '(Path.Data).(EllipseGeometry.RadiusX)' '0:26 2.4:26 3.1:56'
    Add-Track $Sb $ui.PRing '(Path.Data).(EllipseGeometry.RadiusY)' '0:26 2.4:26 3.1:56'
    Add-Track $Sb $ui.Pet $script:PP.Sx "0:$($script:EggScale) 3.2:$($script:EggScale)"
    Add-Track $Sb $ui.Pet $script:PP.Sy "0:$($script:EggScale) 3.2:$($script:EggScale)"
    3.2
}

# The egg wobbles, cracks, the top flies off, the hatchling pops up inside the bottom half, the bottom half falls away.
function Add-HatchPhase($Sb, [double]$S0, [bool]$Private) {
    $P = $script:PP
    $tTop = 2.6; $dur = 4.8
    $rel = 0.70 / $script:EggScale          # the hatchling's size inside the egg's 0.80 scale
    Add-Track $Sb $ui.PPill $P.Op "0:0 ${dur}:0"
    Add-Track $Sb $ui.Pet $P.Sx "0:$($script:EggScale) ${dur}:$($script:EggScale)"
    Add-Track $Sb $ui.Pet $P.Sy "0:$($script:EggScale) ${dur}:$($script:EggScale)"
    Add-Track $Sb $ui.Egg $P.Vis "0:Visible! ${tTop}:Collapsed!" 'v'
    Add-Track $Sb $ui.EggCrack $P.Vis '0:Collapsed! 1.4:Visible!' 'v'
    $wob = (Get-Samples 0.6 1.4 14 { param($q) 7 * [math]::Sin(2 * [math]::PI * 2 * $q) * (1 - $q) }) + ' ' + (Get-Samples 1.9 2.5 12 { param($q) 9 * [math]::Sin(2 * [math]::PI * 3 * $q) * (1 - $q * 0.4) })
    Add-Track $Sb $ui.Egg $P.Angle "0:0 $wob ${tTop}:0"
    # the hatchling, hidden until the top is off
    Add-Track $Sb $ui.Creature $P.Vis "0:Collapsed! ${tTop}:Visible!" 'v'
    $pop = { param($q) $r = if ($q -lt 1) { (Get-Smooth $q) + 0.12 * [math]::Sin([math]::PI * [math]::Min($q, 1)) } else { 1 }; $rel * [math]::Max(0.2, $r) }
    Add-Track $Sb $ui.Creature $P.Sx ("0:$($rel * 0.2) " + (Get-Samples $tTop ($tTop + 0.6) 8 $pop))
    Add-Track $Sb $ui.Creature $P.Sy ("0:$($rel * 0.2) " + (Get-Samples $tTop ($tTop + 0.6) 8 $pop))
    Add-Track $Sb $ui.Creature $P.HopY "0:0 ${tTop}:0 $($tTop + 0.3):-10~ $($tTop + 0.65):0~"
    if (-not $Private) { Add-LookTracks $Sb "$($tTop + 0.2):0,-1" $Private }
    # the top flies off (q over 0.6 s), then fades; the bottom half stays a moment, then falls away

    Add-Track $Sb $ui.PTop $P.Op "0:0 ${tTop}:1! $($tTop + 0.1):1 $($tTop + 0.8):0"
    Add-Track $Sb $ui.PTop $P.Tx ("0:0 " + (Get-Samples $tTop ($tTop + 0.7) 7 { param($f) -26 * (Get-Smooth ([math]::Min(1, $f / 0.857))) / 0.8 }))
    Add-Track $Sb $ui.PTop $P.Ty ("0:0 " + (Get-Samples $tTop ($tTop + 0.7) 7 { param($f) $g = [math]::Min(1, $f / 0.857); (-30 * [math]::Sin([math]::PI * [math]::Min($g * 0.8, 1)) - 8 * $g) / 0.8 }))
    Add-Track $Sb $ui.PTop $P.Rot ("0:0 " + (Get-Samples $tTop ($tTop + 0.7) 7 { param($f) -40 * [math]::Min(1, $f / 0.857) }))
    Add-Track $Sb $ui.PBot $P.Op "0:0 ${tTop}:1! 3.7:1 4.3:0"
    Add-Track $Sb $ui.PBot $P.Ty '0:0 3.7:0 4.3:16~'
    Add-Track $Sb $ui.PBot $P.Rot '0:0 3.7:0 4.3:9~'
    $dur
}

# ---------------------------------------------------------------- running a piece
# Hold the stage the old Tok was in, drawn awake, so nothing shrinks or hides before the piece says so.
function Set-PassPose([string]$Stage) {
    $saved = $script:Passing; $script:Passing = $null
    $script:StageHold = $Stage; $script:Override = $null; $script:Meal = $null
    try { Update-Look 'happy' } finally { $script:Passing = $saved }
    $ui.ClosedEyes.Data = [Windows.Media.Geometry]::Parse((Get-ClosedEyesData 84))
    $ui.SproutRot.BeginAnimation([Windows.Media.RotateTransform]::AngleProperty, $null); $ui.SproutRot.Angle = 0
    $ui.SpecsRot.CenterY = 85
}

function Start-PassPhase {
    $p = $script:Passing
    $ph = $p.Phases[$p.Index]
    $held = $p.Plan.Stage
    $private = Test-Private
    Set-PassPose $(if ($ph -eq 'hatch') { 'hatchling' } else { $held })
    $s0 = [double](($Stages | Where-Object Name -eq $(if ($ph -eq 'hatch') { 'egg' } else { $held })).Scale)
    if ($s0 -le 0) { $s0 = 1.0 }
    $ui.Pass.Visibility = 'Visible'
    $ui.PPillText.Text = "$($p.Plan.Pill)"
    $ui.PPillS.ScaleX = 1 / $s0; $ui.PPillS.ScaleY = 1 / $s0
    $ui.PPill.Measure([Windows.Size]::new(200, 30)); [Windows.Controls.Canvas]::SetLeft($ui.PPill, 138 - $ui.PPill.DesiredSize.Width)
    $hide = if ($ph -eq 'elder') { 'Collapsed' } else { 'Visible' }
    $ui.ElderFlower.Visibility = $hide; $ui.ElderFlowerF.Visibility = $hide
    $ui.PFlower.Visibility = if ($ph -eq 'elder') { 'Visible' } else { 'Collapsed' }
    $sb = [Windows.Media.Animation.Storyboard]::new()
    [Windows.Media.Animation.Timeline]::SetDesiredFrameRate($sb, $script:PassFps)      # a transparent window is redrawn in software, so the piece is drawn at 20 fps, not 60
    $dur = switch ($ph) {
        'elder' { Add-ElderPhase $sb $s0 $private } 'young' { Add-YoungPhase $sb $s0 $private }
        'egg' { Add-EggPhase $sb $s0 $private } 'hatch' { Add-HatchPhase $sb $s0 $private }
    }
    $p.Sb = $sb; $p.Dur = [double]$dur; $p.Manual = $false
    # one cue: the hatch line, said as the shell cracks open
    $p.Cues = if ($ph -eq 'hatch') { @(@{ At = 2.7; Do = { Say $script:Passing.Plan.Line 6 -Pin }; Done = $false }) } else { @() }
    $sb.Begin($window, $true)
    if ($script:Rec) { $sb.Pause($window); $p.Manual = $true; $p.N0 = $script:Rec.N }
    $p.Phase = $ph
}

# Starts a piece from a plan (Get-MoltPlan / Get-HatchPlan). Returns $false if one is already running.
# AfterStage: a demo that doesn't own the state names the stage to settle into when the piece ends.
function Start-Passing($Plan, [string]$AfterStage = '') {
    if ($script:Passing) { return $false }
    Initialize-Passing
    $script:Passing = @{ Plan = $Plan; Phases = @($Plan.Phases); Index = -1; Sb = $null; Sbs = [System.Collections.Generic.List[object]]::new(); Cues = @(); AfterStage = $AfterStage; Dur = 0.0; Manual = $false; N0 = 0; Phase = '' }
    $script:PassTint = $Plan.SpotColor
    Set-EggSpots $Plan.SpotColor
    Write-BodyLog "passing: $($Plan.Phases -join ' + ') ($($Plan.Name))"
    Step-PassPhase
    $true
}

function Step-PassPhase {
    $p = $script:Passing
    if ($p.Sb) { $p.Sb.Stop($window); $p.Sb.Remove($window); $p.Sb = $null }
    $p.Index++
    if ($p.Index -ge $p.Phases.Count) { Stop-Passing; return }
    Start-PassPhase
}

function Stop-Passing {
    $p = $script:Passing
    if (-not $p) { return }
    $script:Passing = $null; $script:StageHold = $null; $script:PassTint = $null
    if ($p.AfterStage) { $script:ForcedStage = $p.AfterStage }
    $ui.ElderFlower.Visibility = 'Visible'; $ui.ElderFlowerF.Visibility = 'Visible'
    if ($p.Sb) { $p.Sb.Stop($window); $p.Sb.Remove($window) }
    $ui.Pass.Visibility = 'Collapsed'
    # everything the piece borrowed goes back to what the real look says
    $script:EyesKey = $null; $script:LastArms = ''; $script:LastSprout = ''; $script:MotionKind = ''
    $ui.SpecsRot.CenterY = 80
    $mood = if ((Get-Stage).Name -eq 'egg') { 'egg' } elseif ($script:Mood -in '', 'egg') { 'happy' } else { $script:Mood }
    $script:Mood = $mood
    Set-EggSpots (Get-EggSpotColor "$((Get-CurrentRec $script:State.Lineage).Tint)")
    Update-Look $mood
    Write-BodyLog 'passing: done'
}

# Called every tick: the cue, the next phase, and the recording clock.
function Step-Passing {
    $p = $script:Passing
    if (-not $p -or -not $p.Sb) { return }
    if ($p.Manual -and -not $script:Rec) { $p.Sb.Resume($window); $p.Manual = $false }
    $t = if ($p.Manual) { ($script:Rec.N - $p.N0) * 0.1 } else { $c = $p.Sb.GetCurrentTime($window); if ($null -eq $c) { $p.Dur } else { $c.TotalSeconds } }
    foreach ($cue in $p.Cues) { if (-not $cue.Done -and $t -ge $cue.At) { $cue.Done = $true; & $cue.Do } }
    if ($t -ge $p.Dur) { Step-PassPhase }
}

# When recording, the clock follows the frames (called after a frame is saved) so a slow frame can't speed the GIF up.
function Sync-PassingClock {
    $p = $script:Passing
    if ($p -and $p.Manual -and $p.Sb) { $p.Sb.Seek($window, [TimeSpan]::FromSeconds(($script:Rec.N - $p.N0) * 0.1), [Windows.Media.Animation.TimeSeekOrigin]::BeginTime) }
}
