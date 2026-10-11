# tok.ps1 - Tok, a small desktop creature that is Claude, and eats your token budget.
# Run with: pwsh -STA -NoProfile -WindowStyle Hidden -File tok.ps1
# It only reads Claude Code transcripts; it changes nothing outside %LOCALAPPDATA%\tok.
param(
    [switch]$Demo,                 # cycle through every look (for screenshots)
    [string]$Mood,                 # force a mood (happy, busy, full, stuffed, sleep, hungry, love, ouch, coma, egg)
    [string]$Stage,                # force a stage (egg, hatchling, kid, adult, elder)
    [double]$X = -1, [double]$Y = -1,  # fixed position in DIPs; disables window following
    [string]$RenderDir,            # draw every look to transparent PNGs in this folder, then exit
    [switch]$MinionDemo,           # a scripted loop of four subagents (one per model) hatching and going home
    [switch]$Showcase,             # a scripted tour of everything Tok does now (about two and a half minutes)
    [switch]$Molt,                 # play the passing-on and the hatch on a loop (-Stage elder or kid picks the kind); never touches the real state
    [string]$RecordDir,            # save 10 fps PNG frames of the window here...
    [double]$RecordSeconds = 20,   # ...for this long
    [double]$Bench = 0             # play only: hold one look still (-Mood, -Stage) for this many seconds, log the CPU it cost, then exit
)

$ErrorActionPreference = 'Stop'
$script:ForcedMood = $Mood     # captured now: $script:Mood is reused below for the live mood
$script:ForcedStage = $Stage
$PlayOnly = $Demo -or $MinionDemo -or $Showcase -or $Molt -or $Bench -gt 0     # a window that never scans, polls or saves
. (Join-Path $PSScriptRoot 'lib\Transcripts.ps1')
. (Join-Path $PSScriptRoot 'lib\Pet.ps1')
. (Join-Path $PSScriptRoot 'lib\Dreams.ps1')
. (Join-Path $PSScriptRoot 'lib\Minions.ps1')
. (Join-Path $PSScriptRoot 'lib\Lineage.ps1')
. (Join-Path $PSScriptRoot 'lib\Privacy.ps1')
. (Join-Path $PSScriptRoot 'lib\Art.ps1')
. (Join-Path $PSScriptRoot 'lib\Passing.ps1')
. (Join-Path $PSScriptRoot 'lib\Chime.ps1')
. (Join-Path $PSScriptRoot 'lib\Menu.ps1')
Move-OldTokHome
$null = New-Item -ItemType Directory -Force $DataDir
$script:LogPath = Join-Path $DataDir 'tok.log'
function Write-BodyLog([string]$Text) {
    try { Add-Content -LiteralPath $script:LogPath -Value "$(Get-Date -Format 'MM-dd HH:mm:ss') $Text" } catch { }
}

