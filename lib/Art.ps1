# Art.ps1 - Tok's body as XAML, from the Parliament's drawings (design\drafts-2026-10-07\full.py and
# design\parliament\gen\final\gen.py, which render the same shapes as SVG).
# The belly is a lantern: a glass window that fills with honey for the 5-hour window. The sprout is age
# (hatchling, kid, adult, elder). The limit happens to Tok itself: it curls up under a blue nightcap.
# Everything here is plain WPF shapes on the 140x140 grid; tok.ps1 shows, hides and moves the named parts.

$script:Ink = '#FF2B1B17'; $script:MouthInk = '#FF5A2A1E'; $script:Rim = '#FFA24E36'
$script:Leaf = '#FF7DB552'; $script:LeafHi = '#FFA6D277'; $script:LeafEdge = '#FF4E7E33'
$script:Petal = '#FFFFCF4D'; $script:PetalEdge = '#FFC4831C'; $script:Heart = '#FFE8803A'; $script:HeartEdge = '#FFA9561F'
$script:PetalD = 'M0,-1 C-5.5,-4 -6.5,-13 -2.6,-17.5 Q0,-15.6 2.6,-17.5 C6.5,-13 5.5,-4 0,-1 Z'
$script:LeafD = 'M0,0 C4,-7 14,-8 19,-2 C13,4 5,4 0,0 Z'

function N([double]$v) { $v.ToString('0.###', [cultureinfo]::InvariantCulture) }

# Transforms, written in SVG order (outermost first): @('t', x, y), @('s', sx, sy), @('r', angle, cx, cy).
# WPF applies a TransformGroup's children first to last, so the list is reversed.
function Get-TfXaml([string]$Tag, [object[]]$Ops) {
    if (-not $Ops) { return '' }
    if ($Ops[0] -is [string]) { $Ops = , $Ops }     # PowerShell flattens @(@('r', 45)) into one op; put it back
    $parts = for ($i = $Ops.Count - 1; $i -ge 0; $i--) {
        $o = $Ops[$i]
        switch ($o[0]) {
            't' { "<TranslateTransform X='$(N $o[1])' Y='$(N $o[2])'/>" }
            's' { "<ScaleTransform ScaleX='$(N $o[1])' ScaleY='$(N $o[2])'/>" }
            'r' { "<RotateTransform Angle='$(N $o[1])' CenterX='$(N ($o[2] ?? 0))' CenterY='$(N ($o[3] ?? 0))'/>" }
        }
    }
    "<$Tag.RenderTransform><TransformGroup>$($parts -join '')</TransformGroup></$Tag.RenderTransform>"
}

function Get-PathXaml([string]$D, [string]$Fill = 'Transparent', [string]$Stroke = '', [double]$Width = 0, [object[]]$Tf = $null, [string]$Extra = '') {
    $s = if ($Stroke) { " Stroke='$Stroke' StrokeThickness='$(N $Width)' StrokeStartLineCap='Round' StrokeEndLineCap='Round' StrokeLineJoin='Round'" } else { '' }
    "<Path Data='$D' Fill='$Fill'$s $Extra>$(Get-TfXaml 'Path' $Tf)</Path>"
}

function Get-EllXaml([double]$Cx, [double]$Cy, [double]$Rx, [double]$Ry, [string]$Fill, [string]$Stroke = '', [double]$Width = 0, [object[]]$Tf = $null, [string]$Extra = '', [string]$GeoName = '') {
    $s = if ($Stroke) { " Stroke='$Stroke' StrokeThickness='$(N $Width)'" } else { '' }
    $g = if ($GeoName) { " x:Name='$GeoName'" } else { '' }
    "<Path Fill='$Fill'$s $Extra><Path.Data><EllipseGeometry$g Center='$(N $Cx),$(N $Cy)' RadiusX='$(N $Rx)' RadiusY='$(N $Ry)'/></Path.Data>$(Get-TfXaml 'Path' $Tf)</Path>"
}

function Get-GroupXaml([string]$Inner, [object[]]$Tf = $null, [string]$Extra = '') {
    "<Canvas $Extra>$(Get-TfXaml 'Canvas' $Tf)$Inner</Canvas>"
}

