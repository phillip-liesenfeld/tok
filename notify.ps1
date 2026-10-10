# notify.ps1 - Claude Code's Notification hook for Tok. Claude Code runs it when it needs you (a permission prompt, or an
# MCP server asking for input) and hands it one JSON object on stdin. This drops one line into Tok's inbox; Tok waves, pips
# and keeps its eyes on you, the same as for a question. It reads nothing else, sends nothing anywhere and never blocks
# Claude Code (any error is swallowed; the exit code is always 0).
#   In ~/.claude/settings.json (Install.ps1 -Hook adds it):
#   "hooks": { "Notification": [ { "matcher": "permission_prompt|worker_permission_prompt|elicitation_dialog|elicitation_url_dialog|agent_needs_input",
#              "hooks": [ { "type": "command", "command": "pwsh -NoProfile -File \"<this folder>/notify.ps1\"" } ] } ] }
try {
    $in = [Console]::In.ReadToEnd() | ConvertFrom-Json
    $dir = if ($env:TOK_DATA_DIR) { $env:TOK_DATA_DIR } else { Join-Path $env:LOCALAPPDATA 'tok' }
    $null = New-Item -ItemType Directory -Force $dir
    $msg = [ordered]@{
        cmd = 'needs'; kind = "$($in.notification_type)"; message = "$($in.message)"
        transcript = "$($in.transcript_path)"; at = [datetime]::UtcNow.ToString('o')
    }
    Add-Content -LiteralPath (Join-Path $dir 'inbox.jsonl') -Value ($msg | ConvertTo-Json -Compress) -Encoding utf8
} catch { }
exit 0
