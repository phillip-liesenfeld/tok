# Privacy.ps1 - private mode: Tok keeps living (moods, belly, minions) but stops showing what Claude
# is working on: no file names, commands, searches, task names or projects in bubbles, no dreams
# built from them, no recordings. Tok wears sunglasses so you can tell at a glance.
# It turns on three ways:
#   - by hand: right-click -> Private mode, or private.ps1 (stays on until turned off)
#   - by Claude: the tok-private skill runs private.ps1 before sensitive work
#   - by itself: a prompt or tool call that looks sensitive turns it on for PrivateMinutes
# Pure functions, so tests can drive them.

# Things that look sensitive, matched (case-insensitive) and never shown anywhere. Reworked 2026-10-07: the old list
# matched bare words like "secret" against whole tool inputs (Write bodies, heredocs), so editing Tok's own README or a
# notes file named ..._secrets_from_1password.md went incognito in bursts. Now:
#   - a tool call is matched only on its key argument (Get-PrivacyKeys: the tool name, the path, the command line, the URL),
#     against patterns that need real context: the 1Password CLI, key and secret files, Gmail and Drive;
#   - a prompt (the user's own words) is matched against the plain-language list.
# PrivatePatterns in config.json replaces both lists ("(?!)" turns auto-private off); PrivateExtra adds to them (10-10: one
# extra pattern used to mean losing every default).
# 10-10, for other people's setups: the password managers and cloud secrets beyond 1Password, the usual credential files (also
# when a command names them: a space or a quote may come before or after the name), and any connector whose tool name says
# mail, drive, a password manager or money, not just claude.ai's own Gmail and Drive.
$script:DefaultPrivatePatterns = @(
    # password managers
    '\bop (read|run|inject|item|signin|vault|document)\b', '\bbw (get|unlock|login|list|export)\b', '\bkeepassxc-cli\b',
    '(^|[;&|]\s*)(pass|gopass) (show|insert|edit|generate|otp)\b', '\bGet-Secret\b', '\bcmdkey\b',
    # cloud and dev secrets
    '\baws (secretsmanager|ssm get-parameters?\b.*--with-decryption)', '\baz keyvault secret\b', '\bgcloud secrets\b',
    '\bvault (kv|read|login)\b', '\bkubectl (get|describe) secrets?\b', '\bgh auth token\b',
    # key and credential files
    '(^|[\\/\s"''])\.env(\.[\w-]+)?(?=$|[\s"''])', '(^|[\\/])id_(rsa|ed25519|ecdsa)\b',
    '\.(pem|pfx|p12|kdbx|key|ppk|p8|jks|keystore|ovpn|tfvars)(?=$|[\s"''])', '(^|[\\/\s"''])\.?credentials(\.json)?(?=$|[\s"''])',
    '(^|[\\/\s"''])\.(git-credentials|npmrc|netrc|pypirc)(?=$|[\s"''])', '\.kube[\\/]config(?=$|[\s"''])',
    '(^|[\\/\s"''])terraform\.tfstate(\.backup)?(?=$|[\s"''])',
    # connectors: mail, drives, password managers, money (by tool name)
    '^mcp__.*(gmail|outlook|mail|drive|onedrive|dropbox|1password|bitwarden|lastpass|bank|plaid|stripe|paypal)'
)
$script:DefaultPromptPatterns = @(
    '1password', '\bpasswords?\b', 'passphrase', 'api[_ -]?keys?\b', 'private[_ -]?key', '\bssn\b', 'social security',
    'bank (account|statement)', 'routing number', 'credit card', 'tax return', 'medical record'
)

function Get-PrivatePatterns($Config, [switch]$Prompt) {
    if ($Config -and $Config.PrivatePatterns) { return @($Config.PrivatePatterns) }
    $base = if ($Prompt) { $script:DefaultPromptPatterns } else { $script:DefaultPrivatePatterns }
    @($base) + @($Config.PrivateExtra | Where-Object { $_ })
}

# The parts of a tool call worth checking: its name, and the argument that says what it touches. A shell command is cut
# at its first heredoc, so a script body that merely mentions a word doesn't count. Paths inside Tok's own folder are
# skipped (its README and this file list the patterns), wherever it was installed.
$script:TokRoot = Split-Path $PSScriptRoot
function Test-InTok([string]$Path, [string]$Root = $script:TokRoot) {
    $Root = $Root.TrimEnd('\', '/'); $p = $Path -replace '/', '\'
    $p.Equals($Root, [StringComparison]::OrdinalIgnoreCase) -or $p.StartsWith("$Root\", [StringComparison]::OrdinalIgnoreCase)
}
function Get-PrivacyKeys([string]$Name, $InputObj) {
    $keys = [System.Collections.Generic.List[string]]::new(); $keys.Add($Name)
    if (-not $InputObj) { return $keys.ToArray() }
    foreach ($f in 'file_path', 'notebook_path', 'path') {
        $v = "$($InputObj.$f)"
        if ($v -and -not (Test-InTok $v)) { $keys.Add($v) }
    }
    if ($InputObj.command) {
        $c = "$($InputObj.command)"; $h = $c.IndexOf('<<'); if ($h -ge 0) { $c = $c.Substring(0, $h) }
        foreach ($line in $c -split '\r?\n') { if ($line.Trim()) { $keys.Add($line.Trim()) } }
    }
    if ($InputObj.url) { $keys.Add("$($InputObj.url)") }
    $keys.ToArray()
}

# The first pattern that matches any of the texts, or $null. Bad patterns in the config are skipped, not fatal.
function Find-Sensitive([string[]]$Texts, $Patterns) {
    foreach ($t in $Texts) {
        if (-not $t) { continue }
        foreach ($p in $Patterns) {
            try { if ($t -match $p) { return $p } } catch { }
        }
    }
    $null
}
function Test-Sensitive([string[]]$Texts, $Patterns) { $null -ne (Find-Sensitive $Texts $Patterns) }

# Private right now? Either switched on by hand (Private) or on a timer (PrivateUntil, ISO UTC).
function Test-PrivateNow($Config, [datetime]$Now = [datetime]::UtcNow) {
    if ($Config.Private) { return $true }
    if ($Config.PrivateUntil) {
        try { return $Now -lt [datetime]::Parse($Config.PrivateUntil, $null, 'RoundtripKind').ToUniversalTime() } catch { }
    }
    $false
}

# What a tool call says while private: the kind of work, never the details.
function Get-PrivateToolLine([string]$Name) {
    switch -Regex ($Name) {
        '^(Edit|Write|NotebookEdit)$'      { return '✎ Editing something' }
        '^Read$'                           { return '👀 Reading something' }
        '^(Bash|PowerShell)$'              { return '⌁ Running a command' }
        '^(Grep|Glob)$'                    { return '🔍 Looking for something' }
        '^(WebSearch|WebFetch)$'           { return '🌐 On the web' }
        '^Agent$'                          { return '🐣 Sending a minion' }
        '^AskUserQuestion$'                { return '❓ A question for you' }
        '^ExitPlanMode$'                   { return '📋 The plan is ready.' }
        default                            { return '🤫 Busy' }
    }
}