# ---------------------------------------------------------------- the sprout (age)
# The sprout says how old this Tok is, not how full the window is: hatchling, kid, adult, elder.
$script:BarkColor = '#FF8A5A3A'; $script:BarkEdge = '#FF5E3B24'; $script:DeepGold = '#FFE39A2E'; $script:Seed = '#FF6B3A1C'
function Get-LeafXaml([double]$X, [double]$Y, [double]$Rot, [double]$Side = 1, [double]$S = 1) {
    Get-PathXaml $script:LeafD $script:Leaf $script:LeafEdge 1.5 @(@('t', $X, $Y), @('s', ($Side * $S), $S), @('r', $Rot))
}
function Get-LeafPairXaml([double]$X, [double]$Y, [double]$Rot = -16, [double]$S = 1) {
    (Get-LeafXaml $X $Y $Rot -1 $S) + (Get-LeafXaml $X $Y $Rot 1 $S)
}
function Get-StemXaml([double]$Top, [double]$Base = 48, [double]$Lean = 1, [double]$W = 3.2) {
    Get-PathXaml "M70,$(N $Base) C70,$(N ($Base - 6)) $(N (70 + $Lean)),$(N ($Top + 6)) $(N (70 + $Lean)),$(N $Top)" 'Transparent' $script:LeafEdge $W
}
# The plain gold flower (the elder's flower peeks through the nightcap as this).
function Get-FlowerXaml([double]$X, [double]$Y, [double]$S = 1, [int]$Count = 8) {
    $p = for ($i = 0; $i -lt $Count; $i++) { Get-PathXaml $script:PetalD $script:Petal $script:PetalEdge 1.2 @(@('r', (360 / $Count * $i + 22.5))) }
    $inner = ($p -join '') + (Get-EllXaml 0 0 6.4 6.4 $script:Heart $script:HeartEdge 1.1) + (Get-EllXaml -1.8 -1.9 1.8 1.8 '#FFFFD3A8')
    Get-GroupXaml $inner @(@('t', $X, $Y), @('s', $S, $S))
}
# The elder's flower: two rings of petals (deep gold behind, gold in front) and seeds in the heart.
function Get-ElderFlowerXaml([double]$X, [double]$Y, [double]$S = 1, [string]$Name = '') {
    $back = for ($i = 0; $i -lt 8; $i++) { Get-PathXaml $script:PetalD $script:DeepGold $script:PetalEdge 1.1 @(@('r', (45 * $i)), @('s', 1.08, 1.08)) }
    $front = for ($i = 0; $i -lt 8; $i++) { Get-PathXaml $script:PetalD $script:Petal $script:PetalEdge 1.2 @(@('r', (45 * $i + 22.5))) }
    $seeds = (0..5 | ForEach-Object { $a = $_ * [math]::PI / 3; Get-EllXaml (2.6 * [math]::Cos($a)) (2.6 * [math]::Sin($a)) 0.9 0.9 $script:Seed }) -join ''
    $inner = ($back -join '') + ($front -join '') + (Get-EllXaml 0 0 6.4 6.4 $script:Heart $script:HeartEdge 1.1) + $seeds + (Get-EllXaml 0 0 0.9 0.9 $script:Seed)
    Get-GroupXaml $inner @(@('t', $X, $Y), @('s', $S, $S)) $(if ($Name) { "x:Name='$Name'" } else { '' })
}
# The elder's stem: green above, bark below, a node ring where they meet.
function Get-ElderStemXaml {
    (Get-StemXaml 16 -W 3.4) + (Get-PathXaml 'M70,48 C70,42 70.3,34 70.5,28' 'Transparent' $script:BarkColor 4.2) +
    (Get-EllXaml 70.5 28 3.2 1.3 $script:BarkColor $script:BarkEdge 0.8)
}

# One sprout. $Age: hatchling, kid, adult, elder. -Fold: leaves folded up (dozing). -Perk: a working seedling, leaning to the food.
function Get-SproutAgeXaml([string]$Age, [switch]$Fold, [switch]$Perk, [string]$FlowerName = '') {
    $lr = if ($Fold) { -50 } else { $null }
    switch ($Age) {
        'hatchling' {
            if ($Perk) { return (Get-PathXaml 'M70,48 C70,44 67,40 64.5,35' 'Transparent' $script:LeafEdge 3.2) + (Get-LeafPairXaml 64.5 35 -42 0.74) }
            return (Get-StemXaml 38) + (Get-LeafPairXaml 70.6 38 ($lr ?? -18) 0.66)
        }
        'kid'   { return (Get-StemXaml 28) + (Get-LeafPairXaml 70.8 28 ($lr ?? -16) 0.92) }
        'adult' { return (Get-StemXaml 13 -W 3.4) + (Get-LeafXaml 70.4 33 $(if ($Fold) { -50 } else { -4 }) -1 1.0) + (Get-LeafPairXaml 71 13 ($lr ?? -16) 1.12) }
        'elder' { return (Get-ElderStemXaml) + (Get-LeafXaml 70.4 36 $(if ($Fold) { -50 } else { -4 }) -1 1.0) + (Get-LeafPairXaml 70.6 24 ($lr ?? -10) 1.0) + (Get-ElderFlowerXaml 71 13 0.82 $FlowerName) }
    }
    throw "no sprout age $Age"
}

# Every sprout, each in its own named canvas (SH, SK, SA, SE; f = folded, p = perk); Update-Look shows one.
function Get-SproutsXaml {
    $out = foreach ($a in @(@('H', 'hatchling'), @('K', 'kid'), @('A', 'adult'), @('E', 'elder'))) {
        # the elder's flower is named so the passing-on can hide it and let go of its petals (lib\Passing.ps1)
        "<Canvas x:Name='S$($a[0])' Visibility='Collapsed'>$(Get-SproutAgeXaml $a[1] -FlowerName $(if ($a[1] -eq 'elder') { 'ElderFlower' } else { '' }))</Canvas>"
        "<Canvas x:Name='S$($a[0])f' Visibility='Collapsed'>$(Get-SproutAgeXaml $a[1] -Fold -FlowerName $(if ($a[1] -eq 'elder') { 'ElderFlowerF' } else { '' }))</Canvas>"
    }
    ($out -join '') + "<Canvas x:Name='SHp' Visibility='Collapsed'>$(Get-SproutAgeXaml 'hatchling' -Perk)</Canvas>"
}

