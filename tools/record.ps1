# record.ps1 - capture Tok as a GIF (or .mp4, much smaller). The body renders its own frames (10 fps,
# transparent), so nothing behind it on the desktop ends up in the recording.
#   .\tools\record.ps1 -Seconds 45 -Out docs\live.gif          # the running body
#   .\tools\record.ps1 -MinionDemo -Out docs\minion-demo.gif   # a scripted demo window (costs no tokens)
#   .\tools\record.ps1 -Showcase -Seconds 108 -Out docs\showcase.mp4   # the narrated tour of everything
#   .\tools\record.ps1 -Molt -Stage elder -Seconds 21 -Out p4-elder.gif   # the passing-on and the hatch (-Stage kid: the younger one)
param(
    [double]$Seconds = 20,
    [Parameter(Mandatory)][string]$Out,
    [switch]$MinionDemo,
    [switch]$Showcase,
    [switch]$Molt,
    [string]$Mood = '',          # hold one look (with -Stage), e.g. -Mood busy -Stage adult
    [string]$Stage = '',
    [string]$Background = '0xF4EFE9',
    [string]$Ffmpeg = $(if ($env:TOK_FFMPEG) { $env:TOK_FFMPEG } else { 'ffmpeg' })     # ffmpeg on the PATH, or its full path here or in TOK_FFMPEG
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$frames = Join-Path ([IO.Path]::GetTempPath()) "tok-record-$PID"
$null = New-Item -ItemType Directory -Force $frames
$proc = $null
if ($MinionDemo -or $Showcase -or $Molt -or $Mood) {
    # off-screen, so the demo window doesn't appear next to the real Tok
    $mode = if ($Showcase) { @('-Showcase') } elseif ($Mood) { @('-Mood', $Mood) + $(if ($Stage) { '-Stage', $Stage }) } elseif ($Molt) { @('-Molt') + $(if ($Stage) { '-Stage', $Stage }) } else { @('-MinionDemo') }
    $proc = Start-Process pwsh -PassThru -WindowStyle Hidden -ArgumentList (@('-STA', '-NoProfile', '-File', (Join-Path $root 'tok.ps1')) + $mode + @('-X', '20000', '-Y', '20000', '-RecordDir', $frames, '-RecordSeconds', $Seconds))
} else {
    $data = if ($env:TOK_DATA_DIR) { $env:TOK_DATA_DIR } else { Join-Path $env:LOCALAPPDATA 'tok' }
    @{ dir = $frames; seconds = $Seconds } | ConvertTo-Json | Set-Content (Join-Path $data 'record.json')
}
$deadline = (Get-Date).AddSeconds($Seconds * 2.5 + 30)   # rendering frames slows the clock a little
while (-not (Test-Path (Join-Path $frames 'done.txt'))) {
    if ((Get-Date) -gt $deadline) { throw "no recording finished in time - is Tok running?" }
    Start-Sleep -Milliseconds 500
}
if ($proc) { Stop-Process -Id $proc.Id -ErrorAction SilentlyContinue }

# Flatten onto a soft background (GIF transparency is 1-bit and looks jagged). Frames are 480x465.
$flat = "color=c=$($Background):s=480x465[bg];[bg][0:v]overlay=shortest=1"
$in = @('-hide_banner', '-loglevel', 'error', '-y', '-framerate', '10', '-i', (Join-Path $frames 'frame_%04d.png'))
if ($Out -like '*.mp4') {
    & $Ffmpeg @in -filter_complex "$flat,scale=480:466,format=yuv420p" -c:v libx264 -crf 20 -movflags +faststart $Out
} else {
    & $Ffmpeg @in -filter_complex "$flat,scale=360:-1:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4" -loop 0 $Out
}
if ($LASTEXITCODE) { throw "ffmpeg failed ($LASTEXITCODE)" }
$n = (Get-ChildItem $frames -Filter 'frame_*.png').Count
Remove-Item $frames -Recurse -Force
"$Out  ($n frames, $([math]::Round((Get-Item $Out).Length / 1KB)) KB)"