$mutex = [System.Threading.Mutex]::new($false, (Get-TokMutexName))
if (-not $PlayOnly -and -not $Mood -and -not $RenderDir -and -not $mutex.WaitOne(0)) { Write-BodyLog 'already running; exiting'; return }

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms
Add-Type -Namespace Tok -Name Native -MemberDefinition @'
[StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
[DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
[DllImport("user32.dll")] public static extern bool IsZoomed(IntPtr h);
[DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr h, System.Text.StringBuilder s, int n);
[DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int i);
[DllImport("user32.dll")] public static extern int SetWindowLong(IntPtr h, int i, int v);
[DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr h, int a, out RECT r, int size);
[DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
[StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] public struct MONITORINFOEX { public int cbSize; public RECT rcMonitor; public RECT rcWork; public uint dwFlags; [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string szDevice; }
[StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] public struct DEVMODE {
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
    public short dmSpecVersion, dmDriverVersion, dmSize, dmDriverExtra; public int dmFields, dmPositionX, dmPositionY, dmDisplayOrientation, dmDisplayFixedOutput;
    public short dmColor, dmDuplex, dmYResolution, dmTTOption, dmCollate; [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
    public short dmLogPixels; public int dmBitsPerPel, dmPelsWidth, dmPelsHeight, dmDisplayFlags, dmDisplayFrequency;
    public int dmICMMethod, dmICMIntent, dmMediaType, dmDitherType, dmReserved1, dmReserved2, dmPanningWidth, dmPanningHeight; }
[DllImport("user32.dll")] public static extern IntPtr MonitorFromWindow(IntPtr h, uint flags);
[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern bool GetMonitorInfo(IntPtr m, ref MONITORINFOEX mi);
[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern bool EnumDisplaySettings(string dev, int mode, ref DEVMODE dm);
// The app's visible frame (DWM: physical pixels), its monitor's rect and work area (this process's coordinates), and the
// monitor's physical position and size, so Get-PerchTarget can map the frame over (ConvertTo-LogicalRect). pw = 0: no mapping.
public static bool PerchInfo(IntPtr h, out RECT frame, out RECT mon, out RECT work, out int px, out int py, out int pw, out int ph) {
    mon = new RECT(); work = new RECT(); px = 0; py = 0; pw = 0; ph = 0;
    if (DwmGetWindowAttribute(h, 9, out frame, 16) != 0) return false;
    MONITORINFOEX mi = new MONITORINFOEX(); mi.cbSize = Marshal.SizeOf(typeof(MONITORINFOEX));
    if (!GetMonitorInfo(MonitorFromWindow(h, 2), ref mi)) return false;
    mon = mi.rcMonitor; work = mi.rcWork;
    DEVMODE dm = new DEVMODE(); dm.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE));
    if (EnumDisplaySettings(mi.szDevice, -1, ref dm)) { px = dm.dmPositionX; py = dm.dmPositionY; pw = dm.dmPelsWidth; ph = dm.dmPelsHeight; }
    return true;
}
'@

# ---------------------------------------------------------------- the look
$xamlText = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        Topmost="True" ShowInTaskbar="False" ResizeMode="NoResize"
        Width="320" Height="310" Title="Tok">
  <Canvas x:Name="Root" Width="320" Height="310">
    <!-- speech bubble: grows upward from just above Tok's head, its right edge just past Tok's, so it stays on screen in the corner -->
    <StackPanel x:Name="Bubble" Canvas.Left="8" Canvas.Bottom="154" Width="272" Visibility="Collapsed">
      <StackPanel.Effect><DropShadowEffect BlurRadius="10" ShadowDepth="2" Direction="270" Opacity="0.35"/></StackPanel.Effect>
      <Border HorizontalAlignment="Right" MaxWidth="264" Background="#FFFFFBF5" BorderBrush="#FF8A3E28" BorderThickness="2" CornerRadius="14" Padding="12,7">
        <StackPanel>
          <TextBlock x:Name="BubbleText" TextWrapping="Wrap" TextAlignment="Center" Foreground="#FF1E1612"
                     FontFamily="Segoe UI, Segoe UI Emoji, Segoe UI Symbol" FontSize="16" FontWeight="SemiBold"/>
          <StackPanel x:Name="BubbleRows" Visibility="Collapsed"/>
        </StackPanel>
      </Border>
      <Path HorizontalAlignment="Right" Margin="0,-2,52,0" Fill="#FFFFFBF5" Stroke="#FF8A3E28" StrokeThickness="2"
            Data="M0,0 L8,10 L16,0"/>
    </StackPanel>

    <Canvas x:Name="Pet" Width="140" Height="140" Canvas.Left="150" Canvas.Top="164" RenderTransformOrigin="0.5,1">
      <Canvas.RenderTransform>
        <TransformGroup>
          <ScaleTransform x:Name="PetScale" ScaleX="1" ScaleY="1"/>
          <TranslateTransform x:Name="PetBob"/>
        </TransformGroup>
      </Canvas.RenderTransform>

      <Ellipse x:Name="Shadow" Canvas.Left="32" Canvas.Top="127" Width="76" Height="8" Fill="#33000000"/>
      <Canvas x:Name="MinionsBack" Opacity="0.92"/>

      <!-- the creature: lib\Art.ps1 draws it (the lantern, the age sprout, the nightcap); Update-Look poses it -->
      <Canvas x:Name="Creature" Width="140" Height="140" RenderTransformOrigin="0.5,1">
        <Canvas.RenderTransform><TransformGroup><ScaleTransform x:Name="Squish"/><RotateTransform x:Name="Lean" CenterX="70" CenterY="128"/><TranslateTransform x:Name="HopT"/><TranslateTransform x:Name="Lift"/></TransformGroup></Canvas.RenderTransform>
@@CREATURE@@
      </Canvas>

      <!-- egg -->
      <Canvas x:Name="Egg" Visibility="Collapsed">
        <Canvas.RenderTransform><RotateTransform CenterX="70" CenterY="131"/></Canvas.RenderTransform>
        <Path Data="M70,26 C100,26 112,70 112,92 C112,118 94,132 70,132 C46,132 28,118 28,92 C28,70 40,26 70,26 Z">
          <Path.Fill>
            <RadialGradientBrush GradientOrigin="0.35,0.3"><GradientStop Color="#FFFFF8EE" Offset="0"/><GradientStop Color="#FFEBD9C2" Offset="1"/></RadialGradientBrush>
          </Path.Fill>
        </Path>
        <Ellipse x:Name="EggSpot1" Canvas.Left="48" Canvas.Top="58" Width="14" Height="10" Fill="#55DE7F5E"/>
        <Ellipse x:Name="EggSpot2" Canvas.Left="80" Canvas.Top="84" Width="18" Height="12" Fill="#55DE7F5E"/>
        <Ellipse x:Name="EggSpot3" Canvas.Left="52" Canvas.Top="104" Width="10" Height="8" Fill="#55DE7F5E"/>
        <Path x:Name="EggCrack" Stroke="#FF8A6A50" StrokeThickness="2" Visibility="Collapsed"
              Data="M44,72 L54,80 L60,72 L68,82 L76,72 L84,80 L94,72"/>
      </Canvas>

      <!-- tokens on their way in, the needs-you waves, the wake-up pill -->
@@PROPS@@

      <Canvas x:Name="MinionsFront"/>

      <TextBlock x:Name="Fx" Canvas.Left="108" Canvas.Top="30" FontFamily="Segoe UI, Segoe UI Symbol" FontSize="18"
                 FontWeight="Bold" Foreground="#FF6B7FD7" Visibility="Collapsed"/>
    </Canvas>
  </Canvas>
</Window>
'@
[xml]$xaml = $xamlText.Replace('@@CREATURE@@', (Get-CreatureXaml)).Replace('@@PROPS@@', (Get-PropsXaml))

$window = [Windows.Markup.XamlReader]::Load([System.Xml.XmlNodeReader]::new($xaml))
$ui = @{}
$xaml.SelectNodes('//*[@*[local-name()="Name"]]') | ForEach-Object {
    $n = $_.Attributes | Where-Object LocalName -eq 'Name' | Select-Object -First 1
    $ui[$n.Value] = $window.FindName($n.Value)
}
$window.ShowActivated = $false
$tokIco = Join-Path $PSScriptRoot 'tok.ico'      # Task Manager's row for the window (the process itself stays PowerShell 7)
if (Test-Path -LiteralPath $tokIco) { try { $window.Icon = [Windows.Media.Imaging.BitmapFrame]::Create([Uri]$tokIco) } catch { } }

# ---------------------------------------------------------------- state
$script:Config = Get-BodyConfig
$loaded = Read-PetJson 'state.json'
$script:State = if ($loaded) { Update-PetState $loaded } else { New-PetState }
# An install from before the exact-usage switch keeps its live usage and skips the first bubbles (Get-OldInstallPlan in lib\Pet.ps1).
# A play-only or forced-look window changes nothing on disk.
if (-not $PlayOnly -and -not $RenderDir -and -not $Mood -and -not $Stage) {
    $oldPlan = Get-OldInstallPlan $loaded (Read-PetJson 'config.json')
    if ($oldPlan.Old) {
        $script:State.Greeted = $true
        if ($oldPlan.WriteLiveUsage -and (Set-ConfigFileKey 'LiveUsage' $true)) { $script:Config.LiveUsage = $true }
        Write-BodyLog "older install: exact usage stays $(if ($script:Config.LiveUsage -eq $true) { 'on' } else { 'as it was' }), no first bubbles"
    }
}
if ($X -ge 0) { $script:Config.Follow = $false }
$script:LastEvent = [datetime]::UtcNow.AddMinutes(-30)
$script:TurnOpen = $false     # a main turn in progress (a prompt or tool call with no reply yet): Tok stays awake
$script:LastPrompt = $null
$script:Mood = ''
$script:Pct = 0.0
$script:WindowInfo = $null
$script:BubbleQueue = [System.Collections.Generic.Queue[object]]::new()
$script:BubbleUntil = [datetime]::MinValue
$script:PinnedUntil = [datetime]::MinValue
$script:Target = $null
$script:Tick = 0
$script:LastSave = [datetime]::UtcNow
$script:Subagents = @{}
$script:Minions = [System.Collections.Generic.List[object]]::new()
$script:Particles = [System.Collections.Generic.List[object]]::new()
$script:Usage = [System.Collections.Generic.List[object]]::new()
$script:UsageIds = [System.Collections.Generic.HashSet[string]]::new()
$script:Rng = [System.Random]::new()
$script:Dpi = 1.0
$script:MyPid = $PID
$script:FastUntil = [datetime]::MinValue
$script:Recent = [System.Collections.Generic.List[string]]::new()   # recent tool hints, for dreams
$script:NextDream = [datetime]::MinValue
$script:LastDream = $null
$script:LastReset = $null           # the 5-hour reset time last seen, for the fresh-window party
$script:LastRethink = [datetime]::MinValue    # the self-correction look, at most once per 10 minutes
$script:LastTokEgg = [datetime]::MinValue     # the "Tok" easter egg fires at most once per 30 minutes
$script:Drag = $null
$script:Override = $null       # transient face (love, chomp, rethink) until a time
$script:OverrideUntil = [datetime]::MinValue
# the edges (Parliament session 4, design\parliament\edges\VERDICT.md). These are plain flags and times, never loops.
$script:TurnErr = $false       # the turn so far ended on an error: a main Ouch sets it, a main Tool or Prompt clears it
$script:LastProject = ''       # the project of the latest main Tool or Prompt, for "All yours." when the Done event has none
$script:ErrPrev = [datetime]::MinValue; $script:ErrRethink = [datetime]::MinValue     # the last main error, and the last time two of them made the rethink look
$script:WaitingSince = $null   # Claude asked a question or showed a plan and is waiting on you (until your next prompt, or 30 minutes)
$script:ReadSweep = $null; $script:LastSweep = [datetime]::MinValue       # a short-lived flag: the pupils' reading sweep (Step-Eyes), at most once per 20 s
$script:ReadsSinceEdit = 0; $script:LastNod = [datetime]::MinValue         # reads since the last Edit or Write, and the last nod
$script:DayCounted = $false; $script:LastDayKey = ''; $script:FxHoldUntil = [datetime]::MinValue     # the day that counts: the flag, the day it last fired, and the ✦ held in the Fx slot
# When the last main-session event was. A restart remembers it from the state (the last meal), so the first prompt of the
# morning still counts as coming back after a quiet night.
$script:LastMainUtc = try { [datetime]::Parse($script:State.LastFedUtc, $null, 'RoundtripKind').ToUniversalTime() } catch { [datetime]::UtcNow }

function Pick([string[]]$Lines) { $Lines[$script:Rng.Next($Lines.Count)] }

# ---------------------------------------------------------------- bubble
# One bubble at a time. -Low (dreams, easter eggs) is dropped if anything is showing or waiting, and any live bubble
# ends a Low one early (Get-BubbleVerdict in lib\Pet.ps1).
$script:BubbleLow = $false
$script:FanMsg = ''; $script:FanN = 0; $script:LastFan = [datetime]::MinValue
$script:BubbleAside = $false; $script:BubblePanel = $false
function Say([string]$Text, [double]$Seconds = 3.5, [switch]$Now, [switch]$Pin, [switch]$Panel, [switch]$Low, $Rows = $null) {
    # -Pin: important (the limit, the reset, say.ps1); tool chatter is dropped while it shows.
    # -Panel: several lines of stats, left-aligned and a size smaller.
    # -Rows: a right-click panel (Stats, Today, Family) drawn as a title and rows (Show-BubbleRows).
    if ($script:Passing -and -not $Pin) { return }      # the set piece (lib\Passing.ps1) has the stage; only pinned lines speak
    $utcNow = [datetime]::UtcNow
    if (-not $Pin -and $utcNow -lt $script:PinnedUntil) { return }
    $verdict = Get-BubbleVerdict ([bool]$Low) ($utcNow -lt $script:BubbleUntil) $script:BubbleLow $script:BubbleQueue.Count
    if ($verdict -eq 'drop') { return }
    if ($Now -or $Pin) { $script:BubbleQueue.Clear(); $script:BubbleUntil = [datetime]::MinValue }
    elseif ($verdict -eq 'cut') { $script:BubbleUntil = [datetime]::MinValue }
    if ($Pin) { $script:PinnedUntil = $utcNow.AddSeconds($Seconds) }
    if ($script:BubbleQueue.Count -ge 3) { $null = $script:BubbleQueue.Dequeue() }
    $script:BubbleQueue.Enqueue(@{ Text = $Text; Seconds = $Seconds; Panel = [bool]$Panel; Low = [bool]$Low; Rows = $Rows })
}

# The right-click panels (lib\Pet.ps1 Get-StatsPanel / Get-TodayPanel, lib\Lineage.ps1 Get-FamilyRows): a title line, then
# a grid of label · value · detail (labels muted brown, values right-aligned so the numbers stack), or for Family a small
# live-drawn portrait (Get-PortraitXaml, cropped to the body and sprout) beside two lines per generation. Contrast is by
# brightness, never hue alone.
function New-PanelText([string]$Text, [double]$Size, [string]$Weight = 'SemiBold', [string]$Color = '#FF1E1612') {
    $tb = [Windows.Controls.TextBlock]@{ Text = $Text; FontSize = $Size; FontWeight = $Weight; VerticalAlignment = 'Center'
                                         FontFamily = [Windows.Media.FontFamily]::new('Segoe UI, Segoe UI Emoji, Segoe UI Symbol') }
    $tb.Foreground = $script:BrushConv.ConvertFromString($Color)
    $tb
}
$script:PanelMuted = '#FF6E5A4E'
# Pace's bar (Haiku's floor, session 7: 4 DIP, a 2 DIP notch, dark on a pale track). The fill is the bubble's own rust; the
# notch is ink and stands 3 DIP proud of the bar on each side, so it reads over the fill as well as the track.
function New-PaceBar([double]$Bar, [double]$Notch) {
    $split = {
        param([double]$At, $El)
        $g = [Windows.Controls.Grid]::new()
        foreach ($w in $At, (1 - $At)) { $null = $g.ColumnDefinitions.Add([Windows.Controls.ColumnDefinition]@{ Width = [Windows.GridLength]::new([math]::Max(0.0, [double]$w), 'Star') }) }
        [Windows.Controls.Grid]::SetColumn($El, $(if ($El -is [Windows.Shapes.Rectangle]) { 1 } else { 0 })); $null = $g.Children.Add($El)
        $g
    }
    $box = [Windows.Controls.Grid]@{ Height = 10; Margin = [Windows.Thickness]::new(0, 1, 0, 4) }
    $null = $box.Children.Add([Windows.Controls.Border]@{ Height = 4; CornerRadius = [Windows.CornerRadius]::new(2); Background = $script:BrushConv.ConvertFromString('#FFE6D6C8') })
    $null = $box.Children.Add((& $split $Bar ([Windows.Controls.Border]@{ Height = 4; CornerRadius = [Windows.CornerRadius]::new(2); Background = $script:BrushConv.ConvertFromString('#FF8A3E28') })))
    $null = $box.Children.Add((& $split $Notch ([Windows.Shapes.Rectangle]@{ Width = 2; Height = 10; HorizontalAlignment = 'Left'; Margin = [Windows.Thickness]::new(-1, 0, 0, 0); Fill = $script:BrushConv.ConvertFromString('#FF1E1612') })))
    $box
}
function Show-BubbleRows($Panel, [double]$Size) {
    $ui.BubbleRows.Children.Clear()
    if (-not $Panel) { $ui.BubbleRows.Visibility = 'Collapsed'; $ui.BubbleText.Visibility = 'Visible'; return }
    $title = New-PanelText $Panel.Title ($Size + 1) 'Bold'
    $title.Margin = [Windows.Thickness]::new(0, 0, 0, 3)
    $null = $ui.BubbleRows.Children.Add($title)
    if ($Panel.Kind -eq 'family') {
        foreach ($r in @($Panel.Rows)) {
            # a generation that never had a body gets an empty dashed ring the body's size: an honest absence, not a broken image
            $art = if ($r.Stage) { Get-PortraitXaml $r.Stage } elseif ($r.NoBody) { "<Ellipse Canvas.Left='26' Canvas.Top='52' Width='88' Height='80' Stroke='#998A3E28' StrokeThickness='5' StrokeDashArray='2.2 1.6' Fill='#14E07A55'/>" } else { '' }
            $pxaml = "<Viewbox xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation' Width='34' Height='40' Margin='0,0,8,0' VerticalAlignment='Center'>" +
                "<Canvas Width='100' Height='138'><Canvas.RenderTransform><TranslateTransform X='-20' Y='6'/></Canvas.RenderTransform>$art</Canvas></Viewbox>"
            $row = [Windows.Controls.StackPanel]@{ Orientation = 'Horizontal'; Margin = [Windows.Thickness]::new(0, 1, 0, 1) }
            $null = $row.Children.Add([Windows.Markup.XamlReader]::Parse($pxaml))
            $lines = [Windows.Controls.StackPanel]@{ VerticalAlignment = 'Center' }
            $null = $lines.Children.Add((New-PanelText $r.Lines[0] $Size))
            $null = $lines.Children.Add((New-PanelText $r.Lines[1] $Size 'Normal' $script:PanelMuted))
            $null = $row.Children.Add($lines)
            $null = $ui.BubbleRows.Children.Add($row)
        }
    } else {
        $g = [Windows.Controls.Grid]::new()
        foreach ($w in 'Auto', 'Auto', '*') { $null = $g.ColumnDefinitions.Add([Windows.Controls.ColumnDefinition]@{ Width = [Windows.GridLengthConverter]::new().ConvertFromString($w) }) }
        $notes = @()
        foreach ($r in @($Panel.Rows)) {
            if ($r.Note) { $notes += $r.Note; continue }
            $i = $g.RowDefinitions.Count
            $null = $g.RowDefinitions.Add([Windows.Controls.RowDefinition]::new())
            # pace (P1): the bar, or the "At this pace" line, across all three columns under its usage row
            $wide = if ($r.Line) { $t = New-PanelText $r.Line $Size; $t.Margin = [Windows.Thickness]::new(0, 0, 0, 3); $t }
                    elseif ($r.ContainsKey('Bar')) { New-PaceBar $r.Bar $r.Notch }
            if ($wide) {
                [Windows.Controls.Grid]::SetRow($wide, $i); [Windows.Controls.Grid]::SetColumnSpan($wide, 3)
                $null = $g.Children.Add($wide); continue
            }
            $cells = @(
                @{ T = (New-PanelText $r.L $Size 'Normal' $script:PanelMuted); C = 0; M = [Windows.Thickness]::new(0, 1, 14, 1) }
                @{ T = (New-PanelText $r.V $Size); C = 1; M = [Windows.Thickness]::new(0, 1, 0, 1) }
            )
            $cells[1].T.HorizontalAlignment = 'Right'
            if ($r.D) { $cells += @{ T = (New-PanelText $r.D $Size 'Normal'); C = 2; M = [Windows.Thickness]::new(7, 1, 0, 1) } }
            foreach ($c in $cells) {
                $c.T.Margin = $c.M
                [Windows.Controls.Grid]::SetRow($c.T, $i); [Windows.Controls.Grid]::SetColumn($c.T, $c.C)
                $null = $g.Children.Add($c.T)
            }
        }
        $null = $ui.BubbleRows.Children.Add($g)
        foreach ($n in $notes) { $nt = New-PanelText $n ($Size - 1) 'Normal' $script:PanelMuted; $nt.Margin = [Windows.Thickness]::new(0, 3, 0, 0); $null = $ui.BubbleRows.Children.Add($nt) }
    }
    $ui.BubbleText.Visibility = 'Collapsed'
    $ui.BubbleRows.Visibility = 'Visible'
}

# Sets the bubble text; the bubble sizes to it, centered over Tok. A bubble taller than the room above Tok (a Family panel
# with three generations) makes the window grow upward for as long as it shows.
function Show-BubbleText([string]$Text, [bool]$Panel = $false, $Rows = $null) {
    $size = [double]($script:Config.BubbleFontSize ?? 16)
    $ui.BubbleText.FontSize = if ($Panel) { $size - 2 } else { $size }
    $ui.BubbleText.TextAlignment = if ($Panel) { 'Left' } else { 'Center' }
    $ui.BubbleText.Text = $Text
    Show-BubbleRows $Rows ($size - 2)
    $ui.Bubble.Visibility = 'Visible'
    $ui.Bubble.UpdateLayout(); $ui.Bubble.Measure([Windows.Size]::new(272, [double]::PositiveInfinity))
    Set-WindowSpan (-(Get-BubbleOverflow $ui.Bubble.DesiredSize.Height))
}

# The window is 320x310 so a bubble has room above Tok, but every redraw of a transparent window is paid for in
# software by its area. With no bubble showing, the window shrinks to the bottom 200 DIP (Tok, its sprout and its
# orbit) and the content is shifted so nothing moves on screen; it grows back before a bubble appears.
# TopOff is how far the window's top sits below where it normally would: 110 compact, 0 normal, negative for a tall bubble.
$script:Compact = $false; $script:TopOff = 0.0
function Set-WindowSpan([double]$Off) {
    if ($Off -eq $script:TopOff) { return }
    $window.Top += $Off - $script:TopOff; $window.Height = 310 - $Off
    $ui.Root.RenderTransform = if ($Off) { [Windows.Media.TranslateTransform]::new(0, -$Off) } else { [Windows.Media.Transform]::Identity }
    $script:TopOff = $Off; $script:Compact = $Off -gt 0
}
function Set-Compact([bool]$On) { Set-WindowSpan $(if ($On) { 110.0 } else { 0.0 }) }

function Step-Bubble {
    $now = [datetime]::UtcNow
    if ($script:BubbleAside -and $ui.Bubble.Visibility -eq 'Visible') {
        $c = [System.Windows.Forms.Cursor]::Position; $pt = $ui.Bubble.PointFromScreen([Windows.Point]::new($c.X, $c.Y))
        if (-not (Test-PointerIn $pt.X $pt.Y $ui.Bubble.ActualWidth $ui.Bubble.ActualHeight)) {
            $script:BubbleAside = $false
            $ui.Bubble.BeginAnimation([Windows.UIElement]::OpacityProperty, [Windows.Media.Animation.DoubleAnimation]::new(1, [TimeSpan]::FromMilliseconds(200)))
        }
    }
    if ($now -lt $script:BubbleUntil) { return }
    if ($script:BubbleQueue.Count -gt 0) {
        $b = $script:BubbleQueue.Dequeue()
        $script:BubbleLow = $b.Low; $script:BubblePanel = $b.Panel; $script:BubbleAside = $false
        Show-BubbleText $b.Text $b.Panel $b.Rows
        $ui.Bubble.BeginAnimation([Windows.UIElement]::OpacityProperty,
            [Windows.Media.Animation.DoubleAnimation]::new(0, 1, [TimeSpan]::FromMilliseconds(160)))
        $script:BubbleUntil = $now.AddSeconds($b.Seconds)
    } elseif ($ui.Bubble.Visibility -eq 'Visible') {
        $ui.Bubble.Visibility = 'Collapsed'; $script:BubbleLow = $false; $script:BubbleAside = $false
        Set-Compact $true
    } elseif (-not $script:Compact) { Set-Compact $true }
}

# ---------------------------------------------------------------- faces
# Poses come from Get-Pose (lib\Art.ps1); the belly's lantern is the meter, the sprout on top is Tok's age (Get-SproutKey).
$script:BrushConv = [Windows.Media.BrushConverter]::new()
function Get-Brush([string]$Color) { $script:BrushConv.ConvertFromString($Color) }
function Get-Color([string]$Color) { [Windows.Media.ColorConverter]::ConvertFromString($Color) }

function Start-Bob([double]$Seconds, [double]$Amp, [int]$Fps = 0) {
    $a = [Windows.Media.Animation.DoubleAnimation]::new(0, -$Amp, [TimeSpan]::FromSeconds($Seconds))
    $a.AutoReverse = $true
    $a.RepeatBehavior = [Windows.Media.Animation.RepeatBehavior]::Forever
    $a.EasingFunction = [Windows.Media.Animation.SineEase]::new()
    Set-LoopFps $a $Seconds $Fps
    $ui.PetBob.BeginAnimation([Windows.Media.TranslateTransform]::YProperty, $a)
    $ui.PetBob.BeginAnimation([Windows.Media.TranslateTransform]::XProperty, $null)
}

# Endless loops are drawn at a lower frame rate: every frame of a transparent window is drawn in software,
# and these never stop. The cost is per frame, not per pixel (measured 10-09: a 170x170 window costs what a 320x310 does).
# Slow loops (breathing, the sprout's sway) move under half a pixel a frame at 8 fps, so they look the same as at 12
# and cost about a point less (awake idle 5.3% -> 4.1% of a core, -Bench 90 s); fast ones get 24.
function Set-LoopFps($Anim, [double]$Seconds, [int]$Fps = 0) {
    [Windows.Media.Animation.Timeline]::SetDesiredFrameRate($Anim, $(if ($Fps) { $Fps } elseif ($Seconds -ge 1.5) { 8 } else { 24 }))
}

# A back-and-forth that runs on its own (WPF animates it; nothing is stepped by hand).
function Start-Swing($Target, $Property, [double]$From, [double]$To, [double]$Seconds, [int]$Fps = 0) {
    $a = [Windows.Media.Animation.DoubleAnimation]::new($From, $To, [TimeSpan]::FromSeconds($Seconds))
    $a.AutoReverse = $true; $a.RepeatBehavior = [Windows.Media.Animation.RepeatBehavior]::Forever
    $a.EasingFunction = [Windows.Media.Animation.SineEase]::new()
    Set-LoopFps $a $Seconds $Fps
    $Target.BeginAnimation($Property, $a)
}

# The spinner's glyphs as outlines (so they can carry the sticker's rim and outline), centred in the 24x24 spark, built once each.
$script:SparkGeos = @{}
function Get-SparkGeo([string]$Glyph) {
    if (-not $script:SparkGeos.ContainsKey($Glyph)) {
        $tf = [Windows.Media.Typeface]::new([Windows.Media.FontFamily]::new('Segoe UI Symbol'), [Windows.FontStyles]::Normal, [Windows.FontWeights]::Bold, [Windows.FontStretches]::Normal)
        $ft = [Windows.Media.FormattedText]::new($Glyph, [Globalization.CultureInfo]::InvariantCulture, [Windows.FlowDirection]::LeftToRight, $tf, 18, [Windows.Media.Brushes]::Black, 1.0)
        $g = $ft.BuildGeometry([Windows.Point]::new(0, 0))
        $b = $g.Bounds
        $g.Transform = [Windows.Media.TranslateTransform]::new(12 - ($b.X + $b.Width / 2), 12 - ($b.Y + $b.Height / 2))
        $g.Freeze()
        $script:SparkGeos[$Glyph] = $g
    }
    $script:SparkGeos[$Glyph]
}
$ui.SparkFace.Data = Get-SparkGeo '✻'

# Awake and idle (and dozing, see Start-Breath), Tok breathes once and then rests (10-09 night). The endless bob and sway cost a drawn frame 8 times a second
# for ever, and a window where nothing moves costs nothing to draw. A breath is the old one: the body rises 2.5 DIP and settles
# in 3.2 s, the sprout swaying out and back on it (the other side each breath, so two breaths make the old left-right). Then
# everything holds still for 2.5 to 4.5 s (Get-BreathRest), and it breathes again. Both animations stop at their end, so no
# clock runs during the rest.
$script:BreathTimer = [Windows.Threading.DispatcherTimer]::new()
$script:BreathSide = 1
function Start-Breath {
    $script:BreathTimer.Stop()
    if ($script:MotionKind -notin 'rest', 'sleep') { return }
    # asleep (dozing, not the nightcap's 'coma') breathes the same way, slower and shallower, resting longer, at 5 fps (session 7)
    $asleep = $script:MotionKind -eq 'sleep'
    $secs = if ($asleep) { 2.8 } else { 1.6 }; $amp = if ($asleep) { 1.2 } else { 2.5 }; $swayDeg = if ($asleep) { 1.5 } else { 4 }; $fps = if ($asleep) { 5 } else { 0 }
    $bob = [Windows.Media.Animation.DoubleAnimation]::new(0, -$amp, [TimeSpan]::FromSeconds($secs))
    $bob.AutoReverse = $true; $bob.FillBehavior = [Windows.Media.Animation.FillBehavior]::Stop
    $bob.EasingFunction = [Windows.Media.Animation.SineEase]::new()
    Set-LoopFps $bob $secs $fps
    $ui.PetBob.BeginAnimation([Windows.Media.TranslateTransform]::YProperty, $bob)
    $ui.PetBob.BeginAnimation([Windows.Media.TranslateTransform]::XProperty, $null)
    if (-not $script:Passing) {      # the set piece holds the sprout itself
        $script:BreathSide = -$script:BreathSide
        $sway = [Windows.Media.Animation.DoubleAnimation]::new(0, $swayDeg * $script:BreathSide, [TimeSpan]::FromSeconds($secs))
        $sway.AutoReverse = $true; $sway.FillBehavior = [Windows.Media.Animation.FillBehavior]::Stop
        $sway.EasingFunction = [Windows.Media.Animation.SineEase]::new()
        Set-LoopFps $sway $secs $fps
        $ui.SproutRot.BeginAnimation([Windows.Media.RotateTransform]::AngleProperty, $sway)
    }
    $script:BreathTimer.Interval = [TimeSpan]::FromSeconds(2 * $secs + $(if ($asleep) { Get-BreathRest $script:Rng.NextDouble() 4 3 } else { Get-BreathRest $script:Rng.NextDouble() }))
    $script:BreathTimer.Start()
}
$script:BreathTimer.Add_Tick({ try { Start-Breath } catch { Write-BodyLog "breath: $_" } })

# Breathing, the sprout's sway, the token stream and the waves, by kind of look.
$script:MotionKind = ''
function Start-Motion([string]$Face) {
    if ($Face -like 'eat?' -or $Face -like 'home?') { return }      # a mouthful or a homecoming keeps the current bob
    $kind = if ($Face -in 'busy', 'zoom', 'sleep', 'coma', 'egg', 'needs') { $Face } else { 'rest' }
    if ($kind -eq $script:MotionKind -or $script:NoMotion) { return }
    $script:MotionKind = $kind
    $angle = [Windows.Media.RotateTransform]::AngleProperty
    if ($kind -notin 'rest', 'sleep') { $script:BreathTimer.Stop() }
    switch ($kind) {
        'busy'  { Start-Bob 0.5 2 -Fps 16; Start-Swing $ui.SproutRot $angle -3 3 0.4 -Fps 16 }      # 16, not 24: about 3 points less while working (-Bench, 10-09)
        'zoom'  { Start-Bob 0.16 3; Start-Swing $ui.SproutRot $angle -4 4 0.18 }
        'sleep' { Start-Breath }      # asleep is most of the day: one slow breath at 5 fps, then 4 to 7 s still (Start-Breath)
        'coma'  { Start-Bob 3.5 1 -Fps 5; Start-Swing $ui.PeekLeafRot $angle -3 3 3 -Fps 5; Start-Swing $ui.PeekFlowerRot $angle -3 3 3 -Fps 5 }
        'egg'   { Start-Bob 1.8 1;  $ui.SproutRot.BeginAnimation($angle, $null) }
        'needs' { Start-Bob 1.6 2.5; Start-Swing $ui.SproutRot $angle -4 4 1.2 }
        default { Start-Breath }      # awake and idle: one breath, then a rest (Start-Breath)
    }
    # the spinner turns through Claude Code's own glyphs and back, like the one in the status bar (faster in fast mode)
    $data = [Windows.Shapes.Path]::DataProperty
    if ($kind -in 'busy', 'zoom') {
        $step = if ($kind -eq 'zoom') { 0.06 } else { 0.12 }
        $glyphs = '·', '✢', '✳', '✶', '✻', '✽', '✻', '✶', '✳', '✢'
        $a = [Windows.Media.Animation.ObjectAnimationUsingKeyFrames]::new()
        for ($i = 0; $i -lt $glyphs.Count; $i++) { $null = $a.KeyFrames.Add([Windows.Media.Animation.DiscreteObjectKeyFrame]::new((Get-SparkGeo $glyphs[$i]), [Windows.Media.Animation.KeyTime]::FromTimeSpan([TimeSpan]::FromSeconds($i * $step)))) }
        $a.Duration = [TimeSpan]::FromSeconds($glyphs.Count * $step); $a.RepeatBehavior = [Windows.Media.Animation.RepeatBehavior]::Forever
        $ui.SparkFace.BeginAnimation($data, $a)
    } else { $ui.SparkFace.BeginAnimation($data, $null) }
    if ($kind -eq 'needs') { Start-Swing $ui.Waves ([Windows.UIElement]::OpacityProperty) 1 0.15 0.6 }
    else { $ui.Waves.BeginAnimation([Windows.UIElement]::OpacityProperty, $null) }
}

function Show-Fx([string]$Text, [string]$Color = '#FF6B7FD7') {
    if (-not $Text) { $ui.Fx.Visibility = 'Collapsed'; return }
    $ui.Fx.Text = $Text
    $ui.Fx.Foreground = Get-Brush $Color
    $ui.Fx.Visibility = 'Visible'
}

function Get-Stage {
    if ($script:StageHold) { return ($Stages | Where-Object Name -eq $script:StageHold) }      # the set piece holds the old Tok's stage
    if ($script:ForcedStage) { return ($Stages | Where-Object Name -eq $script:ForcedStage) }
    Get-PetStage $script:State
}

function Set-Geo($Geo, [double]$Cx, [double]$Cy, [double]$Rx, [double]$Ry) {
    $Geo.Center = [Windows.Point]::new($Cx, $Cy); $Geo.RadiusX = $Rx; $Geo.RadiusY = $Ry
}

function Set-Arm([string]$Side, $A, [string]$Fill = '#FFC9664A') {
    $ui["Arm${Side}Geo"].Center = [Windows.Point]::new($A[0], $A[1])
    $rot = $ui["Arm${Side}Rot"]
    $rot.BeginAnimation([Windows.Media.RotateTransform]::AngleProperty, $null)
    $rot.CenterX = $A[0]; $rot.CenterY = $A[1]; $rot.Angle = $A[2]
    $ui["Arm$Side"].Fill = Get-Brush $Fill
}

# The lantern. Set-Lantern says where the honey should be (and whether it is banked); Step-Lantern eases the
# drawn level toward it, a few ticks at a time, so a change in the window rises and falls instead of jumping.
$script:LanternTarget = 0.05; $script:LanternShown = $null; $script:LanternBanked = $null; $script:PupilK = 1.0
function Set-LanternShape([double]$Level) {
    $h = Get-HoneyGeometry $Level
    $ui.HoneyLit.Data = [Windows.Media.Geometry]::Parse($h.Data)
    $ui.HoneyBank.Data = $ui.HoneyLit.Data
    if ($h.Meniscus) { $ui.Meniscus.Data = [Windows.Media.Geometry]::Parse($h.Meniscus) }
    $ui.Meniscus.Visibility = if ($h.Meniscus -and -not $script:LanternBanked) { 'Visible' } else { 'Collapsed' }
    $ui.Warmth.Opacity = 0.12 + 0.3 * $Level
}
function Set-Lantern([double]$Level, [bool]$Banked) {
    $Level = [math]::Max($script:LanternMin, [math]::Min($Level, 1.0))
    $script:LanternTarget = $Level
    $changed = $script:LanternBanked -ne $Banked
    $script:LanternBanked = $Banked
    $ui.HoneyLit.Visibility = if ($Banked) { 'Collapsed' } else { 'Visible' }
    $ui.HoneyBank.Visibility = if ($Banked) { 'Visible' } else { 'Collapsed' }
    $ui.Warmth.Visibility = if ($Banked) { 'Collapsed' } else { 'Visible' }
    if ($null -eq $script:LanternShown -or $script:NoMotion -or $changed) { $script:LanternShown = $Level; Set-LanternShape $Level }
}
function Step-Lantern {
    if ($null -eq $script:LanternShown) { return }
    $d = $script:LanternTarget - $script:LanternShown
    if ([math]::Abs($d) -lt 0.004) {
        if ($d -ne 0) { $script:LanternShown = $script:LanternTarget; Set-LanternShape $script:LanternShown }
        return
    }
    $script:LanternShown += $d * 0.3
    Set-LanternShape $script:LanternShown
}

# Applies the look for the current stage, window and mood.
$script:LastArms = ''; $script:LastSprout = ''
function Update-Look([string]$Mood) {
    if ($script:Passing) { return }      # the set piece animates the creature itself until it ends
    $stage = Get-Stage
    $isEgg = $stage.Name -eq 'egg' -and $Mood -ne 'coma'
    $coma = $Mood -eq 'coma'
    $ui.Creature.Visibility = if ($isEgg) { 'Collapsed' } else { 'Visible' }
    $ui.Egg.Visibility = if ($isEgg) { 'Visible' } else { 'Collapsed' }
    Set-EggSpots ($script:PassTint ?? (Get-EggSpotColor "$((Get-CurrentRec $script:State.Lineage).Tint)"))      # the inherited tint, if the parent was an elder
    $ui.EggCrack.Visibility = if ((Get-CurrentRec $script:State.Lineage).Replies -gt 0 -or $script:ForcedStage -eq 'egg') { 'Visible' } else { 'Collapsed' }
    $face = if ($script:Override -and [datetime]::UtcNow -lt $script:OverrideUntil) { $script:Override } else { $Mood }
    if ($coma -and $face -ne 'stretch') { $face = 'coma' }
    $p = Get-Pose $face
    $private = Test-Private
    $ui.PetScale.ScaleX = $stage.Scale; $ui.PetScale.ScaleY = $stage.Scale

    # the sprout is age: hatchling, kid, adult, elder. Under the nightcap (the limit) it is hidden.
    $sk = Get-SproutKey $stage.MinDays
    $sp = if ($face -eq 'coma') { '' } elseif ($p.Perk -and $sk -eq 'H') { 'SHp' } elseif ($p.Fold) { "S${sk}f" } else { "S$sk" }
    if ($sp -ne $script:LastSprout) {
        foreach ($c in $ui.Sprout.Children) { if ($c.Name) { $c.Visibility = if ($c.Name -eq $sp) { 'Visible' } else { 'Collapsed' } } }
        $script:LastSprout = $sp
    }
    # the limit: the nightcap. The adult's top leaf pair and the elder's flower poke through its slit.
    $ui.Cap.Visibility = if ($face -eq 'coma') { 'Visible' } else { 'Collapsed' }
    $ui.CapSlit.Visibility = if ($sk -in 'A', 'E') { 'Visible' } else { 'Collapsed' }
    $ui.PeekLeaf.Visibility = if ($face -eq 'coma' -and $sk -eq 'A') { 'Visible' } else { 'Collapsed' }
    $ui.PeekFlower.Visibility = if ($face -eq 'coma' -and $sk -eq 'E') { 'Visible' } else { 'Collapsed' }

    # the belly is the 5-hour window: a lantern of honey; banked (dimmed) at the limit
    $banked = $face -eq 'coma'
    Set-Lantern $(if ($banked) { [math]::Max($script:Pct, 0.97) } else { $script:Pct }) $banked

    # body: the same size at every fullness; settled and curled up at the limit
    $b = if ($p.Body -eq 'limit') { $script:BodyLimit } else { $script:BodyNormal }
    Set-Geo $ui.BodyGeo $b[0] $b[1] $b[2] $b[3]
    $pumpkin = (Get-Date).ToString('MM-dd') -eq '10-31' -or $script:ForcePumpkin
    $ui.BodyLight.Color = Get-Color $(if ($pumpkin) { '#FFF9B25A' } else { '#FFF4AE8C' })
    $ui.BodyMid.Color = Get-Color $(if ($pumpkin) { '#FFE8741C' } else { '#FFDE7F5E' })
    $ui.BodyEdge.Color = Get-Color $(if ($pumpkin) { '#FFB4500F' } else { '#FFB65A3D' })
    $ui.Shadow.Width = if ($coma) { 88 } else { 76 }
    [Windows.Controls.Canvas]::SetLeft($ui.Shadow, 70 - $ui.Shadow.Width / 2)

    # arms (hatchlings have none yet)
    $arms = if ($stage.Name -eq 'hatchling') { 'none' } else { $p.Arms }
    $ui.ArmL.Visibility = if ($arms -eq 'none') { 'Collapsed' } else { 'Visible' }
    $ui.ArmR.Visibility = $ui.ArmL.Visibility
    if ($arms -ne 'none' -and $arms -ne $script:LastArms) {
        $a = $script:ArmPoses[$arms]
        Set-Arm 'L' $a[0] $(if ($arms -eq 'hold') { '#FFD27052' } else { '#FFC9664A' })
        Set-Arm 'R' $a[1] $(if ($arms -in 'pat', 'hold') { '#FFD27052' } else { '#FFC9664A' })
        [Windows.Controls.Panel]::SetZIndex($ui.ArmR, $(if ($arms -in 'pat', 'hold') { 10 } else { 0 }))
        [Windows.Controls.Panel]::SetZIndex($ui.ArmL, $(if ($arms -eq 'hold') { 10 } else { 0 }))
    }
    $script:LastArms = $arms
    $ui.Lean.Angle = $p.Lean
    $ui.Lift.Y = $p.Lift

    # the face by age: a hatchling's eyes are bigger and mostly pupil, a kid has freckles, an elder wears spectacles
    $eyeY = if ($stage.Name -eq 'hatchling') { 81 } else { 80 }
    $ew = if ($stage.Name -eq 'hatchling') { @(9.2, 11) } else { @(8.6, 10.4) }
    $ep = switch ($stage.Name) { 'hatchling' { @(6.6, 7.8) } 'elder' { @(4.4, 5.4) } default { @(5.0, 6.1) } }
    $script:PupilK = switch ($stage.Name) { 'hatchling' { 0.7 } 'elder' { 0.9 } default { 1.0 } }
    foreach ($side in 'L', 'R') {
        $ex = if ($side -eq 'L') { 55 } else { 85 }
        Set-Geo $ui["Eye${side}White"] $ex $eyeY $ew[0] $ew[1]
        Set-Geo $ui["Pupil${side}Geo"] $ex $eyeY $ep[0] $ep[1]
    }
    $ui.Freckles.Visibility = if ($stage.Name -eq 'kid') { 'Visible' } else { 'Collapsed' }
    $ui.FreckleT.Y = if ($coma) { 7 } else { 0 }
    foreach ($n in 'CheekL', 'CheekR') {
        $ui[$n].Opacity = if ($stage.Name -eq 'hatchling' -and $p.Cheek -lt 0.42) { 0.42 } else { $p.Cheek }
        $g = $ui["${n}Geo"]; $g.Center = [Windows.Point]::new($g.Center.X, $p.CheekCy)
        $ui["${n}Puff"].CenterY = $p.CheekCy
    }

    # eyes: open (on your work), closed, pleased, or squeezed; sunglasses in private mode
    $shades = $private -and $p.Eyes -ne 'closed'
    $ui.EyeL.Visibility = if ($p.Eyes -eq 'open' -and -not $shades) { 'Visible' } else { 'Collapsed' }
    $ui.EyeR.Visibility = $ui.EyeL.Visibility
    $ui.ClosedEyes.Visibility = if ($p.Eyes -eq 'closed') { 'Visible' } else { 'Collapsed' }
    if ($p.Eyes -eq 'closed') { $ui.ClosedEyes.Data = [Windows.Media.Geometry]::Parse((Get-ClosedEyesData $p.ClosedCy)) }
    $ui.HappyEyes.Visibility = if ($p.Eyes -eq 'happy' -and -not $shades) { 'Visible' } else { 'Collapsed' }
    $ui.SqueezeEyes.Visibility = if ($p.Eyes -eq 'squeeze' -and -not $shades) { 'Visible' } else { 'Collapsed' }
    $ui.Shades.Visibility = if ($shades) { 'Visible' } else { 'Collapsed' }
    # the elder's spectacles: never with the sunglasses; they slip when the eyes close
    $ui.Specs.Visibility = if ($stage.Name -eq 'elder' -and -not $shades) { 'Visible' } else { 'Collapsed' }
    $slip = $p.Eyes -eq 'closed'
    $ui.SpecsT.Y = if ($slip) { 5 } else { 0 }
    $ui.SpecsRot.CenterY = if ($slip) { 85 } else { 80 }; $ui.SpecsRot.Angle = if ($slip) { -7 } else { 0 }

    # mouth
    $ui.Mouth.Visibility = if ($p.Mouth -in 'smile', 'path') { 'Visible' } else { 'Collapsed' }
    if ($p.Mouth -eq 'smile') {
        $sm = $p.Smile
        if ($face -notin 'love', 'content') { $sm = switch ($stage.Name) { 'hatchling' { @(3.5, 2.6, 96) } 'kid' { @(7, 5, 95) } default { $sm } } }
        $ui.Mouth.Data = [Windows.Media.Geometry]::Parse((Get-SmileData $sm[0] $sm[1] $sm[2]))
    }
    elseif ($p.Mouth -eq 'path') { $ui.Mouth.Data = [Windows.Media.Geometry]::Parse($p.Path) }
    $o = $p.Mouth -eq 'o'
    $ui.OMouth.Visibility = if ($o) { 'Visible' } else { 'Collapsed' }; $ui.OTongue.Visibility = $ui.OMouth.Visibility
    if ($o) {
        Set-Geo $ui.OMouthGeo $p.O[0] $p.O[1] $p.O[2] $p.O[3]
        Set-Geo $ui.OTongueGeo $p.O[0] ($p.O[1] + $p.O[3] * 0.45) ($p.O[2] * 0.55) ($p.O[3] * 0.35)
    }
    $ui.HiMouth.Visibility = if ($p.Mouth -eq 'hi') { 'Visible' } else { 'Collapsed' }

    # props
    $ui.Spark.Visibility = if ($p.Spark) { 'Visible' } else { 'Collapsed' }
    $ui.Waves.Visibility = if ($p.Waves) { 'Visible' } else { 'Collapsed' }
    $ui.WakePill.Visibility = if ($face -eq 'coma' -and $script:State.WakeUtc) { 'Visible' } else { 'Collapsed' }
    if ($face -eq 'coma') { $ui.WakeText.Text = Get-WakeText }
    if ([datetime]::UtcNow -lt $script:FxHoldUntil) { Show-Fx '✦' '#FFE0A030' } else { Show-Fx $p.Fx $p.FxColor }      # the day-count ✦ outranks the face's own mark for its 1.2 s
    Start-Motion $(if ($isEgg) { 'egg' } else { $face })
}

function Get-WakeText {
    if (-not $script:State.WakeUtc) { return '' }
    $t = [datetime]::Parse($script:State.WakeUtc, $null, 'RoundtripKind').ToLocalTime()
    $t.ToString($(if ($t.Minute) { 'h:mm' } else { 'h tt' }))
}

function Set-Override([string]$Face, [double]$Seconds) {
    $script:Override = $Face
    $script:OverrideUntil = [datetime]::UtcNow.AddSeconds($Seconds)
    Update-Look $script:Mood
}

function Invoke-Squish([double]$Amount = 0.12, [int]$Ms = 140) {
    foreach ($p in @([Windows.Media.ScaleTransform]::ScaleYProperty, [Windows.Media.ScaleTransform]::ScaleXProperty)) {
        $to = if ($p -eq [Windows.Media.ScaleTransform]::ScaleYProperty) { 1 - $Amount } else { 1 + $Amount }
        $a = [Windows.Media.Animation.DoubleAnimation]::new(1, $to, [TimeSpan]::FromMilliseconds($Ms))
        $a.AutoReverse = $true
        $ui.Squish.BeginAnimation($p, $a)
    }
}

function Invoke-Hop([switch]$Plain) {
    $spec = Get-HopSpec (Get-Stage).Name ([bool]$Plain)
    $a = [Windows.Media.Animation.DoubleAnimationUsingKeyFrames]::new()
    $a.KeyFrames.Add([Windows.Media.Animation.EasingDoubleKeyFrame]::new(-$spec.Height, [Windows.Media.Animation.KeyTime]::FromTimeSpan([TimeSpan]::FromMilliseconds($spec.RiseMs)), [Windows.Media.Animation.QuadraticEase]@{ EasingMode = 'EaseOut' })) | Out-Null
    $a.KeyFrames.Add([Windows.Media.Animation.EasingDoubleKeyFrame]::new(0, [Windows.Media.Animation.KeyTime]::FromTimeSpan([TimeSpan]::FromMilliseconds($spec.FallMs)), [Windows.Media.Animation.QuadraticEase]@{ EasingMode = 'EaseIn' })) | Out-Null
    $ui.HopT.BeginAnimation([Windows.Media.TranslateTransform]::YProperty, $a)
}

# The arm swings while Tok looks straight at you. -Seconds: how long it keeps asking before it settles.
function Invoke-Wave([double]$Seconds = 2.4) {
    Set-Override 'needs' $Seconds
    $a = [Windows.Media.Animation.DoubleAnimation]::new(17, 47, [TimeSpan]::FromMilliseconds(300))
    $a.AutoReverse = $true; $a.RepeatBehavior = [Windows.Media.Animation.RepeatBehavior]::new([math]::Max(2, [math]::Min(8, [int]($Seconds / 0.6))))
    $ui.ArmRRot.BeginAnimation([Windows.Media.RotateTransform]::AngleProperty, $a)
}

# Claude needs you: a hop and a wave, eyes on you, for about 20 seconds; then Tok settles and the bubble carries it.
function Invoke-NeedsYou { $script:GreetCancelled = $true; Invoke-Hop -Plain; Invoke-Wave 20 }      # the needs-you hop never scales with age

# The window resets: the nightcap comes off and Tok has a big stretch (the tokens are back).
function Invoke-Reset {
    Set-Override 'stretch' 1.8
    Invoke-Squish 0.1 300
}

# The nod ("think first, then write"): the first Edit or Write after two or more reads. The lean dips 6 degrees further
# forward (toward the work, the way the busy look leans) and back, 320 ms in all, from wherever it is now. The animation stops
# at its end, so the lean goes back to whatever Update-Look set.
function Invoke-Nod {
    $from = $ui.Lean.Angle
    $a = [Windows.Media.Animation.DoubleAnimation]::new($from, $from - 6, [TimeSpan]::FromMilliseconds(160))
    $a.AutoReverse = $true; $a.FillBehavior = [Windows.Media.Animation.FillBehavior]::Stop
    $ui.Lean.BeginAnimation([Windows.Media.RotateTransform]::AngleProperty, $a)
}

# Reading: on a main Read, Grep or Glob the pupils sweep left to right twice (Get-ReadSweepPos), about a second. This only sets a
# short-lived flag; Step-Eyes plays it, and Test-NeedsFastTick wants the fast loop only while it runs.
function Start-ReadSweep {
    $now = [datetime]::UtcNow
    $other = [bool]($script:Override -and $now -lt $script:OverrideUntil)
    if ($script:Passing -or -not (Test-ReadSweepOk $script:LastSweep $now ($ui.EyeL.Visibility -eq 'Visible') $other)) { return }
    $script:LastSweep = $now; $script:ReadSweep = @{ Start = $now }
    if ($script:SlowTick) { $script:SlowTick = $false; $fast.Interval = [TimeSpan]::FromMilliseconds(50) }      # start now, not up to a quarter second late
}

# The day counts: the sprout stretches from its base (scale 1 to 1.08 and back over 1.2 s) and a small gold ✦ shows in the Fx
# slot for the same 1.2 s. No bubble, no pip. Update-Look keeps the ✦ up while FxHoldUntil is in the future, and puts the
# face's own mark back when the timer ends.
function Start-DayStretch {
    foreach ($p in @([Windows.Media.ScaleTransform]::ScaleXProperty, [Windows.Media.ScaleTransform]::ScaleYProperty)) {
        $a = [Windows.Media.Animation.DoubleAnimation]::new(1, 1.08, [TimeSpan]::FromMilliseconds(600))
        $a.AutoReverse = $true; $a.FillBehavior = [Windows.Media.Animation.FillBehavior]::Stop
        $a.EasingFunction = [Windows.Media.Animation.SineEase]::new()
        $ui.SproutScale.BeginAnimation($p, $a)
    }
    $script:FxHoldUntil = [datetime]::UtcNow.AddMilliseconds(1200)
    Show-Fx '✦' '#FFE0A030'
    Start-Later 1250 { Update-Look $script:Mood }
}


# ---------------------------------------------------------------- reactions
$script:ToolLines = @{
    Edit = '✎ {0}'; Write = '📝 New file: {0}'; Read = '👀 {0}'; NotebookEdit = '✎ {0}'
    Bash = '⌁ {0}'; PowerShell = '⌁ {0}'; Grep = '🔍 {0}'; Glob = '🔍 {0}'
    WebSearch = '🌐 {0}'; WebFetch = '🌐 Reading {0}'; Agent = '🐣 Sending a minion: {0}'
    Skill = '📚 Skill: {0}'; TodoWrite = '☑ Updating the list'; ToolSearch = '🧰 Grabbing a tool'
    AskUserQuestion = '❓ A question for you'; ExitPlanMode = '📋 The plan is ready.'
}
# Chatter levels: which tool calls get a bubble. Questions and plans always do.
$script:NormalTools = 'Agent', 'Skill', 'WebSearch', 'WebFetch', 'Write'

function Get-YourName { "$($script:Config.YourName)" }

# ---------------------------------------------------------------- private mode (see lib\Privacy.ps1)
function Test-Private { Test-PrivateNow $script:Config }
$script:WasPrivate = $false

# $Minutes = 0 means "until turned off".
function Set-Private([bool]$On, [double]$Minutes = 0, [string]$Why = '') {
    $c = Get-BodyConfig
    if ($On -and $Minutes -gt 0) {
        $until = [datetime]::UtcNow.AddMinutes($Minutes)
        # never shorten a longer private stretch that's already running
        $cur = if ($c.PrivateUntil) { [datetime]::Parse($c.PrivateUntil, $null, 'RoundtripKind').ToUniversalTime() } else { [datetime]::MinValue }
        if ($until -gt $cur) { $c.PrivateUntil = $until.ToString('o') }
    } elseif ($On) { $c.Private = $true }
    else { $c.Private = $false; $c.PrivateUntil = $null }
    Save-PetJson $c 'config.json'
    $c.Follow = $script:Config.Follow; $script:Config = $c
    $script:PrivateItem.IsChecked = Test-Private      # ticked for a timed stretch too (auto-private), so one click ends it
    if ($On) {
        $script:Recent.Clear()          # no dreams about what came before, either
        $script:BubbleQueue.Clear()     # and drop anything already queued
        if (-not $script:WasPrivate) {
            Say $(if ($Why -like 'auto*') { '🕶 That looks private. Going incognito.' } else { '🕶 Private mode. My lips are sealed.' }) 3 -Now
        }
        $script:WasPrivate = $true
        Write-BodyLog "private on ($(if ($Minutes) { "$Minutes min" } else { 'until off' }), $Why)"
    }
    Update-Look $script:Mood
}

# Called from the slow loop: notices when a timed private stretch ends.
function Step-Private {
    $now = Test-Private
    if ($script:PrivateItem -and $script:PrivateItem.IsChecked -ne $now) { $script:PrivateItem.IsChecked = $now }      # a timer ran out, or private.ps1
    if ($script:WasPrivate -and -not $now) {
        $script:WasPrivate = $false
        Say '🕶 → 👀 OK, back to normal.' 3
        Write-BodyLog 'private off'
        Update-Look $script:Mood
    }
    $script:WasPrivate = $now -or $script:WasPrivate
}

# Anything sensitive-looking in a prompt or a tool call turns private mode on for a while.
# Already private: nothing to do, so a burst of matches no longer keeps pushing the timer out. The log names the
# pattern that fired, never the text it matched.
function Test-AutoPrivate([string[]]$Texts, [switch]$Prompt) {
    if (Test-Private) { return }
    $hit = Find-Sensitive $Texts (Get-PrivatePatterns $script:Config -Prompt:$Prompt)
    if (-not $hit) { return }
    Set-Private $true ([double]($script:Config.PrivateMinutes ?? 15)) "auto: $hit"
}

function Invoke-BodyEvent($E) {
    $now = [datetime]::UtcNow
    # the time of the last main-session event before this one (a Prompt asks whether it was more than 6 hours ago)
    $prevMain = $script:LastMainUtc
    if (-not $E.Sub -and $E.Type -in 'Usage', 'Tool', 'Prompt', 'Compact', 'Rethink', 'Ouch', 'Done', 'Interrupt', 'Limit') { $script:LastMainUtc = $now }
    switch ($E.Type) {
        'Usage' {
            if (-not $script:UsageIds.Add($E.Usage.Id)) { return }
            $script:Usage.Add($E.Usage)
            if (-not $E.Sub) { Add-LiveLineage $E }
            if ($script:State.Coma) { return }
            if ($E.Usage.Speed -eq 'fast' -and -not $E.Sub) {
                $script:FastUntil = $now.AddSeconds(30)
            }
            $null = Add-PetMeal $script:State $E.Usage
            if (-not $E.Sub) { $script:LastEvent = $now }
            $grew = Step-Growth
            if ($grew) {
                $evolved = $grew.To
                if ($grew.From -eq 'egg') {
                    # the egg wobbles, cracks and hatches (lib\Passing.ps1); the bubble says the line as it cracks
                    $hatchName = if ($script:State.Lineage) { Get-LineageName $script:State.Lineage } else { $script:State.Name }
                    if (-not (Start-Passing (Get-HatchPlan $hatchName "$((Get-CurrentRec $script:State.Lineage).Tint)"))) { Invoke-Hop; Say (Get-HatchLine $hatchName) 6 -Pin }
                } else { Invoke-Hop; Say "I grew! I'm $(if ($evolved -eq 'elder') { 'an' } else { 'a' }) $evolved now." 6 -Pin }
                Write-BodyLog "evolved to $evolved ($(Get-GenDays $script:State) days together)"
            } elseif ((Get-PetStage $script:State).Name -ne 'egg') {
                Start-Meal      # a token arrives, a chew, a swallow into the lantern (skipped if a mouthful is running)
            }
            # the day counts (Add-LiveLineage flagged it): the sprout stretches once, a small gold ✦ blinks. A day that also grew Tok
            # up has its own moment ("I grew!"), so it is not doubled.
            if ($script:DayCounted) {
                $script:DayCounted = $false
                if (-not $grew -and -not $script:Passing -and (Get-PetStage $script:State).Name -ne 'egg') { Start-DayStretch }
            }
        }
        'Tool' {
            Test-AutoPrivate $E.Keys
            if ($E.Sub) { return }
            $script:LastEvent = $now; $script:TurnOpen = $true; $script:TurnErr = $false
            if ($E.Project) { $script:LastProject = $E.Project }
            if (Test-WaitingAnswered $script:WaitingSince $now $E.Name) {      # Claude has moved on from its question (or you said yes to a tool)
                $script:WaitingSince = $null
                if ($script:Override -eq 'needs') { $script:Override = $null; Update-Look $script:Mood }
            }
            $tools = (Get-Today $script:State).Tools; $tools[$E.Name] = 1 + [int]$tools[$E.Name]
            $private = Test-Private
            if ($E.Hint -and -not $private) { $script:Recent.Add("$($E.Hint)"); if ($script:Recent.Count -gt 30) { $script:Recent.RemoveAt(0) } }
            $fmt = $script:ToolLines[$E.Name] ?? ('🔧 ' + (Get-ShortToolName $E.Name) + ' {0}')
            $hint = "$($E.Hint)"; if ($hint.Length -gt 70) { $hint = $hint.Substring(0, 67) + '…' }
            $line = if ($private) { Get-PrivateToolLine $E.Name } else { ($fmt -f $hint).Trim() }
            $chatter = "$($script:Config.Chatter)"
            if ($E.Name -in 'AskUserQuestion', 'ExitPlanMode') {
                # which session needs you, when another one from a different folder is going too
                $tag = Get-ProjectTag $E.Project (Get-LiveProjects)
                if ($tag -and -not $private) { $line += "`n($tag)" }
                Invoke-NeedsYou
                Invoke-Chime 'needs'      # a small pip, in case you aren't looking
                # the bubble stays for as long as the wave runs (20 s); after that the eyes stay on you, still, until you answer
                # (Step-Eyes) and the hover line says how long it has been waiting
                $script:WaitingSince = $now
                Say $line 20 -Pin
            } elseif ($chatter -eq 'quiet' -or ($chatter -eq 'normal' -and $E.Name -notin $script:NormalTools)) {
                # no bubble
            } elseif ($E.Name -eq 'Agent') {
                Say $line 4
            } else {
                Say $line 2.6
            }
            if ($E.Name -in 'Read', 'Grep', 'Glob') { $script:ReadsSinceEdit++; Start-ReadSweep }
            if ($E.Name -eq 'Skill' -and -not $script:Meal) { Set-Override 'skill' 1.2 }
            # fan-out: the 4th tool call from one reply (parallel calls) raises both arms for half a second, at most once per 5 minutes
            $script:FanN = Get-FanCount $script:FanMsg $script:FanN $E.MsgId; $script:FanMsg = $E.MsgId
            if ((Test-FanOut $script:FanN $script:LastFan $now) -and -not $script:Meal) { $script:LastFan = $now; Set-Override 'fan' 0.6 }
            if ($E.Name -in 'Edit', 'Write') {
                Invoke-Squish 0.08 110
                # think first, then write: the first edit after two or more reads gets a nod (at most once a minute)
                if (Test-Nod $script:ReadsSinceEdit $script:LastNod $now) { $script:LastNod = $now; Invoke-Nod }
                $script:ReadsSinceEdit = 0
            }
        }
        'Prompt' {
            $script:LastEvent = $now; $script:LastPrompt = $now; $script:TurnOpen = $true; $script:TurnErr = $false
            $script:WaitingSince = $null      # you answered
            if ($E.Project) { $script:LastProject = $E.Project }
            if ($script:Override -eq 'needs') { $script:Override = $null; Update-Look $script:Mood }   # you answered
            (Get-Today $script:State).Prompts++
            Invoke-Squish 0.15 160
            # the first prompt after more than 6 quiet hours: one stretch, no words (never "welcome back")
            if ((Test-QuietReturn $prevMain $now) -and -not $script:State.Coma) { Set-Override 'stretch' 1.8 }
            Test-AutoPrivate @($E.Text) -Prompt
            # no greeting bubble on a prompt, just the squish. Tok only speaks up for real changes.
            if ($script:State.Coma) { return }
            # easter eggs (Low priority: they never interrupt a live bubble): say its name, or say thanks
            if (Test-TokName $E.Text) {
                if (([datetime]::UtcNow - $script:LastTokEgg).TotalMinutes -ge 30) {
                    $script:LastTokEgg = [datetime]::UtcNow
                    Invoke-Hop; Set-Override 'love' 1.8; Say (Pick "That's me!", 'Hi! You called?') 2.5 -Low
                }
                return
            }
            if (Test-Thanks $E.Text) { Set-Override 'love' 1.8; Say (Pick '♥', 'Anytime', 'Aw, thank you.') 2.2 -Low; return }
            if ($script:Mood -eq 'sleep' -and $script:LastDream) { Say (Get-DreamRecallLine $script:LastDream.Subject) 4 -Low; $script:LastDream = $null }
        }
        'Compact' {
            # the conversation got compacted: Tok forgets most of it, visibly
            $script:LastEvent = $now
            Set-Override 'dizzy' 2.5
            Say 'Chat compacted. I kept the gist.' 3.5 -Low
        }
        'Interrupt' {
            # Esc: Claude stops now, so Tok stops looking busy and stops waiting up for it. A small settle, no bubble, no pip.
            $script:TurnOpen = $false
            $script:LastEvent = $now.AddSeconds(-30)      # the busy look lasts 25 s after the last event; this ends it now
            if ($script:Override -eq 'needs') { $script:Override = $null }
            $script:WaitingSince = $null
            Invoke-Squish 0.05 120
            Update-Look $script:Mood
        }
        'Rethink' {
            # at most once per 10 minutes, so it stays a small, true moment
            $script:LastEvent = $now
            if (($now - $script:LastRethink).TotalMinutes -lt 10 -or $script:Meal) { return }
            $script:LastRethink = $now
            Set-Override 'rethink' 1.8; Invoke-Squish 0.05 140
        }
        'Ouch' {
            # Errors are weather. Every one is counted and the turn remembers it ended on one, but Tok shows nothing for a single
            # error; two within 60 s make the orange rethink look (at most once per 60 s). No red, no flinch.
            $script:LastEvent = $now; $script:TurnErr = $true
            (Get-Today $script:State).Errors++
            if ((Test-ErrorBurst $script:ErrPrev $now $script:ErrRethink) -and -not $script:Meal) {
                $script:ErrRethink = $now
                Set-Override 'rethink' 1.6
            }
            $script:ErrPrev = $now
        }
        'Done' {
            $script:LastEvent = $now; $script:TurnOpen = $false; $script:GreetCancelled = $true      # a turn ending cuts the first bubbles short
            if (Test-WaitingAnswered $script:WaitingSince $now) { $script:WaitingSince = $null }
            (Get-Today $script:State).Done++
            $long = [bool]($script:LastPrompt -and ($now - $script:LastPrompt).TotalSeconds -gt 45)
            # A short turn only settles. A long one hops and says "All yours." with the done pip landing on the hop's touchdown;
            # if it ended on an error there is no hop and the line says so, with the falling pip now. No love face either way.
            $proj = if ($E.Project) { $E.Project } else { $script:LastProject }
            $end = Get-TurnEndPlan $long $script:TurnErr (Get-ProjectTag "$proj" (Get-LiveProjects)) (Test-Private)
            if ($end.Squish) { Invoke-Squish 0.05 120 }
            if ($end.Hop) { Invoke-Hop }
            if ($end.Text) { Say $end.Text 12 -Pin }
            if ($end.Pip -eq 'done') { Invoke-Chime 'done' -DelayMs (Get-HopSpec (Get-Stage).Name $false).FallMs }
            elseif ($end.Pip) { Invoke-Chime $end.Pip }
            $script:LastPrompt = $null; $script:TurnErr = $false
        }
        'Limit' {
            $reset = if ($script:WindowInfo -and $script:WindowInfo.Real) { $script:WindowInfo.Reset }
            Set-PetComa $script:State $E.Text $reset
            Save-PetJson $script:State 'state.json'
            Update-Look 'coma'; $script:Mood = 'coma'
            Say "🌙 Window's all used up. Asleep until $(Get-WakeText)." 10 -Pin
            Write-BodyLog "food coma: $($E.Text)"
        }
    }
}

# Age is days worked together, so a stage changes when a reply makes a day count (or a scan lands). Returns @{ From; To }
# when Tok has grown up (the caller hops and says so, once), and quietly follows any other change: a new generation
# starts young again, and the first day-count scan must not look like growing.
$script:LastStage = (Get-PetStage $script:State).Name
function Step-Growth {
    $now = (Get-PetStage $script:State).Name
    $from = $script:LastStage
    $script:LastStage = $now
    if ($null -eq $from -or $from -eq $now) { return $null }
    $order = @($Stages | ForEach-Object { $_.Name })
    if ($order.IndexOf($now) -gt $order.IndexOf($from)) { return @{ From = $from; To = $now } }
    $null
}

# Main-session replies feed the family tree; a newer model version makes Tok molt into the next generation.
# Replies from before the startup scan are already counted by it.
function Add-LiveLineage($E) {
    $script:DayCounted = $false
    $lin = $script:State.Lineage
    if (-not $lin -or -not $lin.ScannedUtc) { return }
    if ($E.Usage.Ts -le [datetime]::Parse($lin.ScannedUtc, $null, 'RoundtripKind').ToUniversalTime()) { return }
    $before = (Get-PetStage $script:State).Name       # the old Tok's stage, before the new generation starts at day 0
    $molt = Add-LineageReply $lin $E.Usage.Model $E.Usage.Ts $E.Usage.Out $E.Project
    # The day counts: this reply took today's count, every model together, to exactly 10 (Add-LineageReply keeps the per-day counts
    # that make a day count toward age). Once per day; a molt has its own piece, so it does not also stretch.
    $dk = $E.Usage.Ts.ToLocalTime().ToString('yyyy-MM-dd')
    if (Test-DayJustCounted (Get-DayTotal $lin $dk) $dk $script:LastDayKey) { $script:LastDayKey = $dk; $script:DayCounted = -not $molt }
    # The first generation is just the egg's first day (Step-Growth hatches it); only a later one is a passing-on.
    if ($molt -and @($lin.Generations).Count -gt 1) {
        $name = Get-LineageName $lin
        Write-BodyLog "molted: $name (claude $molt)"
        # A new model is a passing-on (lib\Passing.ps1): the old Tok gives its light to an egg, and the egg hatches a descendant
        # (right away if the new generation already has a day of work, otherwise on its first day). The only thing here that changes the state is Add-LineageReply above.
        $plan = Get-MoltPlan $before $E.Usage.Model $name "$((Get-CurrentRec $lin).Tint)" ((Get-PetStage $script:State).Name -ne 'egg')
        if (-not (Start-Passing $plan)) { Invoke-Hop; Set-Override 'love' 3; Say $plan.Line 8 -Pin }
    }
}

# ---------------------------------------------------------------- inbox (say.ps1)
$script:InboxPath = Join-Path $DataDir 'inbox.jsonl'
$script:InboxOffset = if (Test-Path $script:InboxPath) { (Get-Item $script:InboxPath).Length } else { 0L }
function Read-Inbox {
    if (-not (Test-Path $script:InboxPath)) { return }
    $len = (Get-Item $script:InboxPath).Length
    if ($len -lt $script:InboxOffset) { $script:InboxOffset = 0 }
    if ($len -eq $script:InboxOffset) { return }
    $fs = [System.IO.FileStream]::new($script:InboxPath, 'Open', 'Read', 'ReadWrite')
    try {
        $null = $fs.Seek($script:InboxOffset, 'Begin')
        $buf = [byte[]]::new($len - $script:InboxOffset)
        $read = $fs.Read($buf, 0, $buf.Length)
        $script:InboxOffset += $read
    } finally { $fs.Dispose() }
    foreach ($l in ([Text.Encoding]::UTF8.GetString($buf, 0, $read) -split "`n")) {
        if (-not $l.Trim()) { continue }
        try { $m = $l | ConvertFrom-Json } catch { continue }
        # commands from private.ps1
        if ($m.cmd -eq 'private') { Set-Private ([bool]$m.on) ([double]($m.minutes ?? 0)) "$($m.why)"; continue }
        if ($m.cmd -eq 'quit') { Write-BodyLog "quit: $($m.why)"; Save-PetJson $script:State 'state.json'; $window.Close(); return }
        if ($m.cmd -eq 'needs') { Invoke-HookNeeds $m; continue }      # from notify.ps1, Claude Code's Notification hook
        if (-not $m.text) { continue }
        $secs = [math]::Min(15.0, 2.5 + $m.text.Length / 14)
        if ($m.mood) { Set-Override $m.mood $secs }
        Invoke-Hop
        Say $m.text $secs -Pin
        if (-not $m.silent) { Invoke-Chime 'done' }      # say.ps1 is how Claude calls you back after a long run
    }
}

# Claude Code needs you and the transcript can't say so (a permission prompt, a server asking for input): notify.ps1 writes
# it to the inbox and Tok does what it does for a question (Get-HookNeedsPlan decides): the hop and wave, the needs pip, eyes
# on you until you answer. The project goes under the line when it tells two live sessions apart.
function Invoke-HookNeeds($M) {
    $now = [datetime]::UtcNow
    $age = try { ($now - [datetime]::Parse("$($M.at)", $null, 'RoundtripKind').ToUniversalTime()).TotalSeconds } catch { 0 }
    $private = Test-Private
    $plan = Get-HookNeedsPlan "$($M.kind)" "$($M.message)" (Test-Waiting $script:WaitingSince $now) $age $private
    Write-BodyLog "hook: $($M.kind)$(if (-not $plan) { ' (nothing to show)' })"
    if (-not $plan -or $script:State.Coma) { return }
    $line = $plan.Line
    if ($M.transcript -and -not $private) {
        $tag = Get-ProjectTag (Get-ProjectName ([TranscriptTail]::FirstCwd("$($M.transcript)"))) (Get-LiveProjects)
        if ($tag) { $line += "`n($tag)" }
    }
    $script:LastEvent = $now
    Invoke-NeedsYou
    Invoke-Chime 'needs'
    $script:WaitingSince = $now
    Say $line 20 -Pin
}

# ---------------------------------------------------------------- perching
$script:IgnoreClasses = 'Shell_TrayWnd', 'Shell_SecondaryTrayWnd', 'Progman', 'WorkerW', 'Windows.UI.Core.CoreWindow', 'XamlExplorerHostIslandWindow', 'TopLevelWindowForOverflowXamlIsland', 'NotifyIconOverflowWindow'
# Tok sits in the bottom-right corner of whatever app you're using (the window is 320x310; Tok's
# body spans x 172..268 and its feet rest at y 296), just above where a status bar would be.
function Get-CornerPoint([double]$Right, [double]$Bottom) { [Windows.Point]::new($Right - 288, $Bottom - 334) }
function Get-PerchTarget {
    $work = [System.Windows.SystemParameters]::WorkArea
    $script:TargetLeft = $work.Left
    $corner = Get-CornerPoint $work.Right ($work.Bottom + 16)
    $h = [Tok.Native]::GetForegroundWindow()
    if ($h -eq [IntPtr]::Zero) { return $script:Target ?? $corner }
    [uint32]$procId = 0; $null = [Tok.Native]::GetWindowThreadProcessId($h, [ref]$procId)
    if ($procId -eq $script:MyPid) { return $script:Target ?? $corner }
    $sb = [System.Text.StringBuilder]::new(256); $null = [Tok.Native]::GetClassName($h, $sb, 256)
    if ($sb.ToString() -in $script:IgnoreClasses -or [Tok.Native]::IsIconic($h)) { return $script:Target ?? $corner }
    # the app's own monitor, not the main one (10-10: on an ultrawide above the laptop, the main screen's edge put Tok mid-screen)
    $r = [Tok.Native+RECT]::new(); $mon = [Tok.Native+RECT]::new(); $wk = [Tok.Native+RECT]::new(); [int]$px = 0; [int]$py = 0; [int]$pw = 0; [int]$ph = 0
    if (-not [Tok.Native]::PerchInfo($h, [ref]$r, [ref]$mon, [ref]$wk, [ref]$px, [ref]$py, [ref]$pw, [ref]$ph)) { return $corner }
    $f = ConvertTo-LogicalRect $r $mon $px $py $pw $ph
    $d = $script:Dpi
    $wl = $wk.Left / $d; $wr = $wk.Right / $d; $wb = $wk.Bottom / $d
    $corner = Get-CornerPoint $wr ($wb + 16)
    $left = $f.Left / $d; $top = $f.Top / $d; $right = [math]::Min($f.Right / $d, $wr); $bottom = [math]::Min($f.Bottom / $d, $wb)
    if (($right - $left) -lt 300 -or ($bottom - $top) -lt 260) { return $corner }
    $script:TargetLeft = [math]::Max($left, $wl)
    Get-CornerPoint $right $bottom
}

function Step-Move {
    if (-not $script:Config.Follow) { return }
    if ($script:Tick % 20 -eq 0) { $script:Target = Get-PerchTarget }
    if (-not $script:Target) { return }
    $tx = Get-MinionRoomX $script:Target.X ($script:Minions.Count -gt 0) $script:TargetLeft
    $ty = $script:Target.Y + $script:TopOff
    $dx = $tx - $window.Left; $dy = $ty - $window.Top
    if ([math]::Abs($dx) + [math]::Abs($dy) -lt 1) { return }
    if ([math]::Abs($dx) + [math]::Abs($dy) -gt 900) { $window.Left = $tx; $window.Top = $ty; return }
    $window.Left += $dx * 0.18; $window.Top += $dy * 0.18
}

# ---------------------------------------------------------------- eyes + minions
function Step-Eyes {
    if ($script:Passing -or $script:Mood -in 'sleep', 'coma', 'egg' -or $ui.EyeL.Visibility -ne 'Visible') { $script:EyesKey = $null; return }     # eyes shut: look again on opening
    $now = [datetime]::UtcNow
    if ($script:Override -eq 'dizzy' -and $now -lt $script:OverrideUntil) {
        $t = $script:Tick * 0.45
        $ui.PupilL.X = 2.6 * [math]::Cos($t); $ui.PupilL.Y = 2.6 * [math]::Sin($t)
        $ui.PupilR.X = 2.6 * [math]::Cos(-$t); $ui.PupilR.Y = 2.6 * [math]::Sin(-$t)
        $script:EyesKey = $null
        return
    }
    # eating: eyes on the token; a minion coming home: eyes follow it
    # Every look that places the pupils itself clears EyesKey, so the pointer is looked up again the moment it ends (10-10: after a
    # meal or a homecoming the eyes stayed on the token's spot until the mouse moved).
    if ($script:Override -eq 'eat1') { $ui.PupilL.X = 4 * $script:PupilK; $ui.PupilL.Y = 3 * $script:PupilK; $ui.PupilR.X = $ui.PupilL.X; $ui.PupilR.Y = $ui.PupilL.Y; $script:EyesKey = $null; return }
    if ($script:Override -in 'home1', 'home3' -and $script:HomeLook) { $ui.PupilL.X = $script:HomeLook[0] * $script:PupilK; $ui.PupilL.Y = $script:HomeLook[1] * $script:PupilK; $ui.PupilR.X = $ui.PupilL.X; $ui.PupilR.Y = $ui.PupilL.Y; $script:EyesKey = $null; return }
    # the one time Tok looks straight at you: when it needs you
    if ($script:Override -eq 'needs' -and $now -lt $script:OverrideUntil) { $ui.PupilL.X = 0; $ui.PupilL.Y = -1; $ui.PupilR.X = 0; $ui.PupilR.Y = -1; $script:EyesKey = $null; return }
    $otherLook = [bool]($script:Override -and $now -lt $script:OverrideUntil)
    # reading (Start-ReadSweep): two quick left-to-right sweeps, then back to following the pointer. A short-lived flag consumed
    # here; it ends by itself after a second, or at once if another look starts. The range shrinks with the eyes (PupilK).
    if ($script:ReadSweep) {
        $pos = if ($otherLook) { $null } else { Get-ReadSweepPos (($now - $script:ReadSweep.Start).TotalSeconds) }
        if ($pos) {
            $ui.PupilL.X = $pos[0] * $script:PupilK; $ui.PupilL.Y = $pos[1] * $script:PupilK; $ui.PupilR.X = $ui.PupilL.X; $ui.PupilR.Y = $ui.PupilL.Y
            $script:EyesKey = $null
            return
        }
        $script:ReadSweep = $null
    }
    # and after the wave has settled, while Claude is still waiting on you (up to 30 minutes): still on you, no blinking. It costs
    # nothing: the pupils are set to the same place each pass, and nothing here asks for the fast loop.
    if (-not $otherLook -and (Test-Waiting $script:WaitingSince $now)) {
        $ui.PupilL.X = 0; $ui.PupilL.Y = -1; $ui.PupilR.X = 0; $ui.PupilR.Y = -1; $script:EyesKey = $null; return
    }
    # otherwise its eyes are on your work: wherever the pointer is (only recomputed when something moved)
    $p = [System.Windows.Forms.Cursor]::Position
    if ($script:Tick % 70 -eq 0 -and $script:Rng.Next(3) -eq 0) { Invoke-Blink }
    $key = '{0},{1},{2:0},{3:0},{4}' -f $p.X, $p.Y, $window.Left, $window.Top, $script:Mood
    if ($key -eq $script:EyesKey) { return }
    $script:EyesKey = $key
    $mx = $p.X / $script:Dpi - ($window.Left + 220); $my = $p.Y / $script:Dpi - ($window.Top + 244 - $script:TopOff)
    $d = [math]::Sqrt($mx * $mx + $my * $my); if ($d -lt 1) { $d = 1 }
    $ui.PupilL.X = 3.4 * $script:PupilK * $mx / [math]::Max($d, 60); $ui.PupilL.Y = 3.6 * $script:PupilK * $my / [math]::Max($d, 60)
    if ($script:Mood -eq 'hungry') { $ui.PupilL.Y = 3 * $script:PupilK }
    $ui.PupilR.X = $ui.PupilL.X; $ui.PupilR.Y = $ui.PupilL.Y
}

function Invoke-Blink {
    if ($ui.EyeL.Visibility -ne 'Visible') { return }
    foreach ($s in $ui.EyeLBlink, $ui.EyeRBlink) {
        $a = [Windows.Media.Animation.DoubleAnimation]::new(1, 0.1, [TimeSpan]::FromMilliseconds(80))
        $a.AutoReverse = $true
        $s.BeginAnimation([Windows.Media.ScaleTransform]::ScaleYProperty, $a)
    }
}

# Each subagent transcript is one entry in $script:Subagents (keyed by path):
#   @{ First; Seen; Model; Tool; Done; Desc; M }   where M is the live minion, once it has hatched.
# A minion hatches out of Tok's front once its model is known, orbits while the subagent works,
# and flies home (into the lantern, then the sprout) when the subagent's turn ends (or it goes quiet for 3 minutes).
function Update-Subagent([string]$Path, $E) {
    $now = [datetime]::UtcNow
    $s = $script:Subagents[$Path]
    if (-not $s) {
        $desc = ''
        try { $desc = (Get-Content -LiteralPath ($Path -replace '\.jsonl$', '.meta.json') -Raw | ConvertFrom-Json).description } catch { }
        $s = @{ First = $now; Seen = $now; Model = ''; Tool = ''; Done = $false; Desc = "$desc"; M = $null; Tokens = 0.0 }
        $script:Subagents[$Path] = $s
    }
    $s.Seen = $now
    if (-not $E) { return }
    switch ($E.Type) {
        'Usage'   { if ($E.Usage.Model -and $E.Usage.Model -ne '<synthetic>') { $s.Model = $E.Usage.Model }; $s.Tokens += $E.Usage.In + $E.Usage.Out + $E.Usage.CW }
        'Tool'    { $s.Tool = $E.Name; $s.Done = $false }
        'SubDone' { $s.Done = $true }
    }
}

function Add-Particle([string]$Text, [string]$Color, [double]$X, [double]$Y, [double]$Vx, [double]$Vy, [double]$Life, [double]$Size = 9, [bool]$Front = $true) {
    $tb = [Windows.Controls.TextBlock]@{ Text = $Text; FontSize = $Size; FontFamily = 'Segoe UI Symbol'; IsHitTestVisible = $false
        Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString($Color) }
    $layer = if ($Front) { $ui.MinionsFront } else { $ui.MinionsBack }
    $layer.Children.Insert(0, $tb)    # under the minions
    $script:Particles.Add(@{ El = $tb; Layer = $layer; X = $X; Y = $Y; Vx = $Vx; Vy = $Vy; Life = $Life; Age = 0.0 })
}

function Step-Particles {
    for ($i = $script:Particles.Count - 1; $i -ge 0; $i--) {
        $p = $script:Particles[$i]
        $p.Age += 0.05; $p.X += $p.Vx; $p.Y += $p.Vy
        if ($p.Hold -and $p.Age -gt 0.6) { $p.Vy = -0.15 }
        if ($p.Age -ge $p.Life) { $p.Layer.Children.Remove($p.El); $script:Particles.RemoveAt($i); continue }
        $p.El.Opacity = if ($p.Hold) { [math]::Min(1.0, [math]::Max(0.0, ($p.Life - $p.Age) / ($p.Life - $p.Hold))) } else { 1 - $p.Age / $p.Life }
        [Windows.Controls.Canvas]::SetLeft($p.El, $p.X); [Windows.Controls.Canvas]::SetTop($p.El, $p.Y)
    }
}

function New-Minion($Kind, $Info) {
    $v = New-MinionVisual $Kind
    # Pop from the sprout (the back of the orbit, under the leaves), then spread out from the ones already flying.
    $angle = -[math]::PI / 2
    $m = @{ V = $v; Kind = $Kind; Angle = $angle; Born = 0.0; Hatched = [datetime]::UtcNow; Eat = -1.0; HomeAt = $null; HomeFrom = $null; Phase = $script:Rng.NextDouble() * 6; BlinkAt = $script:Tick + 20; Zoom = 0; Adjust = 0; Layer = $null; Info = $Info }
    Set-MinionLayer $m $true
    $script:Minions.Add($m)
    if ($script:State.Lineage -and -not $PlayOnly -and -not $RenderDir) { Add-LineageMinion $script:State.Lineage $Info.Model }
    $m
}

function Set-MinionLayer($M, [bool]$Front) {
    $want = if ($Front) { $ui.MinionsFront } else { $ui.MinionsBack }
    if ($M.Layer -eq $want) { return }
    if ($M.Layer) { $M.Layer.Children.Remove($M.V.Root) }
    $null = $want.Children.Add($M.V.Root)
    $M.Layer = $want
}

# A minion that hatched before its subagent's model was known is orange ('other'); when the model arrives it takes its
# real kind: colour, size, speed and lift (the loop reads them from the kind each tick).
function Set-MinionKind($M, $Kind) {
    if ($M.Layer) { $M.Layer.Children.Remove($M.V.Root) }
    $M.Kind = $Kind; $M.V = New-MinionVisual $Kind; $M.Layer = $null
    Set-MinionLayer $M $true
}

function Remove-Minion($M) {
    if ($M.Layer) { $M.Layer.Children.Remove($M.V.Root) }
    $null = $script:Minions.Remove($M)
}

function Get-Ease([double]$T) { $T = [math]::Max(0.0, [math]::Min(1.0, $T)); $T * $T * (3 - 2 * $T) }
function Get-Lerp([double]$A, [double]$B, [double]$T) { $A + ($B - $A) * $T }
function Get-Seg([double]$U, [double]$A, [double]$B) { [math]::Max(0.0, [math]::Min(1.0, ($U - $A) / ($B - $A))) }
$script:SproutTop = @{ egg = 40; hatchling = 40; kid = 30; adult = 14; elder = 6 }
$script:GeoChew = [Windows.Media.Geometry]::Parse($script:ChewPath)
$script:GeoGrin = [Windows.Media.Geometry]::Parse((Get-SmileData 7 5 95))

# The lantern's surface: a ripple (p 0..1) where something just dropped in, and a flash of the meniscus.
function Show-LanternRipple([double]$P) {
    if ($P -le 0 -or $P -ge 1) { $ui.MealRip1.Visibility = 'Collapsed'; $ui.MealRip2.Visibility = 'Collapsed'; return }
    $y = (Get-LevelY $script:LanternShown) + 1
    $r1 = Get-Lerp 3 9 $P; $r2 = Get-Lerp 6 16 $P
    Set-Geo $ui.MealRip1Geo 72 $y $r1 ($r1 * 0.28); Set-Geo $ui.MealRip2Geo 72 $y $r2 ($r2 * 0.24)
    $ui.MealRip1.Opacity = 1 - $P; $ui.MealRip2.Opacity = 0.6 * (1 - $P)
    $ui.MealRip1.Visibility = 'Visible'; $ui.MealRip2.Visibility = 'Visible'
}
function Set-LanternPulse([bool]$On) { $ui.Meniscus.StrokeThickness = if ($On) { 2.4 } else { 1.5 } }
function Invoke-BellyPat {
    $pat = [Windows.Media.Animation.DoubleAnimation]::new(38, 16, [TimeSpan]::FromMilliseconds(180))
    $pat.AutoReverse = $true; $pat.RepeatBehavior = [Windows.Media.Animation.RepeatBehavior]::new(3)
    $ui.ArmRRot.BeginAnimation([Windows.Media.RotateTransform]::AngleProperty, $pat)
}

# One mouthful, 3 seconds: a token arrives in Tok's hands; it chews (4-5 beats a second, cheeks puffed); it swallows
# and you see the token drop into the lantern; a ripple, a flash of the meniscus, and the level settles. At most one
# at a time: a usage event while one is running is skipped. Tok only eats while it is awake and nothing else is going on.
$script:Meal = $null
function Start-Meal([switch]$Force) {
    if ($script:Meal -or $script:State.Coma -or $script:Passing) { return }
    if ((Get-Stage).Name -eq 'egg') { return }
    if (@($script:Minions | Where-Object { $_.Eat -ge 0 }).Count) { return }
    if (-not $Force -and $script:Override -and [datetime]::UtcNow -lt $script:OverrideUntil) { return }
    $script:Meal = @{ Start = [datetime]::UtcNow; Face = ''; Alt = -1; Gulped = $false }
}
function Set-MealFace([string]$Face) {
    if ($script:Meal.Face -eq $Face) { return }
    $script:Meal.Face = $Face
    Set-Override $Face 4
}
function Step-Meal {
    if (-not $script:Meal) { return }
    $m = $script:Meal
    $u = ([datetime]::UtcNow - $m.Start).TotalSeconds
    if ($u -ge 3.0) {
        $ui.MealTok.Visibility = 'Collapsed'; Show-LanternRipple 1; Set-LanternPulse $false
        foreach ($c in $ui.CheekLPuff, $ui.CheekRPuff) { $c.ScaleX = 1; $c.ScaleY = 1 }
        $script:Meal = $null
        if ($script:Override -like 'eat?') { $script:Override = $null; Update-Look $script:Mood }
        return
    }
    $ui.MealTok.Visibility = 'Visible'
    if ($u -lt 0.6) {
        $q = Get-Ease ($u / 0.6)
        Set-MealFace 'eat1'
        $ui.MealWhole.Visibility = 'Visible'; $ui.MealBitten.Visibility = 'Collapsed'
        $ui.MealTokS.ScaleX = 0.9; $ui.MealTokS.ScaleY = 0.9
        $ui.MealTokR.Angle = Get-Lerp -40 -8 $q; $ui.MealTokT.X = Get-Lerp 150 70 $q; $ui.MealTokT.Y = Get-Lerp 70 106 $q
    } elseif ($u -lt 2.0) {
        Set-MealFace 'eat2'
        $ui.MealWhole.Visibility = 'Collapsed'; $ui.MealBitten.Visibility = 'Visible'
        $sz = Get-Lerp 1.8 0.9 (Get-Seg $u 0.6 2.0)
        $ui.MealTokS.ScaleX = $sz; $ui.MealTokS.ScaleY = $sz; $ui.MealTokR.Angle = -8; $ui.MealTokT.X = 70; $ui.MealTokT.Y = 106
        $alt = [int]([math]::Floor($u / 0.11)) % 2
        if ($alt -ne $m.Alt) { $m.Alt = $alt; $ui.Mouth.Data = if ($alt) { $script:GeoChew } else { $script:GeoGrin } }
        $puff = 1 + 0.4 * (0.5 + 0.5 * [math]::Sin($u * 2 * [math]::PI * 4.5))
        foreach ($c in $ui.CheekLPuff, $ui.CheekRPuff) { $c.ScaleX = $puff; $c.ScaleY = $puff }
    } elseif ($u -lt 2.5) {
        $q = Get-Seg $u 2.0 2.5
        Set-MealFace 'eat3'
        if (-not $m.Gulped) { $m.Gulped = $true; Invoke-Squish 0.06 130; foreach ($c in $ui.CheekLPuff, $ui.CheekRPuff) { $c.ScaleX = 1; $c.ScaleY = 1 } }
        $ui.MealWhole.Visibility = 'Visible'; $ui.MealBitten.Visibility = 'Collapsed'
        $ui.MealTokS.ScaleX = 0.55; $ui.MealTokS.ScaleY = 0.55; $ui.MealTokR.Angle = 90 * $q
        $ui.MealTokT.X = 70; $ui.MealTokT.Y = Get-Lerp ($script:Lantern.Y - $script:Lantern.Ry + 3) ((Get-LevelY $script:LanternShown) - 3) ($q * $q)
    } else {
        Set-MealFace 'eat4'
        $ui.MealTok.Visibility = 'Collapsed'
        Set-LanternPulse ($u -lt 2.8)
        Show-LanternRipple (Get-Seg $u 2.5 3.0)
    }
}

# A minion that has finished goes home (never eaten): it flies to the lantern, tips and pours what it carried in as
# honey, then flies up and tucks into the sprout. Tok watches, then pats its belly. One at a time.
function Set-HomeFace([string]$Face) {
    if ($script:HomeFace -eq $Face) { return }
    $script:HomeFace = $Face
    Set-Override $Face 5
    if ($Face -eq 'home3') { Invoke-BellyPat }
}
$script:HomeFace = ''; $script:HomeLook = $null
function Step-Home($M, [bool]$Dead) {
    $k = $M.Kind; $v = $M.V; $now = [datetime]::UtcNow
    if (-not $M.HomeAt) {
        $M.HomeAt = $now; $M.HomeFrom = Get-OrbitPoint $M.Angle $k
        $what = if ($M.Info.Desc -and -not (Test-Private)) { '✓ “{0}” is done.' -f $M.Info.Desc } else { '✓ A subagent is done.' }
        if (Test-MinionRanLong $M.Info.First $M.Info.Seen) { Say $what 2.6 }      # only a job that ran over 45 s gets its line; the honey pour says the rest
    }
    $u = ($now - $M.HomeAt).TotalSeconds
    $f = $M.HomeFrom; $hx = 98; $hy = 100
    Set-MinionLayer $M $true
    $x = $hx; $y = $hy; $sc = 1.0; $rot = -70.0
    for ($d = 1; $d -le 4; $d++) { $ui["MealDrop$d"].Visibility = 'Collapsed' }
    if ($u -lt 0.6) {
        $q = Get-Ease ($u / 0.6)
        $x = Get-Lerp $f.X $hx $q; $y = (Get-Lerp $f.Y $hy $q) - 12 * [math]::Sin([math]::PI * $q)
        $sc = Get-Lerp $f.Depth 1.0 $q; $rot = -70 * $q
        $script:HomeLook = @([math]::Max(-4, [math]::Min(4, ($x - 70) / 12)), [math]::Max(-4, [math]::Min(4, ($y - 80) / 12)))
        Set-HomeFace 'home1'
    } elseif ($u -lt 1.5) {
        $rot = -70 - 6 * [math]::Sin($u * 9)
        $L = Get-LevelY $script:LanternShown
        for ($d = 0; $d -lt 4; $d++) {
            $q = Get-Seg $u (0.6 + 0.15 * $d) (1.0 + 0.15 * $d)
            if ($q -gt 0 -and $q -lt 1) {
                $dr = $ui["MealDrop$($d + 1)"]
                [Windows.Controls.Canvas]::SetLeft($dr, (Get-Lerp ($hx - 8) 76 $q)); [Windows.Controls.Canvas]::SetTop($dr, (Get-Lerp ($hy + 2) ($L - 1) ($q * $q)))
                $dr.Visibility = 'Visible'
            }
        }
        $script:HomeLook = @(3, 3)
        Set-HomeFace $(if ($u -gt 1.0) { 'home2' } else { 'home1' })
        Set-LanternPulse ($u -ge 1.0 -and $u -lt 1.3)
        Show-LanternRipple $(if ($u -ge 1.0) { Get-Seg $u 1.0 1.5 } else { 0 })
    } else {
        Set-LanternPulse $false; Show-LanternRipple 0
        $q = Get-Ease (Get-Seg $u 1.5 2.5)
        $top = $script:SproutTop[(Get-Stage).Name] + 6
        $x = Get-Lerp $hx 70 $q; $y = (Get-Lerp $hy $top $q) - 18 * [math]::Sin([math]::PI * $q)
        $sc = 1.0 - 0.85 * $q; $rot = -70 * (1 - $q)
        $script:HomeLook = if ($q -gt 0.4) { @(0, -4) } else { @(3, -2) }
        Set-HomeFace 'home3'
    }
    $v.Scale.ScaleX = $sc; $v.Scale.ScaleY = $sc; $v.Spin.Angle = $rot
    [Windows.Controls.Canvas]::SetLeft($v.Root, $x - $k.Size / 2); [Windows.Controls.Canvas]::SetTop($v.Root, $y - $k.Size / 2)
    if ($u -ge 2.8) {
        Remove-Minion $M
        foreach ($key in @($script:Subagents.Keys)) { if ($script:Subagents[$key].M -eq $M) { $script:Subagents.Remove($key) } }
        for ($d = 1; $d -le 4; $d++) { $ui["MealDrop$d"].Visibility = 'Collapsed' }
        Set-LanternPulse $false; Show-LanternRipple 0
        $script:HomeFace = ''; $script:HomeLook = $null
        if ($script:Override -like 'home?') { $script:Override = $null; Update-Look $script:Mood }
    }
}

# Short faces end on time, not on the slow loop's 0.75s beat.
function Step-Chew {
    if ($script:Override -and [datetime]::UtcNow -ge $script:OverrideUntil -and -not $script:Meal) {
        $script:Override = $null; Update-Look $script:Mood
    }
}

function Step-Minions {
    $now = [datetime]::UtcNow
    Step-Chew
    $dead = $script:State.Coma   # at the limit, minions just tuck away
    $homing = @($script:Minions | Where-Object { $_.Eat -ge 0 }).Count -gt 0
    # hatch: a subagent whose model is known (or that has run 8s without saying) gets a minion, up to 5 at once
    foreach ($k in @($script:Subagents.Keys)) {
        $s = $script:Subagents[$k]
        $quiet = ($now - $s.Seen).TotalSeconds -gt 180
        if ($s.M -or $dead -or $quiet) { continue }
        if (-not $s.Model -and -not $s.Done -and ($now - $s.First).TotalSeconds -lt 8) { continue }
        if ($script:Minions.Count -ge 5) { continue }
        $s.M = New-Minion (Get-MinionKind $s.Model) $s
    }
    # done: the subagent finished (or went quiet) -> its minion hops into Tok, after at least 2s on show
    foreach ($k in @($script:Subagents.Keys)) {
        $s = $script:Subagents[$k]
        $quiet = ($now - $s.Seen).TotalSeconds -gt 180
        if ($s.M -and $s.M.Eat -lt 0 -and $s.Model) {
            $want = Get-MinionKind $s.Model
            if ($s.M.Kind.Name -ne $want.Name) { Set-MinionKind $s.M $want }
        }
        if ($s.M -and $s.M.Eat -lt 0 -and ($dead -or (($s.Done -or $quiet) -and ($now - $s.M.Hatched).TotalSeconds -ge 2))) {
            if ($dead) { $s.M.Eat = 0.0 }
            elseif (-not $homing -and -not $script:Meal) { $s.M.Eat = 0.0; $homing = $true }     # one homecoming at a time
        }
        if (-not $s.M -and $quiet) { $script:Subagents.Remove($k) }
    }

    foreach ($m in @($script:Minions)) {
        $k = $m.Kind; $v = $m.V
        if ($m.Eat -ge 0) {
            if ($dead) {
                Remove-Minion $m
                foreach ($key in @($script:Subagents.Keys)) { if ($script:Subagents[$key].M -eq $m) { $script:Subagents.Remove($key) } }
            } else { Step-Home $m $false }
            continue
        }
        if ($m.Born -lt 1) { $m.Born = [math]::Min(1.0, $m.Born + 0.05 / 0.35) }
        $zooming = $m.Zoom -gt 0
        if ($zooming) { $m.Zoom-- }
        $m.Angle += if ($zooming) { $k.Speed * 2.4 } else { $k.Speed }
        $p = Get-OrbitPoint $m.Angle $k
        Set-MinionLayer $m $p.Front
        $bob = $k.Bob * [math]::Sin($script:Tick * $k.BobRate + $m.Phase)
        $sc = $p.Depth * (1 - [math]::Pow(1 - $m.Born, 3))
        $v.Scale.ScaleX = $sc; $v.Scale.ScaleY = $sc
        # a seed tips toward where it's going
        $v.Spin.Angle = 25 * [math]::Cos($m.Angle) + 8 * [math]::Sin($script:Tick * $k.BobRate + $m.Phase)
        [Windows.Controls.Canvas]::SetLeft($v.Root, $p.X - $k.Size / 2); [Windows.Controls.Canvas]::SetTop($v.Root, $p.Y - $k.Size / 2 + $bob)
        if ($k.Name -eq 'haiku' -and -not $zooming -and $script:Rng.Next(140) -eq 0) { $m.Zoom = 16 }
    }
    Step-Particles
}

# ---------------------------------------------------------------- the slow loop
$script:Tail = [TranscriptTail]::new($ProjectsDir)
# the projects of the main sessions that wrote in the last 15 minutes, one per session (Get-ProjectTag)
function Get-LiveProjects { @($script:Tail.LiveCwds(15) | ForEach-Object { Get-ProjectName $_ }) }
function Step-Life {
    foreach ($l in $script:Tail.Poll()) {
        $events = @(ConvertTo-BodyEvents $l.Line $l.Sub $l.Cwd)
        if ($l.Sub) { Update-Subagent $l.Path $null; foreach ($e in $events) { Update-Subagent $l.Path $e } }
        foreach ($e in $events) { Invoke-BodyEvent $e }
    }
    Read-Inbox
    Step-Private
    Step-LiveUsage
    Step-Greeting

    if (Step-PetWake $script:State) {
        Invoke-Reset; Invoke-Hop
        $script:LastReset = $null    # this is the fresh-window moment; no second party
        Say (Get-FreshWindowLine) 6 -Pin
        Invoke-Chime 'wake'          # only here, after a real limit: an octave with the stretch (never on a routine reset)
        Save-PetJson $script:State 'state.json'
        Write-BodyLog 'woke from the food coma'
    }

    $now = [datetime]::UtcNow
    if ($script:WaitingSince -and -not (Test-Waiting $script:WaitingSince $now)) { $script:WaitingSince = $null }      # waited 30 minutes: let go
    # every 10 minutes: how much CPU Tok itself used, and how much of that time it was asleep (the budget is
    # under 2% of one core asleep, under 8% working; see design\parliament\life\VERDICT.md)
    if ($script:Mood -in 'sleep', 'coma') { $script:AsleepTicks++ }
    if ($script:Tick % 12000 -eq 0) {
        $cpu = [Diagnostics.Process]::GetCurrentProcess().TotalProcessorTime.TotalSeconds
        if ($script:CpuMark) {
            $secs = ($now - $script:CpuMark.At).TotalSeconds
            Write-BodyLog ("cpu: {0:N1}% of one core over {1:N0} min, asleep {2:P0} of it" -f (100 * ($cpu - $script:CpuMark.Cpu) / $secs), ($secs / 60), [math]::Min(1, $script:AsleepTicks / [math]::Max(1, $secs / 0.75)))
        }
        $script:CpuMark = @{ At = $now; Cpu = $cpu }; $script:AsleepTicks = 0
    }
    if ($script:Tick % 100 -eq 0) {
        $cut = $now.AddHours(-24)
        $script:Usage.RemoveAll([Predicate[object]] { param($u) $u.Ts -lt $cut }) | Out-Null
        Update-Window
        Test-WindowReset
        Test-WeekWarning
        Update-Look $script:Mood     # the lantern follows the window
    }
    Test-LateNight
    if ($script:Mood -eq 'sleep' -and $now -ge $script:NextDream) {
        if ($script:NextDream -ne [datetime]::MinValue) {
            $script:LastDream = Get-Dream $script:State $script:Recent $script:Rng (Test-Private)
            if ($script:LastDream.Ancestor) { (Get-CurrentRec $script:State.Lineage).AncestorDreamt = $true }
            Say $script:LastDream.Text 6 -Low
        }
        $script:NextDream = $now.AddSeconds($script:Rng.Next(50, 130))
    }
    if ($script:Mood -ne 'sleep') { $script:NextDream = [datetime]::MinValue }
    if (($now - $script:LastSave).TotalSeconds -ge 30) {
        Save-PetJson $script:State 'state.json'
        $fresh = Get-BodyConfig; $fresh.Follow = $script:Config.Follow; $script:Config = $fresh
        $script:LastSave = $now
    }

    $idle = ($now - $script:LastEvent).TotalSeconds
    $watch = Get-WatchSeconds $script:LastEvent $script:TurnOpen @($script:Subagents.Values | ForEach-Object { $_.Seen }) $now
    $mood = if ($script:ForcedMood) { $script:ForcedMood } else { Get-PetMood $script:State $script:Pct $idle $watch }
    if ($mood -eq 'busy' -and $now -lt $script:FastUntil) { $mood = 'zoom' }
    if ($mood -ne $script:Mood) {
        $pct = [math]::Round($script:Pct * 100)
        switch ($mood) {
            'stuffed' { Say "🏮 $(if (-not $script:WindowInfo.Real) { '~' })$pct% of the window.`nNearly full." 6 -Pin }
        }
        Update-Look $mood
        $script:Mood = $mood
    } elseif ($script:Override -and $now -ge $script:OverrideUntil) {
        $script:Override = $null
        Update-Look $mood
    }
}

# Real limits come from Claude Code's own cache (re-read only when ~/.claude.json changes);
# the estimate fills in when they're missing or out of date. See Get-WindowStatus.
$script:Limits = $null; $script:PlanLimit = $null; $script:LimitsStamp = [datetime]::MinValue
function Update-Window {
    $cfg = $script:ClaudeJson
    $stamp = if (Test-Path $cfg) { (Get-Item $cfg).LastWriteTimeUtc } else { [datetime]::MinValue }
    if ($stamp -ne $script:LimitsStamp) { $script:Limits = Get-UsageLimits $cfg; $script:PlanLimit = Get-PlanLimitUsd $cfg; $script:LimitsStamp = $stamp }
    # the freshest of: the live call (only while Exact usage is on), Claude Code's cache
    $live = if ($script:Config.LiveUsage -eq $true) { $script:LiveLimits }
    $best = Select-Limits @($live, $script:Limits)
    # the guess is measured against LimitUsd from config.json if there is one, else the plan's limit, else not at all
    $script:WindowInfo = Get-WindowStatus $script:Usage $best (Resolve-LimitUsd $script:Config.LimitUsd $script:PlanLimit)
    $script:Pct = $script:WindowInfo.Pct
    if (-not $PlayOnly -and -not $RenderDir) { Add-WeekRise $script:State $script:WindowInfo.Week }      # Today's "Used 9% of the week"
}

# Exact usage from Anthropic (Get-LiveUsage in lib\Transcripts.ps1), only while the Exact usage setting is on (off unless
# LiveUsage is true), fetched off the UI thread. Polled every 3 minutes
# while Claude is active and every 10 otherwise; after an error or a 429 it backs off 5, 10, 20, then 40 minutes. The last
# reading and the next allowed time are saved in live.json, so a restart reuses the reading and does not call again early.
$script:LiveLimits = $null; $script:LiveJob = $null; $script:LiveNext = [datetime]::MinValue; $script:LiveFailures = 0
$script:LiveOkLogged = $false; $script:LiveExpiredLogged = $false
$rec = ConvertFrom-LiveRecord (Read-PetJson 'live.json')
if ($rec) { $script:LiveLimits = $rec.Limits; $script:LiveNext = $rec.Next; $script:LiveFailures = $rec.Failures }
function Save-LiveState { Save-PetJson (ConvertTo-LiveRecord $script:LiveLimits $script:LiveNext $script:LiveFailures) 'live.json' }
function Step-LiveUsage {
    if ($script:Config.LiveUsage -ne $true -or $PlayOnly -or $RenderDir) { return }
    $now = [datetime]::UtcNow
    if ($script:LiveJob) {
        if (-not $script:LiveJob.Handle.IsCompleted) { return }
        $r = $null
        try { $r = @($script:LiveJob.PS.EndInvoke($script:LiveJob.Handle))[0] } catch { }
        $script:LiveJob.PS.Dispose(); $script:LiveJob = $null
        if ($r -and $r.FiveHour -and -not $r.Failed) {
            $recovered = $script:LiveFailures -gt 0
            $script:LiveLimits = $r; $script:LiveFailures = 0
            Update-Window
            if ($recovered -or -not $script:LiveOkLogged) { Write-BodyLog ("live usage: 5-hour {0}%, week {1}% (exact)" -f $r.FiveHour.Pct, $r.Week.Pct); $script:LiveOkLogged = $true }
            $active = ($now - $script:LastEvent).TotalMinutes -lt 15
            $script:LiveNext = $now.AddMinutes((Get-LivePollMinutes $active))
        } elseif ($r -and $r.Why -eq 'expired') {
            # the stored login has lapsed (Claude Code renews it the next time it runs): not a failure, so no backoff; look
            # at the file again in 2 minutes (no call is made until the login is fresh)
            if (-not $script:LiveExpiredLogged) { Write-BodyLog 'live usage: the login has expired; waiting for Claude Code to renew it'; $script:LiveExpiredLogged = $true }
            $script:LiveNext = $now.AddMinutes(2)
        } else {
            $script:LiveFailures++
            $mins = Get-LiveBackoffMinutes $script:LiveFailures
            $why = if ($r -and $r.Status) { "HTTP $($r.Status)" } elseif ($r -and $r.Why) { $r.Why } else { 'no answer' }
            Write-BodyLog "live usage: $why; backing off $mins min (failure $($script:LiveFailures))"
            $script:LiveNext = $now.AddMinutes($mins)
        }
        if ($r -and $r.Why -ne 'expired') { $script:LiveExpiredLogged = $false }
        Save-LiveState
        return
    }
    if ($now -lt $script:LiveNext) { return }
    $ps = [PowerShell]::Create()
    $null = $ps.AddScript(". '$(Join-Path $PSScriptRoot 'lib\Transcripts.ps1')'; Get-LiveUsage")
    $script:LiveJob = @{ PS = $ps; Handle = $ps.BeginInvoke() }
}

# A new 5-hour window means the tokens are back: a stretch once per window, and a word only when the window was nearly full.
# It fires when the clock passes the reset time Tok last knew about (not when the window's
# start moves, which happens whenever the estimate is replaced by the real numbers).
# $script:LastResetPct is how full the window was the last time it was still open: by the time the reset passes, the window
# Tok reads is already the new one.
$script:LastResetPct = 0.0
function Test-WindowReset {
    $w = $script:WindowInfo
    $now = [datetime]::UtcNow
    if ($script:LastReset -and $now -ge $script:LastReset) {
        if (-not $script:State.Coma) {
            Invoke-Reset; Invoke-Hop
            if (Test-FreshWindowBubble $script:LastResetPct) { Say (Get-FreshWindowLine) 4 }
        }
        Write-BodyLog "window reset at $($script:LastReset.ToLocalTime()) (was $([math]::Round($script:LastResetPct * 100))%)"
        $script:LastReset = $null
    }
    if ($w -and $w.Active -and $w.Reset -gt $now) { $script:LastReset = $w.Reset; $script:LastResetPct = $w.Pct }
}

# Once a night, if you're still working past 1am, say so (gently).
function Test-LateNight {
    $local = Get-Date
    if ($local.Hour -lt 1 -or $local.Hour -ge 5 -or $script:Mood -notin 'busy', 'zoom') { return }
    if (Test-Private) { return }                                  # silent in private mode
    if ([datetime]::UtcNow -lt $script:BubbleUntil -or $script:BubbleQueue.Count) { return }    # it never interrupts; try again next time
    $d = $local.ToString('yyyy-MM-dd')
    if ($script:State.NudgedDate -eq $d) { return }
    $script:State.NudgedDate = $d
    Say (Get-LateNightLine $local (Get-YourName)) 7 -Low      # just a note: no fake yawn, no dozing face
}

# The week running low (WHO.md row 4: warn before it runs out). Once per week, the first time the seven-day use reaches 90%;
# the week is keyed by its reset time and the key is saved in the state. A word and nothing else: no pip.
function Test-WeekWarning {
    $w = $script:WindowInfo
    if (-not $w -or -not $w.Week) { return }
    $key = Test-WeekWarn $w.Week "$($script:State.WeekWarnKey)" ([datetime]::UtcNow)
    if (-not $key) { return }
    $script:State.WeekWarnKey = $key
    Say (Get-WeekWarnLine $w.Week.Reset) 6 -Pin
    Save-PetJson $script:State 'state.json'
    Write-BodyLog "week warning: $([math]::Round($w.Week.Pct))% of the week, resets $(Get-WeekResetText $w.Week.Reset)"
}

# ---------------------------------------------------------------- menu + input
$menu = [Windows.Controls.ContextMenu]::new()
$menu.Resources = Get-MenuResources
# Stats · Today · Family | Settings ▸ | Pet | Goodbye
function Add-MenuItem([string]$Header, [scriptblock]$Action, [bool]$Check = $false, [bool]$Checked = $false, [string]$Hint = '', $To = $menu) {
    $mi = [Windows.Controls.MenuItem]@{ Header = (New-MenuHeader $Header $Hint); IsCheckable = $Check; IsChecked = $Checked }
    $mi.Add_Click($Action)
    $null = $To.Items.Add($mi)
    $mi
}
function Save-ConfigKey([string]$Key, $Value) { $script:Config[$Key] = $Value; $c = Get-BodyConfig; $c[$Key] = $Value; Save-PetJson $c 'config.json' }
$null = Add-MenuItem 'Stats' { $p = Get-StatsPanel $script:State $script:WindowInfo ($script:Config.LiveUsage -eq $true); Say (Get-PanelText $p) 9 -Pin -Panel -Rows $p }
$null = Add-MenuItem 'Today' { $p = Get-TodayPanel $script:State; Say (Get-PanelText $p) 9 -Pin -Panel -Rows $p }
$null = Add-MenuItem 'Family' {
    $lin = $script:State.Lineage
    if ($lin -and @($lin.Generations).Count) {
        $priv = Test-Private
        Say (Get-FamilyText $lin $script:State.BornUtc -Private:$priv) 12 -Pin -Panel -Rows @{ Kind = 'family'; Title = (Get-FamilyTitle $lin); Rows = @(Get-FamilyRows $lin $script:State.BornUtc -Private:$priv) }
    } else {
        $text = if ($lin) { Get-FamilyText $lin $script:State.BornUtc } elseif ($script:LineageJob) { "Still reading the old transcripts…`nAsk me again in a few seconds." } else { "No family yet." }
        Say $text 12 -Pin -Panel
    }
}
$null = $menu.Items.Add([Windows.Controls.Separator]::new())
$settings = [Windows.Controls.MenuItem]@{ Header = 'Settings' }
$null = $menu.Items.Add($settings)
$null = $settings.Items.Add((New-MenuLabel 'Chatter'))
$script:ChatterItems = foreach ($mode in @(@('chatty', 'Chatty', 'every tool call'), @('normal', 'Normal', 'the big moments'), @('quiet', 'Quiet', 'only when I need you'))) {
    $mi = Add-MenuItem $mode[1] {
        param($sender)
        foreach ($o in $script:ChatterItems) { $o.IsChecked = ($o -eq $sender) }
        Save-ConfigKey 'Chatter' $sender.Tag
    } $false ($script:Config.Chatter -eq $mode[0]) $mode[2] $settings
    $mi.Tag = $mode[0]
    $mi
}
$null = $settings.Items.Add([Windows.Controls.Separator]::new())
$script:SoundItem = Add-MenuItem 'Sound' {
    Save-ConfigKey 'Sound' $script:SoundItem.IsChecked
    if ($script:SoundItem.IsChecked) { Invoke-Chime 'done' -Force }
} $true ($script:Config.Sound -ne $false) 'a pip when Claude needs you or is done' $settings
$script:PrivateItem = Add-MenuItem 'Private mode' { Set-Private $script:PrivateItem.IsChecked 0 'menu' } $true (Test-Private) 'sunglasses on, no names in bubbles' $settings
$script:LiveItem = Add-MenuItem 'Exact usage' {
    $on = $script:LiveItem.IsChecked
    Save-ConfigKey 'LiveUsage' $on
    Update-Window      # the next slow tick polls if it is allowed to (never inside a backoff); nothing else is reset
    Write-BodyLog "exact usage: $(if ($on) { 'on' } else { 'off' })"
    Say $(if ($on) { "Okay. I'll ask Anthropic every few`nminutes, with Claude Code's login." } else { "Okay. Back to Claude Code's own`nnumbers, and my guess." }) 6 -Now
} $true ($script:Config.LiveUsage -eq $true) "real numbers from Anthropic,`nwith Claude Code's own login" $settings
$script:FollowItem = Add-MenuItem 'Follow the active app' { Save-ConfigKey 'Follow' $script:FollowItem.IsChecked } $true ([bool]$script:Config.Follow) 'sit in its corner' $settings
$script:StartupItem = Add-MenuItem 'Start with Windows' {
    try { Set-StartWithWindows $script:StartupItem.IsChecked $PSScriptRoot; Write-BodyLog "start with windows: $($script:StartupItem.IsChecked)" }
    catch { Write-BodyLog "start with windows failed: $($_.Exception.Message)"; $script:StartupItem.IsChecked = Test-StartWithWindows }
} $true (Test-StartWithWindows) 'a shortcut in your Startup folder' $settings
$null = $menu.Items.Add([Windows.Controls.Separator]::new())
$null = Add-MenuItem 'Pet' { Set-Override 'love' 2; Invoke-Hop; Say (Pick '♥', 'Hehe', 'That tickles.', 'Thank you.') 2 -Now }
$null = $menu.Items.Add([Windows.Controls.Separator]::new())
$null = Add-MenuItem 'Goodbye' { if (-not $PlayOnly) { Save-PetJson $script:State 'state.json' }; $window.Close() } -Hint 'close Tok'
$menu.Add_Opened({ $script:StartupItem.IsChecked = Test-StartWithWindows })   # someone may have removed the shortcut by hand
$window.ContextMenu = $menu

# Hover: one line of status, so a glance answers "what's it doing and how full is it".
# shown to the left of the window, so it never covers Tok's face
# The tooltip opens just above Tok and centred on it (not at the window's mid-height); the popup keeps itself on screen.
$script:Tip = [Windows.Controls.ToolTip]@{ Content = 'Tok'; Placement = 'Top'; PlacementTarget = $ui.Pet }
$window.ToolTip = $script:Tip
[Windows.Controls.ToolTipService]::SetPlacementTarget($window, $ui.Pet)
[Windows.Controls.ToolTipService]::SetPlacement($window, 'Top')
$script:Tip.Add_Opened({ $script:Tip.HorizontalOffset = ($ui.Pet.ActualWidth - $script:Tip.ActualWidth) / 2 })
$window.Add_ToolTipOpening({
    $w = $script:WindowInfo
    $name = if ($script:State.Lineage) { Get-LineageName $script:State.Lineage } else { 'Tok' }
    $doing = switch ($script:Mood) { 'busy' { 'working' } 'zoom' { 'working fast' } 'sleep' { 'napping' } 'coma' { "asleep until $(Get-WakeText)" } 'stuffed' { 'nearly full' } 'full' { 'filling up' } default { $script:Mood } }
    $belly = Get-BellyText $w
    $window.ToolTip.Content = "$(Get-WaitingText $script:WaitingSince ([datetime]::UtcNow))$name · $doing · $belly$(if (Test-Private) { ' · private' })"
})

# The bubble steps aside when the pointer reaches it (not a panel: he is reading that). Step-Bubble brings it back.
$ui.Bubble.Add_MouseEnter({
    if ($script:BubblePanel -or $script:BubbleAside) { return }
    $script:BubbleAside = $true
    $ui.Bubble.BeginAnimation([Windows.UIElement]::OpacityProperty, [Windows.Media.Animation.DoubleAnimation]::new(0, [TimeSpan]::FromMilliseconds(150)))
})

function Get-CursorDip { $p = [System.Windows.Forms.Cursor]::Position; [Windows.Point]::new($p.X / $script:Dpi, $p.Y / $script:Dpi) }
$window.Add_MouseLeftButtonDown({
    param($s, $e)
    if ($e.ClickCount -ge 2) { Set-Override 'love' 2; Invoke-Hop; Say (Pick '♥', 'Hehe', 'That tickles.', 'Thank you.') 2 -Now; return }
    $c = Get-CursorDip
    $script:Drag = @{ Start = $c; Left = $window.Left; Top = $window.Top; LastX = $c.X; Dir = 0; Flips = [System.Collections.Generic.List[datetime]]::new(); Moved = 0.0 }
    $null = $window.CaptureMouse()
})
$window.Add_MouseMove({
    if (-not $script:Drag) { return }
    $c = Get-CursorDip; $d = $script:Drag
    $window.Left = $d.Left + ($c.X - $d.Start.X); $window.Top = $d.Top + ($c.Y - $d.Start.Y)
    $d.Moved = [math]::Max($d.Moved, [math]::Abs($c.X - $d.Start.X) + [math]::Abs($c.Y - $d.Start.Y))
    $dx = $c.X - $d.LastX
    if ([math]::Abs($dx) -gt 6) {
        $dir = [math]::Sign($dx)
        if ($d.Dir -and $dir -ne $d.Dir) {
            $now = [datetime]::UtcNow
            $d.Flips.Add($now); $null = $d.Flips.RemoveAll([Predicate[datetime]] { param($t) ($now - $t).TotalSeconds -gt 1.2 })
            if ($d.Flips.Count -ge 4 -and $script:Override -ne 'dizzy') {
                Set-Override 'dizzy' 3.5
                Say (Pick 'Whoaaa', 'The room is spinning.', '@_@ Please stop.', 'Wheeee… ugh') 2.5 -Now
            }
        }
        $d.Dir = $dir; $d.LastX = $c.X
    }
})
$window.Add_MouseLeftButtonUp({
    if (-not $script:Drag) { return }
    $window.ReleaseMouseCapture()
    if ($script:Drag.Moved -gt 8 -and $script:Config.Follow) {
        $script:Config.Follow = $false; $script:FollowItem.IsChecked = $false
        Say "OK, I'll stay here. Right-click to follow again." 4 -Now
    }
    $script:Drag = $null
})

# ---------------------------------------------------------------- start
$window.Add_SourceInitialized({
    $h = [System.Windows.Interop.WindowInteropHelper]::new($window).Handle
    $ex = [Tok.Native]::GetWindowLong($h, -20)
    $null = [Tok.Native]::SetWindowLong($h, -20, $ex -bor 0x80)   # WS_EX_TOOLWINDOW: no Alt-Tab entry
    $script:Dpi = [Windows.PresentationSource]::FromVisual($window).CompositionTarget.TransformToDevice.M11
})

$work = [System.Windows.SystemParameters]::WorkArea
if ($X -ge 0) { $window.Left = $X; $window.Top = $Y } else { $c0 = Get-CornerPoint $work.Right ($work.Bottom + 16); $window.Left = $c0.X; $window.Top = $c0.Y }

# The startup scan reads ~24 hours of transcripts (the window chain needs a long gap to anchor on) (a few seconds), so it runs on
# a background runspace and is merged in by the slow loop when it finishes.
$script:ScanJob = $null; $script:LineageJob = $null
if (-not $PlayOnly) {
    $ps = [powershell]::Create()
    $null = $ps.AddScript({ param($lib) . $lib; Get-RecentUsage 24 }).AddArgument((Join-Path $PSScriptRoot 'lib\Transcripts.ps1'))
    $script:ScanJob = @{ PS = $ps; Handle = $ps.BeginInvoke() }
    # The family tree is built once from every transcript still on disk (~15 s), then kept up live.
    if (-not $script:State.Lineage -or -not $script:State.Lineage.ScannedUtc -or -not (Test-DaysTracked $script:State)) {
        $lp = [powershell]::Create()
        $null = $lp.AddScript({ param($a, $b) . $a; . $b; Get-LineageBackfill }).AddArgument((Join-Path $PSScriptRoot 'lib\Transcripts.ps1')).AddArgument((Join-Path $PSScriptRoot 'lib\Lineage.ps1'))
        $script:LineageJob = @{ PS = $lp; Handle = $lp.BeginInvoke() }
    }
}

function Step-LineageScan {
    if (-not $script:LineageJob -or -not $script:LineageJob.Handle.IsCompleted) { return }
    try {
        $lin = @($script:LineageJob.PS.EndInvoke($script:LineageJob.Handle))[0]
        $old = $script:State.Lineage
        if ($old -and $old.ScannedUtc) {
            # An older tree (before the per-day counts): keep it, which also keeps what has already aged off disk,
            # and take only the day counts and inherited tints from the scan.
            foreach ($k in @($lin.Versions.Keys)) {
                if (-not $old.Versions.ContainsKey($k)) { $old.Versions[$k] = $lin.Versions[$k]; continue }
                $old.Versions[$k].Days = $lin.Versions[$k].Days
                if ($lin.Versions[$k].Tint) { $old.Versions[$k].Tint = $lin.Versions[$k].Tint }
                if ($lin.Versions[$k].HatchDay -and -not $old.Versions[$k].HatchDay -and $k -notin @($old.Generations)) { $old.Versions[$k].HatchDay = $lin.Versions[$k].HatchDay }
            }
            if (@($old.Generations).Count -lt @($lin.Generations).Count) { $old.Generations = $lin.Generations }
            $old.Schema = 2
            $lin = $old
        }
        $script:State.Lineage = $lin
        $null = Step-Growth      # adopt the day-count stage quietly
        Save-PetJson $script:State 'state.json'
        Write-BodyLog "family tree built: $(@($lin.Generations) -join ', ')"
    } catch { Write-BodyLog "lineage scan failed: $_" }
    $script:LineageJob.PS.Dispose(); $script:LineageJob = $null
}
# The first bubbles (Get-FirstBubbles, lib\Pet.ps1), once ever: after the family scan has landed (or at once when none runs),
# three pinned bubbles, 7 s each with a 1.5 s gap, in place of the startup hello. Greeted is set and saved when the first shows.
# A needs-you or a turn ending drops the rest (GreetCancelled); they are never said again. They show in private mode and at any
# Chatter level: nothing private is in them.
$script:GreetPending = $false; $script:GreetCancelled = $false
function Step-Greeting {
    if (-not $script:GreetPending -or $script:LineageJob) { return }
    $script:GreetPending = $false
    $script:State.Greeted = $true
    Save-PetJson $script:State 'state.json'
    Write-BodyLog 'first bubbles'
    $lines = @(Get-FirstBubbles)
    Say $lines[0] 7 -Pin
    Start-Later 8500 { param($t) if (-not $script:GreetCancelled) { Say $t 7 -Pin } } @($lines[1])
    Start-Later 17000 { param($t) if (-not $script:GreetCancelled) { Say $t 7 -Pin } } @($lines[2])
}
function Step-Scan {
    if (-not $script:ScanJob -or -not $script:ScanJob.Handle.IsCompleted) { return }
    try {
        foreach ($u in $script:ScanJob.PS.EndInvoke($script:ScanJob.Handle)) { if ($script:UsageIds.Add($u.Id)) { $script:Usage.Add($u) } }
        Update-Window
        Write-BodyLog ("scan done: {0} messages, window {1:P0} ({2})" -f $script:Usage.Count, $script:Pct, $(if ($script:WindowInfo.Real) { 'real' } else { 'estimate' }))
    } catch { Write-BodyLog "startup scan failed: $_" }
    $script:ScanJob.PS.Dispose(); $script:ScanJob = $null
}

# Draws the window's current state to a transparent PNG (2x for stills, 1.5x for recordings).
function Save-Frame([string]$Path, [double]$Scale = 2, [switch]$Fixed) {
    # Draws the window as it looks now: 320x310, or taller while a big bubble has grown it (TopOff < 0). Compact is ignored.
    # -Fixed: always 320x310 (a recording's frames must all be one size).
    $extra = if ($Fixed) { 0.0 } else { [math]::Max(0.0, -$script:TopOff) }; $h = 310 + $extra
    $saved = $ui.Root.RenderTransform; $ui.Root.RenderTransform = [Windows.Media.Transform]::Identity
    $ui.Root.Measure([Windows.Size]::new(320, 310)); $ui.Root.Arrange([Windows.Rect]::new(0, 0, 320, 310)); $ui.Root.UpdateLayout()
    $dv = [Windows.Media.DrawingVisual]::new(); $dc = $dv.RenderOpen()
    $vb = [Windows.Media.VisualBrush]@{ Visual = $ui.Root; Stretch = 'None'; AlignmentX = 'Left'; AlignmentY = 'Top'; ViewboxUnits = 'Absolute'; ViewportUnits = 'Absolute'
                                        Viewbox = [Windows.Rect]::new(0, -$extra, 320, $h); Viewport = [Windows.Rect]::new(0, 0, 320, $h) }
    $dc.DrawRectangle($vb, $null, [Windows.Rect]::new(0, 0, 320, $h)); $dc.Close()
    $bmp = [Windows.Media.Imaging.RenderTargetBitmap]::new([int](320 * $Scale), [int]($h * $Scale), 96 * $Scale, 96 * $Scale, [Windows.Media.PixelFormats]::Pbgra32)
    $bmp.Render($dv)
    $enc = [Windows.Media.Imaging.PngBitmapEncoder]::new(); $enc.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bmp))
    $fs = [IO.File]::Create($Path); $enc.Save($fs); $fs.Dispose()
    $ui.Root.RenderTransform = $saved
}

# Pretend subagents, for the minion demo and the renders (never touches transcripts).
function Add-FakeSubagent([string]$Key, [string]$Model, [string]$Tool, [string]$Desc, [double]$Tokens = 0) {
    $now = [datetime]::UtcNow
    if (-not $Tokens) { $Tokens = 20000 + $script:Rng.Next(160000) }
    $script:Subagents[$Key] = @{ First = $now; Seen = $now; Model = $Model; Tool = $Tool; Done = $false; Desc = $Desc; M = $null; Tokens = $Tokens }
}

if ($RenderDir) {
    $null = New-Item -ItemType Directory -Force $RenderDir
    $script:NoMotion = $true      # stills: no half-started sways
    $script:State.WakeUtc = [datetime]::Today.AddHours(14).AddMinutes(10).ToUniversalTime().ToString('o')
    $script:State.Coma = $false
    $i = 0
    function Save-Look([string]$Stage, [string]$Mood, [string]$Text, [double]$Pct = 0.05, [string]$Name = '') {
        $script:ForcedStage = $Stage; $script:Pct = $Pct; $script:Mood = ''; $script:Override = $null
        Update-Look $Mood; $script:Mood = $Mood
        if ($Text) { Show-BubbleText $Text $($Text -match "`n.*`n"); $ui.Bubble.Opacity = 1 } else { $ui.Bubble.Visibility = 'Collapsed' }
        Save-Frame (Join-Path $RenderDir ('{0:D2}-{1}.png' -f $script:RenderN, $(if ($Name) { $Name } else { "$Stage-$Mood" })))
        $script:RenderN++
    }
    $script:RenderN = 0
    Save-Look 'egg' 'egg' (Get-EggLine)
    Save-Look 'hatchling' 'happy' 'Hello!' 0.05
    Save-Look 'kid' 'busy' '✎ tok.ps1' 0.05
    Save-Look 'adult' 'happy' 'Hi! Tok II here.' 0.05 'adult-rest'
    Save-Look 'adult' 'busy' '⌁ Run the test suite' 0.05 'adult-working'
    Save-Look 'adult' 'happy' '' 0.3 'adult-25'
    Save-Look 'adult' 'happy' '' 0.55 'adult-50'
    Save-Look 'adult' 'full' '🏮 78% of the window.' 0.78 'adult-75'
    Save-Look 'adult' 'stuffed' "🏮 92% of the window.`nNearly full." 0.92 'adult-90'
    Save-Look 'adult' 'coma' "🌙 Window's all used up. Asleep until 2:10." 1.0 'adult-limit'
    Save-Look 'adult' 'needs' "❓ A question for you`n(tok)" 0.3 'adult-needs-you'
    Save-Look 'adult' 'sleep' '💭 …A giant Bash was chasing me…' 0.55 'adult-sleep'
    Save-Look 'adult' 'hungry' '…Hungry. Got any tokens?' 0.05
    Save-Look 'adult' 'dizzy' '…Wait, where was I?' 0.3
    Save-Look 'adult' 'rethink' '↺ Changed my mind.' 0.3
    Save-Look 'adult' 'fan' '' 0.3 'adult-fan-out'
    Save-Look 'adult' 'skill' '📚 Skill: artifact-design' 0.3 'adult-skill'
    Save-Look 'adult' 'zoom' '↯ Fast mode! Zoom zoom.' 0.3
    Save-Look 'elder' 'love' '♥' 0.3
    # the look sheet for the lantern / age / nightcap port (tools\sheet.ps1 over the 'life-' files)
    $script:ForcePumpkin = $false
    Save-Look 'egg' 'egg' '' 0.05 'life-0-egg'
    foreach ($st in 'hatchling', 'kid', 'adult', 'elder') { Save-Look $st 'happy' '' 0.3 "life-1-$st-rest" }
    foreach ($pc in 5, 50, 90) { Save-Look 'adult' 'happy' "$pc% of the window" ($pc / 100) "life-2-lantern-$pc" }
    $script:State.WakeUtc = [datetime]::UtcNow.AddHours(2).ToString('o')
    foreach ($st in 'hatchling', 'kid', 'adult', 'elder') { Save-Look $st 'coma' '' 1.0 "life-3-$st-nightcap" }
    $script:Config.Private = $true; Save-Look 'elder' 'busy' '' 0.3 'life-4-elder-private'; $script:Config.Private = $false
    Save-Look 'elder' 'sleep' '' 0.3 'life-4-elder-dozing'
    # the reset: the cap comes off and Tok stretches
    $script:ForcedStage = 'adult'; $script:Pct = 0.0; $script:Mood = ''; Update-Look 'stretch'
    Show-BubbleText (Get-FreshWindowLine); $ui.Bubble.Opacity = 1
    Save-Frame (Join-Path $RenderDir ('{0:D2}-adult-reset.png' -f $script:RenderN)); $script:RenderN++
    $script:ForcePumpkin = $true; Save-Look 'adult' 'happy' '🎃 Happy Halloween!' 0.55 'adult-pumpkin'; $script:ForcePumpkin = $false
    $script:Config.Private = $true; Save-Look 'adult' 'busy' (Get-PrivateToolLine 'Edit') 0.3 'adult-private'; $script:Config.Private = $false
    # the stranger's session (parliament session 6): the three first bubbles, the permission bubble, Stats under a guess and with no reading
    $fb = @(Get-FirstBubbles)
    for ($n = 0; $n -lt 3; $n++) { Save-Look 'adult' 'happy' $fb[$n] 0.3 "first-bubble-$($n + 1)" }
    Save-Look 'adult' 'needs' (Get-HookNeedsPlan 'permission_prompt' 'Claude needs your permission to use Bash' $false 3).Line 0.3 'permission-bash'
    Save-Look 'adult' 'needs' (Get-HookNeedsPlan 'permission_prompt' 'x' $false 3 $true).Line 0.3 'permission-private'
    $soon = [datetime]::UtcNow.AddHours(2)
    foreach ($case in @(@('stats-guess', [pscustomobject]@{ Active = $true; Real = $false; NoReading = $false; Pct = 0.42; Reset = $soon; Week = $null }),
                        @('stats-no-reading', [pscustomobject]@{ Active = $false; Real = $false; NoReading = $true; Pct = 0.0; Reset = $null; Week = $null }))) {
        Save-Look 'adult' 'happy' '' 0.3 'scratch'; Remove-Item (Join-Path $RenderDir ('{0:D2}-scratch.png' -f ($script:RenderN - 1))); $script:RenderN--
        $p = Get-StatsPanel $script:State $case[1] $false
        Show-BubbleText (Get-PanelText $p) $true $p; $ui.Bubble.Opacity = 1
        Save-Frame (Join-Path $RenderDir ('{0:D2}-{1}.png' -f $script:RenderN, $case[0])); $script:RenderN++
    }
    # One of each minion, posed: two in front of Tok, two behind.
    Save-Look 'adult' 'busy' '' 0.3 'scratch'; Remove-Item (Join-Path $RenderDir ('{0:D2}-scratch.png' -f ($script:RenderN - 1))); $script:RenderN--
    Add-FakeSubagent 'h' 'claude-haiku-4-5' 'Grep' 'find TODOs' 41000
    Add-FakeSubagent 's' 'claude-sonnet-5-5' 'Read' 'review tok.ps1' 143000
    Add-FakeSubagent 'o' 'claude-opus-5-5' 'Edit' 'design the minions' 212000
    Add-FakeSubagent 'f' 'claude-fable-5-1' 'Bash' 'run the tests' 18000
    Step-Minions
    $targets = @{ haiku = 0.75; sonnet = 2.35; opus = 3.75; fable = 5.55; other = 5.55 }
    foreach ($m in $script:Minions) { $m.Angle = $targets[$m.Kind.Name] - 16 * $m.Kind.Speed }
    for ($t = 0; $t -lt 16; $t++) { $script:Tick++; Step-Minions }
    Show-BubbleText '🐣 Sending a minion: design the minions'; $ui.Bubble.Opacity = 1
    Save-Frame (Join-Path $RenderDir ('{0:D2}-adult-minions.png' -f $script:RenderN)); $script:RenderN++
    # A mouthful, one frame per beat: the token arrives, the chew, the swallow dropping into the lantern, the ripple.
    foreach ($beat in @(@(0.4, 'eat-1-arrives'), @(1.1, 'eat-2-chew'), @(2.25, 'eat-3-swallow'), @(2.7, 'eat-4-ripple'))) {
        $script:Meal = $null; Start-Meal -Force; $script:Meal.Start = [datetime]::UtcNow.AddSeconds(-$beat[0]); Step-Meal
        Save-Frame (Join-Path $RenderDir ('{0:D2}-{1}.png' -f $script:RenderN, $beat[1])); $script:RenderN++
    }
    $script:Meal = $null; $script:Override = $null; Show-LanternRipple 1; Set-LanternPulse $false; $ui.MealTok.Visibility = 'Collapsed'; Update-Look 'busy'
    # A minion coming home: it flies to the lantern, pours, and tucks into the sprout (the Sonnet one).
    $sn = $script:Minions | Where-Object { $_.Kind.Name -eq 'sonnet' }
    foreach ($beat in @(@(0.3, 'home-1-flies'), @(1.3, 'home-2-pours'), @(2.0, 'home-3-rises'))) {
        $sn.Eat = 0.001; $sn.HomeAt = [datetime]::UtcNow.AddSeconds(-$beat[0]); $sn.HomeFrom = Get-OrbitPoint $sn.Angle $sn.Kind
        Step-Minions
        Show-BubbleText '✓ “review tok.ps1” is done.'; $ui.Bubble.Opacity = 1
        Save-Frame (Join-Path $RenderDir ('{0:D2}-{1}.png' -f $script:RenderN, $beat[1])); $script:RenderN++
    }
    $script:Override = $null; $script:HomeFace = ''; Show-LanternRipple 0; Set-LanternPulse $false
    # A minion that hatched before its model was known is orange; the model arriving recolours it.
    Add-FakeSubagent 'x' 'claude-unknown' 'Read' 'late model' 1000; $script:Subagents['x'].Model = $null; $script:Subagents['x'].First = [datetime]::UtcNow.AddSeconds(-10)
    Step-Minions; $lm = $script:Subagents['x'].M; $before = $lm.Kind.Name
    $script:Subagents['x'].Model = 'claude-haiku-4-5'; Step-Minions
    Write-Host "late model: $before -> $($lm.Kind.Name), size $($lm.Kind.Size)"
    foreach ($d in 1..4) { $ui["MealDrop$d"].Visibility = 'Collapsed' }
    foreach ($m in @($script:Minions)) { Remove-Minion $m }
    foreach ($p in @($script:Particles)) { $p.Layer.Children.Remove($p.El) }; $script:Particles.Clear()
    foreach ($c in $ui.CheekLPuff, $ui.CheekRPuff) { $c.ScaleX = 1; $c.ScaleY = 1 }
    # The two right-click panels, with made-up numbers.
    $script:Override = $null; $script:Mood = ''; Update-Look 'happy'
    $fake = New-PetState; $fake.Xp = 328; $fake.Tokens = 42.8e6
    $ft = Get-Today $fake; $ft.Prompts = 55; $ft.Done = 121; $ft.Errors = 17; $ft.Tokens = 36.8e6
    $ft.Tools = @{ Bash = 93; Edit = 58; 'mcp__claude_ai_Notion__notion-update-page' = 70; Read = 40 }
    $ft.Out = 1.24e6; $ft.WeekRise = 9.0; $ft.Since = [datetime]::Today.AddHours(8).AddMinutes(12).ToUniversalTime().ToString('o')
    $fw = [pscustomobject]@{ Active = $true; Real = $true; Pct = 0.31; Reset = [datetime]::UtcNow.Date.AddHours(19).AddMinutes(10); AsOf = [datetime]::UtcNow.AddMinutes(-6)
                             Week = @{ Pct = 54; Reset = [datetime]::UtcNow.Date.AddDays(4).AddHours(14) } }
    $panelFrame = { param($P, [string]$Name) Show-BubbleText (Get-PanelText $P) $true $P; $ui.Bubble.Opacity = 1; Save-Frame (Join-Path $RenderDir ('{0:D2}-{1}.png' -f $script:RenderN, $Name)); $script:RenderN++ }
    & $panelFrame (Get-StatsPanel $fake $fw) 'adult-stats'
    # pace (P1): two hours into a window that is already 60% used, so the line shows
    & $panelFrame (Get-StatsPanel $fake ([pscustomobject]@{ Active = $true; Real = $true; Pct = 0.6; Reset = [datetime]::UtcNow.AddHours(3); AsOf = [datetime]::UtcNow; Week = @{ Pct = 14; Reset = [datetime]::UtcNow.AddDays(6) } })) 'stats-pace'
    & $panelFrame (Get-TodayPanel $fake) 'adult-today'
    # the other Stats states: an estimate, no window open, no reading at all
    & $panelFrame (Get-StatsPanel $fake ([pscustomobject]@{ Active = $true; Real = $false; Pct = 0.42; Reset = $fw.Reset })) 'stats-estimate'
    & $panelFrame (Get-StatsPanel $fake ([pscustomobject]@{ Active = $false; Real = $true; AsOf = [datetime]::UtcNow; Week = $fw.Week })) 'stats-no-window'
    # Family with three generations (made up): the tallest a panel gets
    $f3 = New-Lineage; $d3 = [datetime]::UtcNow.Date.AddDays(-80)
    foreach ($g in @(@('claude-opus-5', 0, 6, 'home'), @('claude-opus-5-5', 10, 34, 'tok'), @('claude-fable-5-1', 50, 12, 'my-project'))) {
        for ($dd = 0; $dd -lt $g[2]; $dd++) { for ($q = 0; $q -lt 12; $q++) { $null = Add-LineageReply $f3 $g[0] $d3.AddDays($g[1] + $dd).AddHours(15).AddMinutes($q) 10 $g[3] } }
    }
    & $panelFrame @{ Kind = 'family'; Title = (Get-FamilyTitle $f3); Rows = @(Get-FamilyRows $f3 $d3.AddDays(20).ToString('o')) } 'family-three'
    # The right-click menu and its Settings submenu, opened for real (they flash in the screen's corner) and drawn to PNGs.
    $pump = { $window.Dispatcher.Invoke([Action] {}, [Windows.Threading.DispatcherPriority]::ContextIdle) }
    $saveVisual = {
        param($v, [string]$Name)
        $v.UpdateLayout(); $w = [math]::Ceiling($v.ActualWidth); $h = [math]::Ceiling($v.ActualHeight)
        $bmp = [Windows.Media.Imaging.RenderTargetBitmap]::new([int]($w * 2), [int]($h * 2), 192, 192, [Windows.Media.PixelFormats]::Pbgra32)
        $bmp.Render($v)
        $enc = [Windows.Media.Imaging.PngBitmapEncoder]::new(); $enc.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bmp))
        $fs = [IO.File]::Create((Join-Path $RenderDir ('{0:D2}-{1}.png' -f $script:RenderN, $Name))); $enc.Save($fs); $fs.Dispose(); $script:RenderN++
    }
    $menu.Placement = 'AbsolutePoint'; $menu.HorizontalOffset = 0; $menu.VerticalOffset = 0; $menu.IsOpen = $true; & $pump
    & $saveVisual $menu 'menu'
    $settings.IsSubmenuOpen = $true; & $pump; & $pump
    & $saveVisual $settings.Template.FindName('PART_Popup', $settings).Child 'menu-settings'
    $menu.IsOpen = $false; & $pump
    # Phase 3, age is days together: the real tree (the one in state.json, or else built from every transcript still on disk),
    # its Stats with the last real usage reading (live.json) and Family bubbles, and Tok at the stage those days give it
    # (tools\sheet.ps1 over the 'p3-' files makes life\code\p3-sheet.png).
    $real = if ($script:State.Lineage -and @($script:State.Lineage.Generations).Count) { $script:State.Lineage } else { try { Get-LineageBackfill } catch { $null } }
    $lv = (ConvertFrom-LiveRecord (Read-PetJson 'live.json')).Limits
    if ($lv -and $lv.FiveHour) {
        $fw = [pscustomobject]@{ Active = $lv.FiveHour.Reset -gt [datetime]::UtcNow; Real = $true; Pct = $lv.FiveHour.Pct / 100; Reset = $lv.FiveHour.Reset; AsOf = $lv.FetchedUtc; Week = $lv.Week }
    }
    if ($real -and @($real.Generations).Count) {
        $rs = New-PetState; $rs.Lineage = $real; $rs.Tokens = [long]$script:State.Tokens; $rs.Comas = 0
        $rs.BornUtc = $script:State.BornUtc
        $rstage = (Get-PetStage $rs).Name
        Write-Host "p3: $(Get-LineageName $real) has $(Get-GenDays $rs) days together -> $rstage"
        & $panelFrame (Get-StatsPanel $rs $fw) 'p3-stats'
        & $panelFrame @{ Kind = 'family'; Title = (Get-FamilyTitle $real); Rows = @(Get-FamilyRows $real $rs.BornUtc) } 'p3-family'
        Save-Look $rstage 'happy' "Hi! $(Get-LineageName $real) here." 0.3 "p3-tok-$rstage"
    }
    # The meter across a window, into a subfolder (tools\sheet.ps1 -Dir ...\meter -Cols 6 makes a strip).
    $meterDir = Join-Path $RenderDir 'meter'; $null = New-Item -ItemType Directory -Force $meterDir
    $j = 0
    foreach ($b in @(@(0.05, 'happy', 'Fresh window'), @(0.3, 'happy', '25%'), @(0.55, 'happy', '50%'),
                     @(0.78, 'full', '75%'), @(0.92, 'stuffed', '90%'), @(1.0, 'coma', 'Limit'))) {
        $script:ForcedStage = 'adult'; $script:Pct = $b[0]; $script:Mood = ''; Update-Look $b[1]
        Show-BubbleText $b[2]; $ui.Bubble.Opacity = 1
        Save-Frame (Join-Path $meterDir ('{0:D2}-{1}.png' -f $j, ($b[2] -replace '[ %]', '').ToLower())); $j++
    }
    Write-Host "rendered $($script:RenderN) looks (+ the meter) to $RenderDir"
    return
}

# Recording: every 2nd tick (10 fps) the window is saved as a PNG frame. Started by -RecordDir,
# or for the running body by dropping record.json ({"dir": "...", "seconds": 20}) in its data folder.
$script:Rec = $null
function Start-Recording([string]$Dir, [double]$Seconds) {
    $null = New-Item -ItemType Directory -Force $Dir
    $script:Rec = @{ Dir = $Dir; Left = [int]($Seconds * 10); N = 0 }
    Write-BodyLog "recording $Seconds s to $Dir"
}
function Step-Recording {
    if (-not $script:Rec) {
        $trigger = Join-Path $DataDir 'record.json'
        if ($script:Tick % 20 -eq 0 -and (Test-Path $trigger)) {
            try { $r = Get-Content $trigger -Raw | ConvertFrom-Json; Remove-Item $trigger; Start-Recording $r.dir ([double]($r.seconds ?? 20)) }
            catch { Write-BodyLog "record trigger: $_" }
        }
        return
    }
    if ($script:Tick % 2 -ne 0) { return }
    if ((Test-Private) -and -not $Showcase) { Set-Content (Join-Path $script:Rec.Dir 'done.txt') 'private'; Write-BodyLog 'recording stopped: private mode'; $script:Rec = $null; return }
    Save-Frame (Join-Path $script:Rec.Dir ('frame_{0:D4}.png' -f $script:Rec.N)) 1.5 -Fixed
    $script:Rec.N++; $script:Rec.Left--
    Sync-PassingClock
    if ($script:Rec.Left -le 0) {
        Set-Content (Join-Path $script:Rec.Dir 'done.txt') $script:Rec.N
        Write-BodyLog "recorded $($script:Rec.N) frames"
        $script:Rec = $null
    }
}
if ($RecordDir) { Start-Recording $RecordDir $RecordSeconds }

# A made-up molt for the tour, -Demo and -Molt: the plan only, nothing in the state changes (a play-only window never saves it).
# Opus 6 is the pretend new model; the name is the next one on the real family tree; an elder hands its flower colour on.
function Get-DemoMoltPlan([string]$StageBefore) {
    $lin = $script:State.Lineage
    $name = if ($lin -and @($lin.Generations).Count) { Get-NextLineageName $lin } else { 'Tok II' }
    Get-MoltPlan $StageBefore 'claude-opus-6' $name $(if ($StageBefore -eq 'elder') { $script:ElderTint } else { '' }) $true
}

$fast = [Windows.Threading.DispatcherTimer]::new()
$fast.Interval = [TimeSpan]::FromMilliseconds(50)
# The loop runs 20x a second only while something moves (minions, chewing, a hop, the window catching up,
# your pointer while Tok is awake). Otherwise it drops to 4x a second, stepping Tick by 5 so every
# "every N ticks" check keeps its timing.
$script:LastCursor = $null; $script:CursorMovedAt = [datetime]::MinValue
function Test-NeedsFastTick {
    if ($script:Minions.Count -or $script:Particles.Count -or $script:Override -or $script:Rec -or $script:Meal -or $script:Passing) { return $true }
    if ($script:ReadSweep -and ([datetime]::UtcNow - $script:ReadSweep.Start).TotalSeconds -lt $script:ReadSweepSeconds) { return $true }      # the reading sweep, only while it runs
    if ($null -ne $script:LanternShown -and [math]::Abs($script:LanternTarget - $script:LanternShown) -ge 0.004) { return $true }
    if ($script:Config.Follow -and $script:Target -and ([math]::Abs((Get-MinionRoomX $script:Target.X ($script:Minions.Count -gt 0) $script:TargetLeft) - $window.Left) + [math]::Abs($script:Target.Y + $script:TopOff - $window.Top)) -ge 1) { return $true }
    if ($script:Mood -in 'sleep', 'coma', 'egg') { return $false }
    $p = [System.Windows.Forms.Cursor]::Position
    $now = [datetime]::UtcNow
    if ($null -eq $script:LastCursor -or $p.X -ne $script:LastCursor.X -or $p.Y -ne $script:LastCursor.Y) { $script:LastCursor = $p; $script:CursorMovedAt = $now }
    ($now - $script:CursorMovedAt).TotalSeconds -lt 1.5
}
$script:SlowTick = $false
$fast.Add_Tick({
    try {
        $wantFast = Test-NeedsFastTick
        if ($wantFast -and $script:SlowTick) { $script:SlowTick = $false; $fast.Interval = [TimeSpan]::FromMilliseconds(50) }
        elseif (-not $wantFast -and -not $script:SlowTick -and $script:Tick % 5 -eq 0) { $script:SlowTick = $true; $fast.Interval = [TimeSpan]::FromMilliseconds(250) }
        $script:Tick += $(if ($script:SlowTick) { 5 } else { 1 })
        Step-Move; Step-Eyes; Step-Lantern; Step-Meal; Step-Passing
        if ($script:Minions.Count -or $script:Subagents.Count -or $script:Particles.Count -or $script:Override) { Step-Minions }
        Step-Bubble
        if ($script:Tick % 15 -eq 0 -and -not $PlayOnly) { Step-Scan; Step-LineageScan; Step-Life }
        Step-Recording
    } catch { Write-BodyLog "tick: $_ $($_.ScriptStackTrace)" }
})

if ($Demo) {
    $script:Config.Follow = $false
    $script:DemoSteps = @(
        @{ S = 'egg'; M = 'egg'; T = 'An egg' }, @{ S = 'hatchling'; M = 'happy'; T = 'Hello!' },
        @{ S = 'kid'; M = 'busy'; T = '✎ tok.ps1' }, @{ S = 'adult'; M = 'happy'; T = 'Adult, fresh window' },
        @{ S = 'adult'; M = 'happy'; T = '🏮 25%'; P = 0.3 }, @{ S = 'adult'; M = 'happy'; T = '🏮 50%'; P = 0.55 },
        @{ S = 'adult'; M = 'full'; T = '🏮 75%'; P = 0.78 }, @{ S = 'adult'; M = 'stuffed'; T = '🏮 85%: nearly full'; P = 0.88 },
        @{ S = 'adult'; M = 'coma'; T = "🌙 Asleep until the reset"; P = 1.0 }, @{ S = 'adult'; M = 'needs'; T = '❓ A question for you' },
        @{ S = 'adult'; M = 'sleep'; T = 'zzz'; P = 0.55 }, @{ S = 'adult'; M = 'hungry'; T = '…Hungry. Got any tokens?' },
        @{ S = 'elder'; M = 'love'; T = 'Elder ♥' }, @{ S = 'elder'; M = 'happy'; T = '✨ A new model: the elder passes on.'; Piece = 1 },
        @{ S = 'kid'; M = 'happy'; T = '…A younger Tok curls up instead.'; Piece = 1 }, @{ S = 'adult'; M = 'zoom'; T = '↯ Fast mode! Zoom zoom.' },
        @{ S = 'adult'; M = 'dizzy'; T = 'Chat compacted. I kept the gist.' }, @{ S = 'adult'; M = 'rethink'; T = '↺ Changed my mind.' }
    )
    $script:DemoIndex = -1
    $demoTimer = [Windows.Threading.DispatcherTimer]::new()
    $demoTimer.Interval = [TimeSpan]::FromSeconds(2.5)
    $demoTimer.Add_Tick({
        if ($script:Passing) { return }      # a set piece plays out before the next look
        $script:DemoIndex = ($script:DemoIndex + 1) % $script:DemoSteps.Count
        $d = $script:DemoSteps[$script:DemoIndex]
        $script:ForcedStage = $d.S
        if ($d.M -eq 'coma') { $script:State.WakeUtc = [datetime]::UtcNow.AddHours(2).ToString('o') }
        $script:Pct = if ($d.P) { $d.P } else { 0.05 }
        $script:Override = $null; $script:Mood = ''; Update-Look $d.M; $script:Mood = $d.M
        Say $d.T 2.4 -Now
        if ($d.Piece) { $null = Start-Passing (Get-DemoMoltPlan $d.S) 'hatchling' }
        Write-Host "DEMO $($script:DemoIndex) $($d.S)/$($d.M)"
    })
    $demoTimer.Start()
} elseif ($Showcase) {
    # A narrated tour of everything Tok does, on a timeline (seconds). Nothing here touches the real Tok's state.
    $script:Config.Follow = $false
    $script:State.Coma = $false
    $script:ForcedStage = 'egg'; $script:Pct = 0.05; Update-Look 'egg'; $script:Mood = 'egg'
    $script:ShowT = 0.0
    function Set-ShowLook([string]$Stage, [string]$Mood, [double]$Pct) {
        $script:ForcedStage = $Stage; $script:Pct = $Pct; $script:Override = $null; $script:Mood = ''; Update-Look $Mood; $script:Mood = $Mood
    }
    # The week line's reset: next Friday 9 AM (a sample).
    $script:ShowWeekReset = [datetime]::Today.AddDays((5 - [int][datetime]::Today.DayOfWeek + 7) % 7).AddHours(9).ToUniversalTime()
    # Pips play here (-Force: a play-only window is otherwise silent), each on its motion, as live.
    $script:ShowPlan = @(
        @(0.3,  { Say (Get-EggLine) 3 -Now }),
        @(3.0,  { Set-ShowLook 'hatchling' 'happy' 0.05; Invoke-Hop; Say "Hello! I'm Tok." 3 -Now }),
        @(6.0,  { Set-ShowLook 'adult' 'happy' 0.05; Invoke-Hop; Say "I'm Claude, with a body. I live in the corner of your screen." 4.5 -Now }),
        @(11.0, { Set-ShowLook 'adult' 'busy' 0.05; Say '✻ When Claude works, I think.' 3.5 -Now }),
        @(14.5, { $script:LastSweep = [datetime]::MinValue; Start-ReadSweep; Say '👀 When it reads, my eyes follow the lines.' 3.5 -Now }),
        @(18.5, { Invoke-Nod; Say '✎ Then a small nod, and it writes.' 3 -Now }),
        @(22.0, { Set-ShowLook 'adult' 'happy' 0.3; Say '🏮 My belly is your 5-hour window. This is 25%.' 4 -Now }),
        @(26.0, { Set-ShowLook 'adult' 'happy' 0.55 }),
        @(29.5, { Set-ShowLook 'adult' 'full' 0.78; Say '🏮 75%.' 3 -Now }),
        @(33.0, { Set-ShowLook 'adult' 'stuffed' 0.88; Say '🏮 85%: nearly full. I warn you here.' 4.5 -Now }),
        @(38.0, { $script:State.WakeUtc = [datetime]::UtcNow.AddHours(2).ToString('o'); Set-ShowLook 'adult' 'coma' 1.0
                  Say "🌙 All used up. I nap under my cap until the reset." 4.5 -Now }),
        @(43.5, { Set-ShowLook 'adult' 'happy' 0.05; Invoke-Reset; Invoke-Hop; Invoke-Chime 'wake' -Force; Say (Get-FreshWindowLine) 4.5 -Now }),
        @(49.0, { Set-ShowLook 'adult' 'busy' 0.3; Add-FakeSubagent 'h' 'claude-haiku-4-5' 'Grep' 'find TODOs' 41000; Say 'Each subagent is a helper seed. A Haiku.' 2 -Now }),
        @(51.0, { Add-FakeSubagent 's' 'claude-sonnet-5-5' 'Read' 'review tok.ps1' 143000; Say 'A Sonnet.' 2 -Now }),
        @(53.0, { Add-FakeSubagent 'o' 'claude-opus-5-5' 'Edit' 'design the minions' 212000; Say 'An Opus.' 2 -Now }),
        @(55.0, { Add-FakeSubagent 'f' 'claude-fable-5-1' 'Bash' 'run the tests' 18000; Say 'A Fable. They orbit while they work.' 3.5 -Now }),
        @(59.0, { $script:Subagents['h'].Done = $true; Say '🍯 Done, they fly home and pour into the lantern.' 4 -Now }),
        @(62.0, { $script:Subagents['s'].Done = $true }),
        @(65.0, { $script:Subagents['f'].Done = $true }),
        @(68.0, { $script:Subagents['o'].Done = $true }),
        @(72.0, { Set-ShowLook 'adult' 'happy' 0.3; Invoke-NeedsYou; Invoke-Chime 'needs' -Force; Say '❓ When Claude needs you, I wave and look right at you.' 5 -Now }),
        @(78.0, { Set-ShowLook 'adult' 'busy' 0.3; Say 'When a long turn ends, I hop and tell you.' 3.5 -Now }),
        @(81.5, { Set-ShowLook 'adult' 'happy' 0.3; $end = Get-TurnEndPlan $true $false '' $false; Invoke-Hop; Say $end.Text 4 -Now
                  Invoke-Chime 'done' -Force -DelayMs (Get-HopSpec 'adult' $false).FallMs }),
        @(86.0, { Set-ShowLook 'adult' 'busy' 0.3; Set-Override 'rethink' 2; Say '↺ When Claude changes its mind, so do I.' 3.5 -Now }),
        @(90.0, { Set-ShowLook 'adult' 'happy' 0.3; Start-DayStretch; Say '✦ When today counts as a day together, I stretch.' 4 -Now }),
        @(94.5, { Set-ShowLook 'adult' 'sleep' 0.55; Say '💭 Idle: my leaves fold and I doze. I dream about your day.' 4.5 -Now }),
        @(99.5, { Set-ShowLook 'adult' 'happy' 0.3; Set-Override 'dizzy' 2.5; Say 'Chat compacted. I kept the gist.' 3 -Now }),
        @(103.0, { Set-Override 'love' 2.5; Invoke-Hop; Say '♥ Say thanks and I blush.' 2.5 -Now }),
        @(106.0, { Set-ShowLook 'adult' 'zoom' 0.3; Say '↯ Fast mode: zoom zoom.' 2.5 -Now }),
        @(109.5, { $script:Config.Private = $true; Set-ShowLook 'adult' 'busy' 0.3; Say '🕶 Private mode: no details, sunglasses on.' 3 -Now }),
        @(113.0, { $script:Config.Private = $false; Set-ShowLook 'adult' 'happy' 0.3; Say (Get-WeekWarnLine $script:ShowWeekReset) 4 -Now }),
        @(117.5, { $script:ForcePumpkin = $true; Set-ShowLook 'adult' 'happy' 0.55; Say '🎃 On Halloween, a little pumpkin.' 3 -Now }),
        @(121.0, { $script:ForcePumpkin = $false; Set-ShowLook 'elder' 'love' 0.55; Say 'After 30 days together: an elder.' 3 -Now }),
        @(124.5, { Set-ShowLook 'elder' 'happy' 0.3; Say '✨ A new model arrives. The elder passes on.' 3 -Now; $null = Start-Passing (Get-DemoMoltPlan 'elder') 'hatchling' }),
        @(139.0, { Set-ShowLook 'kid' 'busy' 0.3; Say '✨ A younger Tok just curls up into the egg.' 3 -Now; $null = Start-Passing (Get-DemoMoltPlan 'kid') 'hatchling' }),
        @(151.5, { Set-ShowLook 'adult' 'happy' 0.05; Invoke-Hop; Say '🌱 That is me now. The Parliament of Claudes drew me.' 5 -Now }),
        @(158.0, { $window.Close() })
    )
    $demoTimer = [Windows.Threading.DispatcherTimer]::new()
    $demoTimer.Interval = [TimeSpan]::FromMilliseconds(50)
    $demoTimer.Add_Tick({
        # the tour's clock is the creature's own tick (50 ms each), so a recording keeps its timing
        $prev = $script:ShowT; $script:ShowT = $script:Tick * 0.05
        foreach ($p in $script:ShowPlan) { if ($p[0] -gt $prev -and $p[0] -le $script:ShowT) { & $p[1] } }
        # the subagents stay "seen" while the tour runs
        foreach ($k in @($script:Subagents.Keys)) { $script:Subagents[$k].Seen = [datetime]::UtcNow }
        # overrides end on time, as in the live loop
        if ($script:Override -and [datetime]::UtcNow -ge $script:OverrideUntil -and -not $script:Meal) { $script:Override = $null; Update-Look $script:Mood }
    })
    $demoTimer.Start()
} elseif ($Molt) {
    # The passing-on and the hatch, on a loop, for watching: an elder, then a younger Tok (-Stage elder or -Stage kid picks one).
    # Play only: it reads the family tree for the next name and writes nothing, and a play-only window never saves the state.
    $script:Config.Follow = $false
    $script:MoltKinds = @(if ($Stage) { $Stage } else { 'elder'; 'kid' })
    $script:MoltI = 0; $script:MoltAt = 20          # ticks (50 ms each): a second of rest first
    $script:ForcedStage = $script:MoltKinds[0]; $script:Pct = 0.3; Update-Look 'happy'; $script:Mood = 'happy'
    $moltTimer = [Windows.Threading.DispatcherTimer]::new()
    $moltTimer.Interval = [TimeSpan]::FromMilliseconds(100)
    $moltTimer.Add_Tick({
        if ($script:Passing) { $script:MoltAt = $script:Tick + 100; return }      # five seconds of rest after each piece
        if ($script:Tick -lt $script:MoltAt) { return }
        $kind = $script:MoltKinds[$script:MoltI % $script:MoltKinds.Count]; $script:MoltI++
        $script:ForcedStage = $kind; $script:Override = $null; $script:Mood = ''; Update-Look 'happy'; $script:Mood = 'happy'
        $null = Start-Passing (Get-DemoMoltPlan $kind) 'hatchling'
    })
    $moltTimer.Start()
} elseif ($Bench) {
    # One look held still, nothing said, nothing scanned or saved. After 4 s to settle, Tok's own CPU is measured for
    # -Bench seconds and written to stdout and tok.log (tools\bench.ps1 runs the whole set).
    $script:Config.Follow = $false
    if (-not $script:ForcedStage) { $script:ForcedStage = 'adult' }
    $script:Pct = 0.3
    $look = if ($script:ForcedMood) { $script:ForcedMood } else { 'happy' }
    Update-Look $look; $script:Mood = $look
    $script:BenchAt = $null
    $benchTimer = [Windows.Threading.DispatcherTimer]::new()
    $benchTimer.Interval = [TimeSpan]::FromSeconds(4)
    $benchTimer.Add_Tick({
        $me = [Diagnostics.Process]::GetCurrentProcess()
        if (-not $script:BenchAt) {
            $script:BenchAt = @{ At = [datetime]::UtcNow; Cpu = $me.TotalProcessorTime.TotalSeconds }
            $script:BenchThreads = @{}; foreach ($t in $me.Threads) { try { $script:BenchThreads[$t.Id] = $t.TotalProcessorTime.TotalSeconds } catch { } }
            $script:BenchUi = [int][Tok.Native]::GetCurrentThreadId()
            $benchTimer.Interval = [TimeSpan]::FromSeconds($Bench); return
        }
        $secs = ([datetime]::UtcNow - $script:BenchAt.At).TotalSeconds
        # The UI thread is Tok's own PowerShell; the rest is mostly WPF drawing the window. Measure 3 minutes or more:
        # the first minute or so carries .NET's JIT warming up (~4% of a core on its own), which fades.
        $ui = 0.0; $other = 0.0
        foreach ($t in $me.Threads) { try { $d = $t.TotalProcessorTime.TotalSeconds - [double]$script:BenchThreads[$t.Id]; if ($t.Id -eq $script:BenchUi) { $ui += $d } else { $other += $d } } catch { } }
        $line = "bench: {0} {1}: {2:N2}% of one core over {3:N0} s (UI thread {4:N2}%, others {5:N2}%)" -f $script:ForcedStage, $look,
            (100 * ($me.TotalProcessorTime.TotalSeconds - $script:BenchAt.Cpu) / $secs), $secs, (100 * $ui / $secs), (100 * $other / $secs)
        Write-BodyLog $line; [Console]::Out.WriteLine($line)
        $benchTimer.Stop(); $window.Close()
    })
    $benchTimer.Start()
} elseif ($MinionDemo) {
    # A scripted 20-second loop: four subagents (one per model) hatch, work and fly home; two mouthfuls too.
    $script:Config.Follow = $false
    $script:State.Coma = $false
    $script:ForcedStage = 'adult'; Update-Look 'busy'; $script:Mood = 'busy'
    $script:DemoT = 0.0
    $script:DemoPlan = @(
        @(0.5,  'spawn', 'h', 'claude-haiku-4-5',  'find TODOs'),
        @(2.0,  'spawn', 's', 'claude-sonnet-5-5', 'review tok.ps1'),
        @(3.5,  'spawn', 'o', 'claude-opus-5-5',   'design the minions'),
        @(6.5,  'spawn', 'f', 'claude-fable-5-1',  'run the tests'),
        @(1.0, 'meal'), @(4.5, 'meal'), @(8.0, 'meal'), @(19.0, 'meal'),
        @(10.0, 'done',  'h'), @(12.5, 'done', 's'), @(14.5, 'done', 'f'), @(17.0, 'done', 'o')
    )
    $script:DemoTools = @{ h = 'Grep', 'Glob', 'Read'; s = 'Read', 'Read', 'Grep'; o = 'Read', 'Edit', 'Write'; f = 'Bash', 'PowerShell', 'Read' }
    $demoTimer = [Windows.Threading.DispatcherTimer]::new()
    $demoTimer.Interval = [TimeSpan]::FromMilliseconds(100)
    $demoTimer.Add_Tick({
        $prev = $script:DemoT; $script:DemoT += 0.1
        foreach ($p in $script:DemoPlan) {
            if ($p[0] -le $prev -or $p[0] -gt $script:DemoT) { continue }
            if ($p[1] -eq 'meal') { Start-Meal -Force }
            elseif ($p[1] -eq 'spawn') { Add-FakeSubagent $p[2] $p[3] $script:DemoTools[$p[2]][0] $p[4]; Say "🐣 Sending a minion: $($p[4])" 2.4 }
            elseif ($script:Subagents[$p[2]]) { $script:Subagents[$p[2]].Done = $true }
        }
        if ([math]::Floor($script:DemoT / 1.5) -ne [math]::Floor($prev / 1.5)) {
            foreach ($k in @($script:Subagents.Keys)) {
                $s = $script:Subagents[$k]; $s.Seen = [datetime]::UtcNow
                $s.Tool = $script:DemoTools[$k][[int]([math]::Floor($script:DemoT / 1.5)) % 3]
            }
        }
        if ($script:DemoT -ge 20) { $script:DemoT = 0.0 }
    })
    $demoTimer.Start()
} else {
    $initial = if ($script:ForcedMood) { $script:ForcedMood } else { Get-PetMood $script:State $script:Pct 9999 }
    Update-Look $initial; $script:Mood = $initial
    if (-not $script:State.Greeted -and -not $script:ForcedMood -and -not $script:ForcedStage) { $script:GreetPending = $true }      # the first bubbles take the hello's place (Step-Greeting)
    else {
        $hello = if ((Get-PetStage $script:State).Name -eq 'egg') { Get-EggLine } else { "Hi! $(if ($script:State.Lineage) { Get-LineageName $script:State.Lineage } else { 'Tok' }) here." }
        Say $hello 4
    }
}

$fast.Start()
Write-BodyLog "started (pid $PID, mood $script:Mood, xp $([math]::Round($script:State.Xp,1)), est window $([math]::Round($script:Pct*100))%)"
$null = $window.ShowDialog()
# demo and forced-look windows never write the real creature's state
if (-not $PlayOnly -and -not $script:ForcedMood -and -not $script:ForcedStage) { Save-PetJson $script:State 'state.json' }
Write-BodyLog 'stopped'
$mutex.Dispose()