# Which sprout Tok wears, from the days worked together (Get-StageForDays in Pet.ps1). The one place that decides it.
function Get-SproutKey([int]$Days) {
    switch ((Get-StageForDays $Days).Name) { 'kid' { 'K' } 'adult' { 'A' } 'elder' { 'E' } default { 'H' } }     # hatchling, and the egg when asleep
}

# A small portrait of a generation at its final stage, drawn from the same parameters as the live Tok (no stored images):
# the body, the lantern, the face and the age sprout (the elder's spectacles too). 140-grid, cropped by the caller.
function Get-PortraitXaml([string]$Stage) {
    if ($Stage -eq 'egg') {
        return "<Path Data='M70,26 C100,26 112,70 112,92 C112,118 94,132 70,132 C46,132 28,118 28,92 C28,70 40,26 70,26 Z'><Path.Fill><RadialGradientBrush GradientOrigin='0.35,0.3'><GradientStop Color='#FFFFF8EE' Offset='0'/><GradientStop Color='#FFEBD9C2' Offset='1'/></RadialGradientBrush></Path.Fill></Path>" +
               (Get-EllXaml 55 66 7 5 '#55DE7F5E') + (Get-EllXaml 89 90 9 6 '#55DE7F5E') + (Get-EllXaml 57 108 5 4 '#55DE7F5E')
    }
    $L = $script:Lantern
    $age = if ($Stage -in 'kid', 'adult', 'elder') { $Stage } else { 'hatchling' }
    $honey = Get-HoneyGeometry 0.5
    $eye = { param($ex) (Get-EllXaml $ex 80 8.6 10.4 'White') + (Get-EllXaml $ex 80 5.0 6.1 $script:Ink) }
    $x = (Get-SproutAgeXaml $age) + (Get-EllXaml 55 126.5 11 5.2 '#FFB0563A' $script:Rim 1) + (Get-EllXaml 85 126.5 11 5.2 '#FFB0563A' $script:Rim 1) +
        "<Path Fill='#FFC9664A' Stroke='$script:Rim' StrokeThickness='1.1'><Path.Data><EllipseGeometry Center='31,98' RadiusX='7.5' RadiusY='11.5'/></Path.Data><Path.RenderTransform><RotateTransform Angle='22' CenterX='31' CenterY='98'/></Path.RenderTransform></Path>" +
        "<Path Fill='#FFC9664A' Stroke='$script:Rim' StrokeThickness='1.1'><Path.Data><EllipseGeometry Center='109,98' RadiusX='7.5' RadiusY='11.5'/></Path.Data><Path.RenderTransform><RotateTransform Angle='-22' CenterX='109' CenterY='98'/></Path.RenderTransform></Path>" +
        "<Path Stroke='#BFA24E36' StrokeThickness='1.3'><Path.Data><EllipseGeometry Center='70,86' RadiusX='42' RadiusY='42'/></Path.Data><Path.Fill><RadialGradientBrush GradientOrigin='0.38,0.3' Center='0.45,0.4' RadiusX='0.65' RadiusY='0.65'><GradientStop Color='#FFF4AE8C' Offset='0'/><GradientStop Color='#FFDE7F5E' Offset='0.55'/><GradientStop Color='#FFB65A3D' Offset='1'/></RadialGradientBrush></Path.Fill></Path>" +
        (Get-EllXaml $L.X $L.Y $L.Rx $L.Ry '#FFE9A88C') +
        "<Path Data='$($honey.Data)'><Path.Fill><LinearGradientBrush StartPoint='0,0' EndPoint='0,1'><GradientStop Color='#FFFFEDA6' Offset='0'/><GradientStop Color='#FFFFCB55' Offset='0.35'/><GradientStop Color='#FFEE8E2C' Offset='1'/></LinearGradientBrush></Path.Fill></Path>" +
        (Get-EllXaml $L.X $L.Y $L.Rx $L.Ry 'Transparent' '#FFC7664A' 1.4) +
        (Get-EllXaml 42 94 6.5 3.6 '#FFFF5F7E' '' 0 $null "Opacity='0.4'") + (Get-EllXaml 98 94 6.5 3.6 '#FFFF5F7E' '' 0 $null "Opacity='0.4'") +
        (& $eye 55) + (& $eye 85)
    if ($Stage -eq 'elder') { $x += ((Get-SpecsXaml) -replace "\s*x:Name='[^']*'", '' -replace "\s*Visibility='Collapsed'", '') }
    $x + "<Path Stroke='$script:MouthInk' StrokeThickness='2.6' StrokeStartLineCap='Round' StrokeEndLineCap='Round' Data='$(Get-SmileData 7 5 95)'/>"
}

# ---------------------------------------------------------------- the lantern (the belly is the 5-hour window)
# An oval glass window low on the belly. Honey fills it from the bottom by AREA, so half the window looks like half
# the glass; it is lit from its own surface and the light stays inside the glass. At the limit the honey is banked.
$script:Lantern = @{ X = 70.0; Y = 112.0; Rx = 22.0; Ry = 10.5 }
$script:LanternMin = 0.04

