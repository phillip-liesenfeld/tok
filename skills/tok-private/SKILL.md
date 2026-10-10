---
name: tok-private
description: Put Tok (the desktop creature that shows Claude Code's work, in {{TOK}}) in private mode before work involving sensitive material, so file names, commands, searches and task names stop appearing in its speech bubbles. Use when the user says /tok-private, "go private" or "Tok off", or is screen sharing; and on your own before touching passwords, password managers, secrets/.env/keys, financial, medical, legal or personal-email content. Turn it back off when that work is done.
argument-hint: "[on | off | quit | status | <minutes>]"
---
<!-- installed by Tok from {{TOK}}; Uninstall.ps1 removes it -->

# Tok private mode

Tok shows each of Claude's tool calls in a speech bubble on the user's desktop: file names, command descriptions, search patterns, task names. Private mode keeps Tok alive (moods, belly, helpers) but replaces all of that with generic lines ("👀 Reading something"), stops dreams built from recent work, refuses recordings, and puts sunglasses on Tok. Quit closes Tok entirely.

Run one of these (PowerShell):

```powershell
$tok = '{{TOK}}\private.ps1'
& $tok                    # on until turned off        (argument: on, or none)
& $tok -Minutes 30        # on for 30 minutes          (argument: a number)
& $tok -Off               # back to normal             (argument: off)
& $tok -Quit              # close Tok entirely         (argument: quit)
& $tok -Status            # check                      (argument: status)
```

- Pass `-Why "<short reason>"` with no sensitive details in it; it goes in Tok's log.
- Turn private mode on **before** the first sensitive tool call. A bubble already shown can't be unshown.
- Tok also turns private on by itself for 15 minutes when a prompt or tool call looks sensitive (a password manager's CLI, `.env` and key files, cloud secrets, mail and drive tools). That is a safety net with a fixed list, not a substitute: use this skill when you know the work is sensitive.
- When the sensitive work is finished, run `-Off` (unless the user asked for it to stay on) and say Tok is back to normal.
- If Tok isn't running, private.ps1 says so; there is nothing to hide then.
