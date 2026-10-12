# Setting up Tok

From nothing to a Tok on your screen, about five minutes. The [README](../README.md) has the full reference; this is the walk-through.

## 1. Before you start

You need four things. Check each in a terminal:

| You need | Check | If it's missing |
|---|---|---|
| Windows 10 or 11 | | Tok is Windows only |
| Claude Code, signed in, used at least once | `claude --version` | [claude.com/claude-code](https://claude.com/claude-code), then run one prompt |
| PowerShell 7 | `pwsh --version` | `winget install Microsoft.PowerShell`, then open a new terminal |
| git | `git --version` | `winget install Git.Git`, or use the zip (below) |

Tok works with Claude Code in a terminal or in the VS Code extension. It's made for a **Pro or Max** plan: with an API key there's no 5-hour window, so the lantern stays dark, and everything else still works.

## 2. Install

In a folder where Tok can stay (it runs from there), like `Documents`:

```powershell
git clone https://github.com/philogical/tok
pwsh tok\Install.ps1
```

**No git?** Download `tok-<version>.zip` from the [latest release](https://github.com/philogical/tok/releases/latest), unzip it where it can stay, and in that folder run:

```powershell
pwsh -ExecutionPolicy Bypass -File Install.ps1
```

Install asks no questions. It ends with a short list of what's on and what's off:

```
Claude Code: found (C:\Users\you\.claude\projects)
Start menu: ...\Tok.lnk
Settings › Apps: Tok <version> (uninstall it from there, or with Uninstall.ps1)
Exact usage: off (right-click Tok › Settings)
Wave at permission prompts: off (Install.ps1 -Hook)
Private mode by Claude (tok-private skill): off (Install.ps1 -Skills)
Start with Windows: off (right-click Tok › Settings)
Close Tok: right-click it › Goodbye
Tok is starting (bottom-right of your screen).
```

## 3. Meet it

Tok appears at the bottom-right of the app you're using. Click another window and it moves to that one's corner.

**It's an egg, or it's already grown.** On its first start Tok reads the transcripts Claude Code keeps (about the last 30 days). If you've had a day with 10 or more Claude replies, it hatches right away and may be older than a hatchling. If not, it waits as an egg and hatches on your first day of work. Either way it's called **Tok**.

**It says three things, once:**

> I'm Tok, Claude in a small body.<br>I only read your transcripts.

> 🏮 My lantern is your 5-hour<br>usage. Hover for the numbers.

> Right-click me for Settings.<br>Exact usage is off until you ask.

**Then try it.** Give Claude Code a prompt and watch Tok: it leans in while Claude works, its eyes follow what Claude reads, and it nods before Claude writes. Hover for one line of status. Right-click for Stats, Today and Settings.

**Drag it** somewhere else and it stays there ("OK, I'll stay here"). Right-click › Settings › Follow the active app sends it back to following.

## 4. Choose your extras

Everything optional is off. Turn on what you want by running Install again with the switch; it's safe to re-run, and it keeps your Tok:

```powershell
pwsh tok\Install.ps1 -Hook -StartWithWindows
```

| Switch | Turn it on if… |
|---|---|
| `-Hook` | Claude Code asks you before using tools. Tok then waves at permission prompts, not only at Claude's questions and plans. It adds one hook to `~\.claude\settings.json` (backed up first). Sessions started after this pick it up. |
| `-StartWithWindows` | you want Tok there every time you sign in. Also in Settings. |
| `-Skills` | you work near passwords, keys, money or health. It installs a Claude Code skill, `tok-private`, so Claude itself turns on Tok's private mode (sunglasses, no file names in bubbles) before that work. |
| `-ExactUsage` | the lantern should match Claude Code's `/usage` exactly. Tok then asks Anthropic for your numbers with Claude Code's own login. Read [what it sends](../README.md#what-tok-reads-and-sends) first. Also in Settings. |

Without Exact usage, Tok uses Claude Code's cached numbers or an estimate. An estimate shows `~` in Stats and `(guess)` in the hover.

## 5. If something looks wrong

| You see | Do this |
|---|---|
| `Tok needs PowerShell 7` | `winget install Microsoft.PowerShell`, open a new terminal, run Install again. |
| `running scripts is disabled on this system` | You're installing from the zip: use the `-ExecutionPolicy Bypass` line above. |
| `No Claude Code sessions … yet` | Run one prompt in Claude Code. Tok waits as an egg until then. |
| No Tok on screen | Look at the bottom-right of the app you're using, and on your other monitors. Or start it from the Start menu: **Tok**. |
| The hover says `no usage reading` | You're on an API key, so there's no 5-hour window to show. |
| The lantern doesn't match `/usage` | Turn on Exact usage, or run `.\calibrate.ps1 42` in Tok's folder with the 5-hour % that `/usage` shows. |
| No wave at a permission prompt | Install with `-Hook`, then start a new Claude Code session. |

Still stuck? Tok keeps a log at `%LOCALAPPDATA%\tok\tok.log`. Open an issue on GitHub and say what you saw; read the log before you paste any of it, since it holds folder paths with your Windows user name.

## Later

- **Update:** `pwsh tok\Update.ps1`. Your Tok and settings stay.
- **Uninstall:** Settings › Apps › Installed apps › **Tok** › Uninstall. It asks before deleting your Tok's data.