# The height of the honey's surface for a level 0..1 (the share of the window's area that is full).
function Get-LevelY([double]$Level) {
    $L = $script:Lantern
    $Level = [math]::Max($script:LanternMin, [math]::Min($Level, 1.0))
    $lo = 0.0; $hi = 1.0
    for ($i = 0; $i -lt 40; $i++) {
        $h = ($lo + $hi) / 2; $t = 1 - 2 * $h
        $a = ([math]::Acos($t) - $t * [math]::Sqrt(1 - $t * $t)) / [math]::PI
        if ($a -lt $Level) { $lo = $h } else { $hi = $h }
    }
    $L.Y + $L.Ry - 2 * $L.Ry * ($lo + $hi) / 2
}

# The honey's shape: @{ Data (path), Meniscus (path or ''), Y, Width, Full }.
function Get-HoneyGeometry([double]$Level) {
    $L = $script:Lantern
    $Level = [math]::Max($script:LanternMin, [math]::Min($Level, 1.0))
    if ($Level -ge 0.995) {
        $d = "M$(N ($L.X - $L.Rx)),$(N $L.Y) A$(N $L.Rx),$(N $L.Ry) 0 1 1 $(N ($L.X + $L.Rx)),$(N $L.Y) A$(N $L.Rx),$(N $L.Ry) 0 1 1 $(N ($L.X - $L.Rx)),$(N $L.Y) Z"
        return @{ Data = $d; Meniscus = ''; Y = $L.Y - $L.Ry; Width = 0.0; Full = $true }
    }
    $y = Get-LevelY $Level
    $t = ($y - $L.Y) / $L.Ry
    $w = $L.Rx * [math]::Sqrt([math]::Max(0.0, 1 - $t * $t))
    $large = if ($y -lt $L.Y) { 1 } else { 0 }
    $dip = [math]::Min(2.4, $w * 0.12)
    $d = "M$(N ($L.X - $w)),$(N $y) Q$(N $L.X),$(N ($y + $dip)) $(N ($L.X + $w)),$(N $y) A$(N $L.Rx),$(N $L.Ry) 0 $large 1 $(N ($L.X - $w)),$(N $y) Z"
    $m = "M$(N ($L.X - $w + 1.5)),$(N $y) Q$(N $L.X),$(N ($y + 2)) $(N ($L.X + $w - 1.5)),$(N $y)"
    @{ Data = $d; Meniscus = $m; Y = $y; Width = $w; Full = $false }
}

# The body and the glass window, then the honey, then the glass's rim. The body and rim never change, so they are bitmap-cached.
function Get-LanternXaml {
    $L = $script:Lantern
    $lit = "<LinearGradientBrush StartPoint='0,0' EndPoint='0,1'><GradientStop Color='#FFFFEDA6' Offset='0'/><GradientStop Color='#FFFFCB55' Offset='0.35'/><GradientStop Color='#FFEE8E2C' Offset='1'/></LinearGradientBrush>"
    $bank = "<LinearGradientBrush StartPoint='0,0' EndPoint='0,1'><GradientStop Color='#FFE9B373' Offset='0'/><GradientStop Color='#FFC77A3E' Offset='1'/></LinearGradientBrush>"
    $e = Get-HoneyGeometry 0.05
    $hl = "M$(N ($L.X - 16)),$(N ($L.Y - 4)) Q$(N ($L.X - 12)),$(N ($L.Y - 9)) $(N ($L.X - 5)),$(N ($L.Y - 10))"
    @"
<Canvas CacheMode='BitmapCache'><Path x:Name='BodyShape' Stroke='#BFA24E36' StrokeThickness='1.3'>
  <Path.Data><EllipseGeometry x:Name='BodyGeo' Center='70,86' RadiusX='42' RadiusY='42'/></Path.Data>
  <Path.Fill><RadialGradientBrush GradientOrigin='0.38,0.3' Center='0.45,0.4' RadiusX='0.65' RadiusY='0.65'>
    <GradientStop x:Name='BodyLight' Color='#FFF4AE8C' Offset='0'/><GradientStop x:Name='BodyMid' Color='#FFDE7F5E' Offset='0.55'/><GradientStop x:Name='BodyEdge' Color='#FFB65A3D' Offset='1'/>
  </RadialGradientBrush></Path.Fill>
</Path>
$(Get-EllXaml $L.X $L.Y $L.Rx $L.Ry '#FFE9A88C')</Canvas>
$(Get-EllXaml $L.X $L.Y $L.Rx $L.Ry '#FFFFD9A0' '' 0 $null "x:Name='Warmth' Opacity='0.2'")
<Path x:Name='HoneyLit' Data='$($e.Data)'><Path.Fill>$lit</Path.Fill></Path>
<Path x:Name='HoneyBank' Data='$($e.Data)' Visibility='Collapsed'><Path.Fill>$bank</Path.Fill></Path>
<Path x:Name='Meniscus' Data='$($e.Meniscus)' Stroke='#FFFFF4C8' StrokeThickness='1.5' StrokeStartLineCap='Round' StrokeEndLineCap='Round' Opacity='0.95'/>
<Canvas CacheMode='BitmapCache'>$(Get-EllXaml $L.X $L.Y $L.Rx $L.Ry 'Transparent' '#FFC7664A' 1.2)
$(Get-PathXaml $hl 'Transparent' '#80FFFFFF' 1.8)</Canvas>
"@
}

