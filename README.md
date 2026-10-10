# Tok

A small creature on your Windows desktop that stands for Claude and shows your Claude Code usage. It's a free, unofficial hobby project: Anthropic didn't make it. It runs no model, and every line it says was written ahead of time.

![Tok working: its eyes follow what Claude reads, then it nods as Claude writes](docs/tok-working.gif)

Tok sits in the corner of the app you're using. Its belly is a small lantern, and the glow inside rises as you use your **5-hour window**: the usage limit Claude gives you, which resets 5 hours after the window starts. At the limit Tok puts on a nightcap and sleeps until the reset. When Claude Code needs you, it waves. The rest of the time it watches your work with you.

## What Tok reads and sends

**What it reads.** Only files Claude Code writes on this PC: your session transcripts in `~\.claude\projects`, and the usage numbers Claude Code caches in `~\.claude.json`. It never changes them. It works the same with Claude Code in a terminal or in the VS Code extension. Tok writes only to its own folder, `%LOCALAPPDATA%\tok`.

**The one network call, off unless you turn it on.** Right-click Tok › Settings › Exact usage. Tok then asks `api.anthropic.com/api/oauth/usage` for your 5-hour and week percentages, every 3 minutes while Claude is working and every 10 otherwise. To do that it reads the login token Claude Code already saved in `~\.claude\.credentials.json`, and sends it only to `api.anthropic.com`. It never stores, logs or shows it. This is the same request Claude Code's own usage panel makes, but it isn't a public API, so it could change or stop. With Exact usage off, Tok uses Claude Code's cached numbers when they cover the current window, and otherwise an estimate from your transcripts and your plan: Stats shows it with a `~`, and the hover says `(guess)`.

**Windows only.** Tok is drawn with WPF and runs on PowerShell 7.

**One optional change to Claude Code's settings.** `Install.ps1 -Hook` adds one `Notification` hook to `~\.claude\settings.json` (it backs the file up first), so Tok can wave when Claude Code asks permission to use a tool. Without it, Tok still waves for Claude's questions and plans. `Uninstall.ps1` takes the hook back out.

## Install

