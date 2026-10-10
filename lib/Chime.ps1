# Chime.ps1 - Tok's small sounds, synthesized in code (no sound files, no voice).
# A soft marimba-like pip for the moments you might not be looking: Claude needs you (three notes up), a long turn is
# done (two notes settling), a long turn ended on an error (the same two notes, falling the other way), and Tok woke up after
# a real limit (an octave). Quiet hours, the Sound setting and a short gap between pips keep it small.
#
# The family (Parliament session 4, ruling 10; design\parliament\edges\VERDICT.md). Every new pip keeps to these:
#   - One dry marimba: no reverb, no glide, the same synthesis for every kind.
#   - Notes from C, E and G only (one C-major chord).
#   - At most 3 notes, and the whole pip rings out in under 0.6 s.
#   - Contour is speech: up asks, settling answers, an octave means refilled.
#   - Never a pip without a visible cause: each kind has a motion twin (the wave and hop, the hop's touchdown, the stretch).
#   - No sound for bad news: a turn that ended on an error is still just "your turn", falling, never an alarm.
if (-not ('Tok.Chime' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.IO;

namespace Tok {
public static class Chime {
    const int SR = 44100;
    // Each note: a sine with a fast attack and a ~0.11 s decay, plus a quick 4x overtone (the marimba "tok")
    // and a little 2x warmth. Peak-normalized to Volume (0..1), 16-bit mono WAV.
    public static byte[] Render(double[] freqs, double gap, double volume) {
        double tail = 0.5;
        int n = (int)((gap * (freqs.Length - 1) + tail) * SR);
        var buf = new double[n];
        for (int k = 0; k < freqs.Length; k++) {
            int start = (int)(k * gap * SR);
            double f = freqs[k];
            for (int i = 0; start + i < n; i++) {
                double t = i / (double)SR;
                double att = Math.Min(1.0, t / 0.004);
                double v = Math.Exp(-t / 0.11) * Math.Sin(2 * Math.PI * f * t)
                         + 0.14 * Math.Exp(-t / 0.025) * Math.Sin(2 * Math.PI * 4 * f * t)
                         + 0.10 * Math.Exp(-t / 0.06) * Math.Sin(2 * Math.PI * 2 * f * t);
                buf[start + i] += att * v;
            }
        }
        double peak = 1e-9;
        foreach (double x in buf) peak = Math.Max(peak, Math.Abs(x));
        int fade = SR / 50;
        var ms = new MemoryStream();
        var w = new BinaryWriter(ms);
        w.Write(new[] { 'R', 'I', 'F', 'F' }); w.Write(36 + n * 2); w.Write(new[] { 'W', 'A', 'V', 'E' });
        w.Write(new[] { 'f', 'm', 't', ' ' }); w.Write(16); w.Write((short)1); w.Write((short)1);
        w.Write(SR); w.Write(SR * 2); w.Write((short)2); w.Write((short)16);
        w.Write(new[] { 'd', 'a', 't', 'a' }); w.Write(n * 2);
        for (int i = 0; i < n; i++) {
            double g = i > n - fade ? (n - i) / (double)fade : 1.0;
            w.Write((short)Math.Round(32767 * volume * g * buf[i] / peak));
        }
        w.Flush();
        return ms.ToArray();
    }
}
}
'@
}

# The pips. Notes in Hz.
#   needs   = C6 E6 G6 (a little question going up). The 0.10 s gap puts the top note on the apex of the 220 ms hop.
#   done    = G5 C6 (settled), quieter; it is played (-DelayMs) so the C6 lands as the hop touches down.
#   doneerr = C6 G5 (the same two notes falling: your turn, and it did not go well).
#   wake    = C5 C6 (an octave: the tokens are back), only after a real limit, with the stretch.
$script:ChimeKinds = @{
    needs   = @{ Notes = [double[]](1046.50, 1318.51, 1567.98); Gap = 0.10; Volume = 0.30 }
    done    = @{ Notes = [double[]](783.99, 1046.50); Gap = 0.085; Volume = 0.22 }
    doneerr = @{ Notes = [double[]](1046.50, 783.99); Gap = 0.085; Volume = 0.22 }
    wake    = @{ Notes = [double[]](523.25, 1046.50); Gap = 0.12; Volume = 0.22 }
}
$script:ChimeVersion = 2      # bump when the sound changes, so the cached file is rebuilt

function Get-ChimeFile([string]$Kind) {
    $k = $script:ChimeKinds[$Kind]
    if (-not $k) { return $null }
    $dir = Join-Path $script:DataDir 'sounds'
    $path = Join-Path $dir "$Kind-v$script:ChimeVersion.wav"
    if (-not (Test-Path $path)) {
        $null = New-Item -ItemType Directory -Force $dir
        [IO.File]::WriteAllBytes($path, [Tok.Chime]::Render($k.Notes, $k.Gap, $k.Volume))
    }
    $path
}

# Quiet hours run from QuietFrom to QuietTo (local hours, wrapping past midnight); equal means none.
function Test-QuietHour([int]$Hour, $From, $To) {
    if ($null -eq $From -or $null -eq $To -or [int]$From -eq [int]$To) { return $false }
    $f = [int]$From; $t = [int]$To
    if ($f -lt $t) { return $Hour -ge $f -and $Hour -lt $t }
    $Hour -ge $f -or $Hour -lt $t
}

# Whether a pip may play now: Sound on, not quiet hours, and at least 15 s since the last one
# (a needs-you pip may follow a done pip sooner, since it asks for something).
function Test-ChimeOk($Config, [string]$Kind, [datetime]$NowLocal, [datetime]$LastUtc, [datetime]$NowUtc, [string]$LastKind = '') {
    if ($Config.Sound -eq $false) { return $false }
    if (Test-QuietHour $NowLocal.Hour $Config.QuietFrom $Config.QuietTo) { return $false }
    $gap = if ($Kind -eq 'needs' -and $LastKind -ne 'needs') { 3 } else { 15 }
    ($NowUtc - $LastUtc).TotalSeconds -ge $gap
}

$script:ChimePlayers = @{}
$script:LastChime = [datetime]::MinValue; $script:LastChimeKind = ''
function Invoke-Chime([string]$Kind, [switch]$Force, [int]$DelayMs = 0) {
    try {
        $now = [datetime]::UtcNow
        if ($PlayOnly -and -not $Force) { return }      # demo, bench and tour windows stay silent
        # -DelayMs: play later, so a pip can land on a motion (the done pip on the hop's touchdown). The checks below run when it
        # plays, not now.
        if ($DelayMs -gt 0) { Start-Later $DelayMs { param($k, $f) Invoke-Chime $k -Force:$f } @($Kind, [bool]$Force); return }
        if (-not $Force -and -not (Test-ChimeOk $script:Config $Kind ([datetime]::Now) $script:LastChime $now $script:LastChimeKind)) { return }
        $p = $script:ChimePlayers[$Kind]
        if (-not $p) {
            $file = Get-ChimeFile $Kind
            if (-not $file) { return }
            $p = [System.Media.SoundPlayer]::new($file); $p.Load()
            $script:ChimePlayers[$Kind] = $p
        }
        $p.Play()      # async; the player is kept so it isn't collected mid-pip
        $script:LastChime = $now; $script:LastChimeKind = $Kind
    } catch { }
}