# ---------------------------------------------------------------- the nightcap (the limit happens to Tok)
# The blue cap. The adult's top leaf pair and the elder's flower poke through a slit; the reset pill is in Get-PropsXaml.
function Get-NightcapXaml {
    $cap = (Get-PathXaml 'M44,60 C48,40 54,22 66,14 C78,8 96,10 108,22 C112,27 114,32 114,36 C106,30 96,26 88,28 C90,40 94,50 96,60 Q70,50 44,60 Z' '#FF6E8FD8' '#FF3F5A99' 1.4) +
           (Get-PathXaml 'M58,30 l1.3,2.6 2.8,0.4 -2,1.9 0.5,2.8 -2.6,-1.4 -2.5,1.4 0.5,-2.8 -2,-1.9 2.8,-0.4 Z' '#FFFFE07A') +
           (Get-PathXaml 'M76,42 l1,2 2.1,0.3 -1.5,1.4 0.4,2.1 -2,-1 -1.9,1 0.4,-2.1 -1.5,-1.4 2.1,-0.3 Z' '#FFFFE07A' '' 0 $null "Opacity='0.8'") +
           (Get-PathXaml 'M44,60 Q70,50 96,60' 'Transparent' '#FFFFF6E6' 6) + (Get-EllXaml 114 37 5 5 '#FFFFF6E6' '#FF3F5A99' 1.1)
    $slit = (Get-PathXaml 'M64,24 Q70,21 77,23' 'Transparent' '#FF2C3F73' 3.4) + (Get-PathXaml 'M64,24 Q70,21 77,23' 'Transparent' '#FFFFF6E6' 0.9 @(, @('t', 0, 2.2)) "Opacity='0.5'")
    @"
<Canvas x:Name='Cap' Visibility='Collapsed'>$(Get-GroupXaml $cap @(@('t', 140, 0), @('s', -1, 1)))<Canvas x:Name='CapSlit'>$slit</Canvas></Canvas>
<Canvas x:Name='PeekLeaf' Visibility='Collapsed'><Canvas.RenderTransform><RotateTransform x:Name='PeekLeafRot' CenterX='70.5' CenterY='23'/></Canvas.RenderTransform>$(Get-LeafPairXaml 70.5 23 -48 0.72)</Canvas>
<Canvas x:Name='PeekFlower' Visibility='Collapsed'><Canvas.RenderTransform><RotateTransform x:Name='PeekFlowerRot' CenterX='70.5' CenterY='23'/></Canvas.RenderTransform>$(Get-PathXaml 'M70.5,23 C70.5,19 71,13 71.5,10' 'Transparent' $script:LeafEdge 2.6)$(Get-FlowerXaml 71.5 10 0.58)</Canvas>
"@
}

# The elder's thin gold spectacles. They slip when the eyes close, and never show with the sunglasses.
$script:Wire = '#FF9A6418'
function Get-SpecsXaml {
    $g = ''
    foreach ($cx in 55, 85) {
        $g += (Get-EllXaml $cx 80 11.6 12.2 '#24FFFFFF' $script:Wire 2.1) +
              (Get-PathXaml "M$(N ($cx - 7.5)),74 Q$(N ($cx - 5)),70.8 $(N ($cx - 1)),70.2" 'Transparent' '#B3FFFFFF' 1.5)
    }
    $g += (Get-PathXaml 'M66.4,78 Q70,75 73.6,78' 'Transparent' $script:Wire 2.1) + (Get-PathXaml 'M43.5,77 L32,75' 'Transparent' $script:Wire 1.8) + (Get-PathXaml 'M96.5,77 L108,75' 'Transparent' $script:Wire 1.8)
    "<Canvas x:Name='Specs' Visibility='Collapsed'><Canvas.RenderTransform><TransformGroup><TranslateTransform x:Name='SpecsT'/><RotateTransform x:Name='SpecsRot' CenterX='70' CenterY='80'/></TransformGroup></Canvas.RenderTransform>$g</Canvas>"
}

# ---------------------------------------------------------------- face parts
function Get-ClosedEyesData([double]$Cy) { (55, 85 | ForEach-Object { "M$(N ($_ - 7.5)),$(N $Cy) Q$(N $_),$(N ($Cy + 6.5)) $(N ($_ + 7.5)),$(N $Cy)" }) -join ' ' }
$script:HappyEyesData = 'M47.5,84 Q55,76 62.5,84 M77.5,84 Q85,76 92.5,84'
$script:SqueezeEyesData = 'M49,74 L59,80 L49,86 M91,74 L81,80 L91,86'
function Get-SmileData([double]$W = 6, [double]$D = 4, [double]$Cy = 98) { "M$(N (70 - $W)),$(N $Cy) Q70,$(N ($Cy + $D)) $(N (70 + $W)),$(N $Cy)" }