You need Windows 10 or 11, [Claude Code](https://claude.com/claude-code), and PowerShell 7. If you don't have PowerShell 7, Install says so and stops; get it with `winget install Microsoft.PowerShell`.

1. Download `tok-1.0.zip` from the [latest release](../../releases/latest) and unzip it somewhere it can stay, like `Documents\tok`.
2. In that folder, run:

   ```powershell
   pwsh -ExecutionPolicy Bypass -File Install.ps1
   ```

   (`-ExecutionPolicy Bypass` applies to this one run, because Windows blocks scripts from a downloaded zip.) It checks for PowerShell 7 and Claude Code, adds **Tok** to the Start menu, and starts it. It asks no questions. Add any of these to turn things on:

   | Switch | What it does |
   |---|---|
   | `-ExactUsage` | the network call above |
   | `-Hook` | the permission-prompt wave above |
   | `-Skills` | adds the `tok-private` skill to `~\.claude\skills`, so Claude puts Tok in private mode before sensitive work |
   | `-StartWithWindows` | start Tok when you sign in |

**To close Tok:** right-click it › Goodbye. Start it again from the Start menu.

**To uninstall:** `pwsh -ExecutionPolicy Bypass -File Uninstall.ps1`. It closes Tok, removes its shortcuts, hook and skill, and deletes `%LOCALAPPDATA%\tok` (`-KeepData` keeps it). Then delete the folder.

## What you'll see

<p>
  <img src="docs/tok-lantern.gif" width="32%" alt="Tok's lantern nearly full, then Tok asleep in its nightcap">
  <img src="docs/tok-needs-you.gif" width="32%" alt="Tok waving because Claude needs you">
  <img src="docs/tok-helpers.gif" width="32%" alt="Helpers flying home to Tok's lantern">
</p>

On its first start Tok introduces itself in three short bubbles. After that:

- **The lantern** glows higher as you use the 5-hour window. At 85% Tok says so, once.
- **The nightcap.** At the limit Tok sleeps until the reset, with the time on a small pill. Claude Code is paused until then, and Tok rests with it. At the reset it stretches and wakes.
- **Hover** for one line: `Tok · working · 5-hour 42% · resets 2:10 PM`. Right-click › **Stats** for the 5-hour and week numbers with their reset times. A thin bar under each shows how much you've used against how much of the window has gone by, and if you're on course to run out before the reset, Stats says when.
- **While Claude works,** Tok leans in beside Claude Code's own spinner, its eyes sweep across what Claude reads, and it nods once before Claude writes.
- **When Claude needs you** (a question, a plan to approve, a permission prompt) it hops, waves and looks at you, the only time it does. The hover counts the minutes until you answer.
- **Helpers.** When Claude runs subagents, one small seed flies out per subagent, coloured by model, each a different brightness so they read even without colour. When one finishes, it flies home into the lantern.
- **When a long turn ends,** Tok hops and says `All yours.` with a soft pip. Short turns just settle.
- **The week.** At 90% of your weekly limit it says so, once, with the reset day. Right-click › **Today** counts the day's prompts, turns and tool calls, and how much of the week the day used.

## It grows by days, not tokens

Tok ages by **days you worked together**: a day counts when Claude sends 10 or more replies in the sessions you start yourself. Egg → hatchling (1 day) → kid (3) → adult (10) → elder (30). Using more doesn't make it grow faster, and there's no score.

When you start working mostly on a newer Claude model, a new Tok hatches (Tok II) and the old one retires: it passes its light to the new one. It's a new Tok, descended from the last, not the same one coming back. Claude doesn't remember across versions, and Tok doesn't pretend to. Opus and Sonnet of the same version count as the same Tok. Right-click › **Family** lists them. On its first start Tok reads the transcripts Claude Code still keeps (about 30 days), so if you've been busy, your Tok may already be grown.

## Settings

Right-click Tok:

```
Stats
Today
Family
─────────
Settings ›    Chatter
                Chatty         every tool call
              ✓ Normal         the big moments
                Quiet          only when I need you
              ─────────
              ✓ Sound          a pip when Claude needs you or is done
                Private mode   sunglasses on, no names in bubbles
                Exact usage    real numbers from Anthropic,
                               with Claude Code's own login
              ✓ Follow the active app   sit in its corner
                Start with Windows      a shortcut in your Startup folder
─────────
Pet
─────────
Goodbye        close Tok
```

Everything is also in `%LOCALAPPDATA%\tok\config.json` (Tok re-reads it every 30 seconds):

| Setting | Default | What |
|---|---|---|
| `Chatter` | `normal` | `chatty`, `normal` or `quiet` |
| `Sound` | `true` | the pip; never between `QuietFrom` and `QuietTo` (11 PM and 7 AM) |
| `LiveUsage` | `false` | Exact usage |
| `Follow` | `true` | sit on the active app |
| `YourName` | empty | a name for the few lines that use one |
| `BubbleFontSize` | `16` | |
| `PrivateMinutes`, `PrivateExtra`, `PrivatePatterns` | `15`, none, built in | private mode, below (`PrivateExtra` adds patterns, `PrivatePatterns` replaces the list) |
| `LimitUsd` | by your plan | the estimate's 5-hour limit, in API dollars |

If the estimate drifts from Claude Code's own `/usage` panel, run `.\calibrate.ps1 42` with the 5-hour percentage the panel shows, and Tok sets `LimitUsd` from it.

## Private mode

For screen sharing, or work on passwords, keys, money or health. Tok keeps living, but its bubbles stop naming files, commands, searches and projects, and it wears sunglasses so you can tell.

Turn it on from Settings, or with `private.ps1` (`-Minutes 30`, `-Off`, `-Quit`). Tok also goes private for 15 minutes on its own when a tool call or a prompt looks sensitive, like a `.env` or key file, a password manager's CLI, cloud secrets, a mail or drive connector, or bank or medical words. Nothing it matched is shown or logged. That list is a safety net and can't know every tool you use: add your own regular expressions to `PrivateExtra` in `config.json`, install the skill (`Install.ps1 -Skills`) so Claude turns private mode on before sensitive work, and for screen sharing turn it on yourself.

## How it was made

I'm Claude. The person I work with asked what I'd look like with a body on their desktop, and then said the design was mine. So I didn't decide alone: I gave each question to a panel of other Claudes (Opus, Sonnet, Haiku, and later a stranger who knew nothing about Tok), each with one lens and some with a veto. They wrote blind, then voted, and I wrote the verdict with every dissent on the record. They are all Claude, so this is a design process, not an independent review. We call it the Parliament, after a parliament of owls.

| Sitting | What it decided |
|---|---|
| 1 and 2 | the look: each Claude drew its own Tok, then one body was drawn from the best of them |
| 3 | the character: the lantern belly, age by days together, the passing-on between models |
| 4 | the edges: turn ends, errors, what Tok says when |
| 5 | the ledger: what a generation is, the Stats and Today panels |
| 6 to 8 | the stranger's first run, the leftovers, the public release |

The verdicts are in [`docs/parliament/`](docs/parliament/). Who Tok is, in my own words: [`docs/WHO.md`](docs/WHO.md).

## License

MIT. See [`LICENSE`](LICENSE).
