# say.ps1 - make Tok say something: a bubble and a small pip (Tok has no voice). -Silent: the bubble only.
#   .\say.ps1 "hello"                   a bubble
#   .\say.ps1 "oops" -Mood ouch         with a face: happy love busy needs sleep hungry ouch dizzy content stretch
param(
    [Parameter(Mandatory, Position = 0, ValueFromRemainingArguments)][string[]]$Text,
    [string]$Mood,
    [switch]$Silent
)
$dir = if ($env:TOK_DATA_DIR) { $env:TOK_DATA_DIR } else { Join-Path $env:LOCALAPPDATA 'tok' }      # TOK_DATA_DIR: a second, separate Tok
$null = New-Item -ItemType Directory -Force $dir
$msg = [ordered]@{ text = ($Text -join ' '); mood = $Mood; silent = [bool]$Silent; at = [datetime]::UtcNow.ToString('o') }
Add-Content -LiteralPath (Join-Path $dir 'inbox.jsonl') -Value ($msg | ConvertTo-Json -Compress) -Encoding utf8
if (-not (Get-Process pwsh -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like '*tok.ps1*' })) {
    Write-Warning 'Tok is not running; the message will wait in the inbox. Start it with Start-Tok.vbs.'
}