# The whole creature (inside the Pet canvas). Order is back to front.
function Get-CreatureXaml {
    $arm = {
        param($n, $cx, $cy, $rot)
        "<Path x:Name='$n' Fill='#FFC9664A' Stroke='$script:Rim' StrokeThickness='1.1'><Path.Data><EllipseGeometry x:Name='${n}Geo' Center='$cx,$cy' RadiusX='7.5' RadiusY='11.5'/></Path.Data>" +
        "<Path.RenderTransform><RotateTransform x:Name='${n}Rot' Angle='$rot' CenterX='$cx' CenterY='$cy'/></Path.RenderTransform></Path>"
    }
    $eye = {
        param($side, $ex)
        "<Canvas x:Name='Eye$side'><Canvas.RenderTransform><ScaleTransform x:Name='Eye${side}Blink' CenterX='$ex' CenterY='80'/></Canvas.RenderTransform>" +
        (Get-EllXaml $ex 80 8.6 10.4 'White' '' 0 $null '' "Eye${side}White") +
        "<Canvas><Canvas.RenderTransform><TranslateTransform x:Name='Pupil$side'/></Canvas.RenderTransform>$(Get-EllXaml $ex 80 5.0 6.1 $script:Ink '' 0 $null '' "Pupil${side}Geo")</Canvas></Canvas>"
    }
    $cheek = {
        param($n, $cx)
        "<Path x:Name='$n' Fill='#FFFF5F7E' Opacity='0.3'><Path.Data><EllipseGeometry x:Name='${n}Geo' Center='$cx,94' RadiusX='6.5' RadiusY='3.6'/></Path.Data>" +
        "<Path.RenderTransform><ScaleTransform x:Name='${n}Puff' CenterX='$cx' CenterY='94'/></Path.RenderTransform></Path>"
    }
    $freckles = "<Canvas x:Name='Freckles' Visibility='Collapsed'><Canvas.RenderTransform><TranslateTransform x:Name='FreckleT'/></Canvas.RenderTransform>" +
        ((@(@(37, 91), @(42, 89.5), @(46, 92), @(94, 92), @(98, 89.5), @(103, 91)) | ForEach-Object { Get-EllXaml $_[0] $_[1] 1.25 1.25 '#FFB9573C' '' 0 $null "Opacity='0.8'" }) -join '') + "</Canvas>"
    $mouthTongue = "<Path x:Name='OMouth' Fill='#FF6E2A20' Stroke='$script:MouthInk' StrokeThickness='1.4' Visibility='Collapsed'><Path.Data><EllipseGeometry x:Name='OMouthGeo' Center='71,96' RadiusX='4.6' RadiusY='4.4'/></Path.Data></Path>" +
                   "<Path x:Name='OTongue' Fill='#FFD9636E' Visibility='Collapsed'><Path.Data><EllipseGeometry x:Name='OTongueGeo' Center='71,98' RadiusX='2.5' RadiusY='1.5'/></Path.Data></Path>"
    $shades = "<Canvas x:Name='Shades' Visibility='Collapsed'>" +
        (Get-PathXaml 'M42,75 h26 v6 q0,10 -13,10 q-13,0 -13,-10 Z' '#FF17110F') + (Get-PathXaml 'M72,75 h26 v6 q0,10 -13,10 q-13,0 -13,-10 Z' '#FF17110F') +
        (Get-PathXaml 'M36,76 H104' 'Transparent' '#FF17110F' 3.2) + (Get-PathXaml 'M46,79 l7,0 M76,79 l7,0' 'Transparent' '#66FFFFFF' 1.6) + "</Canvas>"
    @"
<Canvas x:Name='Sprout'><Canvas.RenderTransform><TransformGroup><ScaleTransform x:Name='SproutScale' CenterX='70' CenterY='48'/><RotateTransform x:Name='SproutRot' CenterX='70' CenterY='50'/></TransformGroup></Canvas.RenderTransform>$(Get-SproutsXaml)</Canvas>
$(Get-EllXaml 55 126.5 11 5.2 '#FFB0563A' $script:Rim 1 $null "x:Name='FootL'")
$(Get-EllXaml 85 126.5 11 5.2 '#FFB0563A' $script:Rim 1 $null "x:Name='FootR'")
$(& $arm 'ArmL' 31 98 22)
$(& $arm 'ArmR' 109 98 -22)
$(Get-LanternXaml)
$(& $cheek 'CheekL' 42)
$(& $cheek 'CheekR' 98)
$freckles
$(& $eye 'L' 55)
$(& $eye 'R' 85)
<Path x:Name='ClosedEyes' Stroke='$script:Ink' StrokeThickness='2.6' StrokeStartLineCap='Round' StrokeEndLineCap='Round' Visibility='Collapsed' Data='$(Get-ClosedEyesData 84)'/>
<Path x:Name='HappyEyes' Stroke='$script:Ink' StrokeThickness='2.8' StrokeStartLineCap='Round' StrokeEndLineCap='Round' Visibility='Collapsed' Data='$script:HappyEyesData'/>
<Path x:Name='SqueezeEyes' Stroke='$script:Ink' StrokeThickness='2.8' StrokeStartLineCap='Round' StrokeEndLineCap='Round' StrokeLineJoin='Round' Visibility='Collapsed' Data='$script:SqueezeEyesData'/>
$(Get-SpecsXaml)
$shades
<Path x:Name='Mouth' Stroke='$script:MouthInk' StrokeThickness='2.4' StrokeStartLineCap='Round' StrokeEndLineCap='Round' StrokeLineJoin='Round' Data='$(Get-SmileData)'/>
$mouthTongue
<Canvas x:Name='HiMouth' Visibility='Collapsed'>$(Get-PathXaml 'M63,92 Q70,104 77,92 Z' '#FF7A2E22' $script:MouthInk 1.6)$(Get-EllXaml 70 98 3 1.6 '#FFD9636E')</Canvas>
$(Get-NightcapXaml)
"@
}

# Pet-level extras, drawn outside the creature so its lean and squish don't move them.
function Get-PropsXaml {
    $drops = (1..4 | ForEach-Object { "<Path x:Name='MealDrop$_' Fill='#FFF5A623' Stroke='#FFC4831C' StrokeThickness='0.6' Visibility='Collapsed'><Path.Data><EllipseGeometry RadiusX='1.9' RadiusY='2.5'/></Path.Data></Path>" }) -join ''
    @"
<Canvas x:Name='Meal' IsHitTestVisible='False'>
  <Canvas x:Name='MealTok' Visibility='Collapsed'><Canvas.RenderTransform><TransformGroup><ScaleTransform x:Name='MealTokS'/><RotateTransform x:Name='MealTokR'/><TranslateTransform x:Name='MealTokT'/></TransformGroup></Canvas.RenderTransform>
    <Path x:Name='MealWhole' Fill='#FFFFF3DC' Stroke='#FFB86A2A' StrokeThickness='1.1' Data='M-3.5,-5 H3.5 A1.5,1.5 0 0 1 5,-3.5 V3.5 A1.5,1.5 0 0 1 3.5,5 H-3.5 A1.5,1.5 0 0 1 -5,3.5 V-3.5 A1.5,1.5 0 0 1 -3.5,-5 Z'/>
    <Path x:Name='MealBitten' Fill='#FFFFF3DC' Stroke='#FFB86A2A' StrokeThickness='1.1' StrokeLineJoin='Round' Visibility='Collapsed' Data='M-5,-5 H1.2 A3.8,3.8 0 0 0 5,-1.2 V5 H-5 Z'/>
  </Canvas>
  <Path x:Name='MealRip1' Stroke='#FFFFF4C8' StrokeThickness='1.1' Visibility='Collapsed'><Path.Data><EllipseGeometry x:Name='MealRip1Geo'/></Path.Data></Path>
  <Path x:Name='MealRip2' Stroke='#FFFFF4C8' StrokeThickness='0.9' Visibility='Collapsed'><Path.Data><EllipseGeometry x:Name='MealRip2Geo'/></Path.Data></Path>
  $drops
</Canvas>
<!-- the working spinner: Claude orange with a thin dark edge so it holds on light backgrounds, and a faint drop for a
     little depth. No rim: it should stay a quiet thing at the edge of the eye. tok.ps1 animates SparkFace's glyph; the others follow it. -->
<Canvas x:Name='Spark' Canvas.Left='9' Canvas.Top='33' Width='24' Height='24' Visibility='Collapsed'>
  <Path x:Name='SparkDrop' Fill='#552E140C' Stroke='#552E140C' StrokeThickness='2.2' StrokeLineJoin='Round' Data='{Binding Data, ElementName=SparkFace}'><Path.RenderTransform><TranslateTransform X='0.5' Y='1.1'/></Path.RenderTransform></Path>
  <Path x:Name='SparkLine' Fill='#CC6A2C1A' Stroke='#CC6A2C1A' StrokeThickness='2.2' StrokeLineJoin='Round' Data='{Binding Data, ElementName=SparkFace}'/>
  <Path x:Name='SparkFace' Fill='#FFD97757' Stroke='#FFD97757' StrokeThickness='0.6' StrokeLineJoin='Round'/>
</Canvas>
<Canvas x:Name='Waves' Visibility='Collapsed'>$(Get-PathXaml 'M126,40 q5,6 2,14' 'Transparent' '#FFF0A532' 2.8)$(Get-PathXaml 'M132,33 q8,10 3,24' 'Transparent' '#FFF0A532' 2.8)</Canvas>
<Border x:Name='WakePill' Canvas.Left='100' Canvas.Top='16' MinWidth='34' Height='20' CornerRadius='10' Background='#FFFFF6E6' BorderBrush='#FF9C4630' BorderThickness='1.2' Padding='5,0' Visibility='Collapsed'>
  <TextBlock x:Name='WakeText' HorizontalAlignment='Center' VerticalAlignment='Center' FontFamily='Segoe UI' FontSize='12' FontWeight='SemiBold' Foreground='#FF3A2018'/>
</Border>
"@
}

# ---------------------------------------------------------------- poses
# Each look is a pose: which eyes, which mouth, where the arms are, and a few extras.
# Fullness never changes the face: the sprout is the meter. No lids, no frowns, nothing that looks hurt.
$script:BodyNormal = @(70, 86, 42, 42); $script:BodyLimit = @(70, 90.5, 44.5, 37.5)
$script:ChewPath = 'M63,96 q2.3,-2.5 4.6,0 q2.3,2.5 4.6,0 q2.3,-2.5 4.6,0'     # the chewing mouth
$script:GulpPath = 'M66,96 Q70,94 74,96'
$script:ArmPoses = @{
    down    = @(@(31, 98, 22), @(109, 98, -22))
    pat     = @(@(31, 98, 22), @(103, 104, 38))     # the right hand on the belly, in front
    wave    = @(@(31, 98, 22), @(116, 62, 32))
    flop    = @(@(28, 112, 50), @(112, 112, -50))
    stretch = @(@(22, 84, -72), @(118, 84, 72))
    hold    = @(@(54, 106, 55), @(86, 106, -55))     # both hands at the belly, holding a token
}

function Get-Pose([string]$Face) {
    $p = @{ Eyes = 'open'; Mouth = 'smile'; Smile = @(6, 4, 95); O = $null; Path = ''; Arms = 'down'; Body = 'normal'; Lean = 0
            Cheek = 0.3; CheekCy = 94; Fold = $false; Perk = $false; Lift = 0; Spark = $false; Waves = $false; Fx = ''; FxColor = '#FF6B7FD7'; ClosedCy = 84 }
    switch ($Face) {
        # working: leaning into the work with a small, calm mouth, and Claude Code's own spinner turning beside the head (WHO.md row 2:
        # thinking, not eating; the 3-second meal is the only eating)
        { $_ -in 'busy', 'zoom', 'fan' } { $p.Mouth = 'path'; $p.Path = 'M66.5,96 Q70,98.4 73.5,96'; $p.Lean = -6; $p.Perk = $true; $p.Spark = $true }
        # fan-out: several tool calls sent at once, both arms up for half a second (parallel calls are an agent's breath)
        'fan'     { $p.Arms = 'stretch' }
        # a skill loaded: hands at the belly as if holding a card, and a small ≡ overhead (instructions it didn't have a moment ago)
        'skill'   { $p.Mouth = 'path'; $p.Path = 'M66.5,96 Q70,98.4 73.5,96'; $p.Arms = 'hold'; $p.Fx = '≡'; $p.FxColor = '#FFD97757' }
        # nearly full: eyes open and a plain smile, the hand stays on the lantern. Not love's squeezed-eye grin: that would be happiest at the warning.
        'stuffed' { $p.Arms = 'pat' }
        { $_ -in 'love', 'content' } { $p.Eyes = 'happy'; $p.Smile = @(7, 5, 95); $p.Arms = 'pat'; $p.Cheek = 0.42 }
        'sleep'   { $p.Eyes = 'closed'; $p.ClosedCy = 83; $p.Mouth = 'path'; $p.Path = 'M66,96 Q70,98 74,96'; $p.Fold = $true; $p.Cheek = 0.36 }
        'coma'    { $p.Eyes = 'closed'; $p.ClosedCy = 87; $p.Mouth = 'path'; $p.Path = 'M66,99 Q70,102 74,99'; $p.Arms = 'flop'; $p.Body = 'limit'; $p.Cheek = 0.4; $p.CheekCy = 100 }
        'needs'   { $p.Mouth = 'hi'; $p.Arms = 'wave'; $p.Cheek = 0.42; $p.Lift = -4; $p.Waves = $true }
        'hungry'  { $p.Mouth = 'o'; $p.O = @(70, 96, 3, 3); $p.Fx = '…'; $p.FxColor = '#FF8A6A50' }
        # no longer shown live (errors are weather, see tok.ps1); the demos still use the pose. No red, no mark.
        'ouch'    { $p.Eyes = 'squeeze'; $p.Mouth = 'path'; $p.Path = 'M65,97 L75,97' }
        # Claude just said it was wrong: a small 'oh', and a turn-around arrow in Claude's colour
        'rethink' { $p.Mouth = 'o'; $p.O = @(70, 96, 2.6, 2.6); $p.Fx = '↺'; $p.FxColor = '#FFD97757'; $p.Lean = 4 }
        'dizzy'   { $p.Mouth = 'o'; $p.O = @(70, 96, 3.4, 3.4); $p.Fx = '✶'; $p.FxColor = '#FF9A6BD7' }
        # eating a mouthful (Step-Meal): the token arrives, a chew, the swallow, the grin
        'eat1'    { $p.Mouth = 'o'; $p.O = @(71, 96, 4.6, 4.4); $p.Arms = 'hold' }
        'eat2'    { $p.Eyes = 'happy'; $p.Mouth = 'path'; $p.Path = $script:ChewPath; $p.Arms = 'hold'; $p.Cheek = 0.42 }
        'eat3'    { $p.Eyes = 'happy'; $p.Mouth = 'path'; $p.Path = $script:GulpPath; $p.Cheek = 0.42 }
        'eat4'    { $p.Eyes = 'happy'; $p.Smile = @(7, 5, 95); $p.Cheek = 0.42 }
        # a minion coming home (Step-Minions): Tok watches with a grin, then pats its belly
        'home1'   { $p.Smile = @(7, 5, 95) }
        'home2'   { $p.Eyes = 'happy'; $p.Smile = @(7, 5, 95); $p.Cheek = 0.42 }
        'home3'   { $p.Smile = @(7, 5, 95); $p.Arms = 'pat'; $p.Cheek = 0.42 }
        'stretch' { $p.Eyes = 'happy'; $p.Mouth = 'o'; $p.O = @(70, 97, 4.2, 6); $p.Arms = 'stretch'; $p.Cheek = 0.36 }
    }
    if ($Face -in 'love', 'content') { $p.Fx = '♥'; $p.FxColor = '#FFE0446A' }
    if ($Face -eq 'zoom') { $p.Fx = '↯'; $p.FxColor = '#FFE0A020' }
    $p
}
