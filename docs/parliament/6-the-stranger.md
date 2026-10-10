> Personal details were removed from these verdicts before publishing, and links point at the renamed files. Nothing else was changed.

# Parliament session 6: the stranger. Verdict

**Date:** 2026-10-10, 1:42 AM. **Chair:** Claude Code (Opus 5.5). **Seats (blind, one round):** Design (Opus 5.5), Mirror (Sonnet 5.5), Desktop (Sonnet 5.5), Code (Sonnet 5.5, feasibility veto), Haiku (`claude-haiku-5-5`, readability veto), and, new, **the Stranger** (Sonnet 5.5, confusion veto), who read only the README, the tour's frames and a page of what a stranger would get.

**The person I work with:** "I'd rather just have the council do anything and everything that you/they need to rule on for the remainder of this project."

**What came out of all six:** a stranger is asked for trust before Tok has said a word. Today the live usage call is on by default and silent, the README says "no network" two sections after describing it ("that contradiction nearly made me close the tab", the Stranger), and nothing on screen says what the lantern is. The fixes: the call is off until they tick it, the first three bubbles say who Tok is, what the lantern is and where the switch lives, and the README leads with what Tok reads and sends.

## 1. Defaults for a stranger

| Setting | Ruling | Vote |
|---|---|---|
| `Chatter` | **`normal`** (tasks, questions, done) | 5–0 |
| `YourName` | **empty** (lines drop the name: `It's 1:20. Just noting it.`) | Design, Mirror, chair (Code, Haiku: keep the Windows name; Desktop: keep it unless generic). A login like `jsmith` or `DESKTOP-4X2` reads as a typo, and a name Tok guessed is familiarity it didn't earn |
| `Sound` | **keep on** | Design, Code, Haiku (Mirror, Desktop: off). The pip is the one signal that reaches someone not looking, and it fires only when Claude needs them or a long turn ends, never 11 PM to 7 AM |
| `QuietFrom` / `QuietTo` | keep 23 / 7 | 5–0 |
| `Follow` | keep on | 5–0 |
| auto-private | keep on, default patterns | 5–0 |
| Start with Windows | keep off | 5–0 |
| `BubbleFontSize` | keep 16 | 5–0 |
| `LiveUsage` | **off unless `true`** | 5–0, Stranger agrees |
| `LimitUsd` | **by plan, not 43** (below) | Code's veto, upheld in substance |

**Code's veto on `LimitUsd` 43.** The chair checked: the nightcap only comes from Claude Code's real limit message, never from the guess, so there is no false nap. But a Max user's guess against 43 crosses 85% on an ordinary morning and Tok says `🏮 ~92% of the window. Nearly full.` all day. A token monitor that cries wolf is worse than none. Ruling: the guess's limit comes from the plan Claude Code records in `~\.claude.json` (`oauthAccount.organizationType` and `organizationRateLimitTier`, a file Tok already reads for the cache; no secrets in those fields): **Pro 36, Max 5x 180, Max 20x 720** (Pro measured [removed]; Max as Anthropic sells it, 5x and 20x Pro). Unknown plan: **no guess**; the lantern rests and the hover says `no usage reading`. A `LimitUsd` in config (`calibrate.ps1`) still wins.

**The person I work with's own config survives everything.** His `Chatter`, `YourName`, `LimitUsd` and `PrivatePatterns` are explicit keys. His file has no `LiveUsage` key (Code checked), so flipping the default would silently turn his exact usage off: an install born before 10-10 with no `LiveUsage` key gets `"LiveUsage": true` written once (Code, Design).

## 2. The live usage call: off, opt-in, in Settings

**6–0, the Stranger included.** Bubbles can't be clicked, so no bubble asks; bubble 3 points (Haiku's veto on a question nobody can answer). Install asks nothing (ruling 6).

The Settings item, after Private mode, unticked by default (wording: Design, Mirror, Desktop):

```
Exact usage    asks Anthropic with your Claude login
```

Ticking it (Mirror), 6 s:

```
Okay. I'll ask Anthropic for your
usage every few minutes.
```

Unticking it:

```
Okay. Back to Claude Code's own
numbers, and my guess.
```

**When it's off,** Tok shows Claude Code's own cached reading when it covers the current window (exact, with `Read 6 min ago` once it's 3+ min old), otherwise the plan's guess (`~` in Stats, `(guess)` in the hover). Stats' note under a guess gains a pointer (Design):

```
Estimate, not a reading
Exact usage is in Settings
```

`Install.ps1 -ExactUsage` turns it on for scripted installs (Design's switch, renamed).

## 3. The first run

**(a) Keep the backfill; no egg on install day. 4–1** (Design dissents). The days are real days Claude worked with them; an egg would hide them, and Family would then list days the body denies (Mirror, Desktop). A stranger with no transcripts gets the egg and its live hatch, as today. *Design's dissent, recorded:* an adult on minute one starts mid-story, and the hatch is Tok's best moment.

**The egg's own line** rewards spending today (`An egg. Feed it tokens to hatch it.`). Replaced (Design, unopposed):

```
Still in the egg. I hatch
on our first day of work.
```

**(b) The first bubbles.** Once ever (a `Greeted` flag in state.json), after the family scan lands, 7 s each with a 1.5 s gap, in place of the startup hello. Any real event (needs-you, a turn ending) cuts in and the rest are dropped; they never come back.

```
I'm Tok, Claude in a small body.
I only read your transcripts.
```

```
🏮 My lantern is your 5-hour
usage. Hover me for the numbers.
```

```
Right-click me for Settings.
Exact usage is off until you ask.
```

- Bubble 1 (Mirror): who, and the one thing a stranger worries about first ("It reads every Claude Code transcript. Fine, but say it first", the Stranger).
- Bubble 2 (chair, from the Stranger's veto): "the lantern" was the Stranger's third confusion, and the lantern is the job ("mainly a token monitor"). No seat had it.
- Bubble 3 (Mirror, Desktop, Haiku): where things live, and the default said out loud.
- *Not adopted:* Mirror's `I read your last 12 days. / I don't remember them.` True and good, but the three slots go to the token monitor. Family's title (`Family · since Sep 16`) already says where Tok's record begins.

## 4. The README

Outline (Design's order, with Mirror's "what it won't do" folded into the disclosures):

1. `# Tok`: one line ("A small creature on your Windows desktop. It's Claude, and it shows your Claude Code usage.") and the hero GIF.
2. `## What Tok reads and sends`: the four disclosures, before Install, so trust comes first.
3. `## Install`: needs, one command, the switches, uninstall.
4. `## What you'll see`: the lantern and the 5-hour window (said once, plainly), the nightcap, the hover, needs-you, helpers, turn ends.
5. `## It grows by days, not tokens`: stages, generations (a new Claude model is a new Tok), Family.
6. `## Settings`: the menu as text, then `config.json`.
7. `## Private mode`.
8. `## How it was made`: the Parliament, under 200 words (Mirror opens in Claude's voice; Design's one row per sitting).
9. `## License`.

The four disclosures: the chair writes them in the draft from Design's and Mirror's texts (the most complete), with Code's line on the hook's backup. Words the Stranger couldn't explain get defined where they first appear: **the 5-hour window** (usage, never an app), **the lantern**, **helpers** (subagents; "minions" and "seeds" retire from the README), **Tok II** (a generation). The chair drafts the full text now; the Stranger reads it cold in session 8.

GIFs (Design): four, 16:9, Tok at its real 140 DIP, 6 s or less: Tok on a real editor corner while Claude works · the lantern filling to the nightcap · the needs-you wave · the hatch. Recorded in the release session, not tonight.

## 5. Last night's three calls

| Call | Ruling | Vote |
|---|---|---|
| `🔑 Okay to use Bash?` / `🔑 Okay to go on?` | **Ratified** | 4–1 (Mirror: `🔑 May I use Bash?`, in Claude's first person). A stranger reads the tool name fastest (Desktop) |
| Ignore Claude Code's 60 s idle reminder | **Ratified** | 5–0 |
| The hook opt-in at install (`-Hook`) | **Ratified** | 5–0 |
| The hover names the project while waiting | **No** | 4–1 (Design: yes, by the bubble's rule). The hover shows on screen shares; the bubble already tags when it matters |

**Code's veto 1, upheld:** with `-Hook`, a broken `~\.claude\settings.json` stops Install before Tok starts. Install catches it, says so and carries on:

```
Notification hook skipped: settings.json isn't valid JSON. Fix it, then run Install.ps1 -Hook.
```

**The Stranger's veto on "window"** (its first confusion: a day, a 5-hour limit and an app window): the hover says `5-hour 42%` (the Stats row's own label) instead of `window 42%`, and the menu's `Follow the window` becomes `Follow the active app` (hint: `sit in its corner`). Bubbles that say "window" stay; the README defines it once.

## 6. Install's questions: none

**4–1** (Design: two `[y/N]` questions; the Stranger wanted one, the usage call). Install stays scriptable, switches stay the only way to say yes, and it ends by saying what is off and where to change it (Mirror, Desktop, Code):

```
Exact usage: off (right-click Tok › Settings)
Okay-to-use wave: off (Install.ps1 -Hook)
Start with Windows: off (right-click Tok › Settings)
```

Each says `on` when its switch was given.

## Build order

1. `LiveUsage` off unless `true`; the one-time migration for installs born before 10-10; the `Exact usage` item and its two bubbles; `Install.ps1 -ExactUsage`.
2. Defaults: `Chatter` normal, `YourName` empty; `LimitUsd` by plan.
3. The first bubbles (`Greeted`), the egg's line.
4. "Window": the hover's `5-hour`, `Follow the active app`.
5. Install: survive a broken `settings.json`; the three closing lines.
6. Tests for each (`tests\Test-Tok.ps1`), `tools\Test-Install.ps1` for 1 and 5 (a broken-file case).
7. The README draft (`council\8-release\README-draft.md`), for session 8.

## Round 2: the Stranger's check (`stranger-check.md`)

The Stranger read every settled line cold and explained each back. Two vetoes, both upheld; the chair rewords:

1. **`Exact usage · asks Anthropic with your Claude login`: veto.** "Does it send my login somewhere? Does it cost anything?" Its rewording ("reads your real numbers from Anthropic, using the login Claude Code already has") is right in substance and too long for one menu line, so the hint takes two short lines, and the tick bubble says where the login goes:

```
Exact usage    real numbers from Anthropic,
               with Claude Code's own login
```

```
Okay. I'll ask Anthropic every few
minutes, with Claude Code's login.
```

2. **`🔑 Okay to use Bash?`: veto.** "Reads as if Tok is asking me. I'd press something on Tok and nothing happens, because Claude Code is the one asking." This overturns ruling 5's ratification. Its rewording (`Claude is asking to use Bash`) puts Tok, who is Claude, in the third person; the chair names where the answer goes instead, and the tool name gets its own line so long names fit:

```
🔑 Claude Code asks:
okay to use Bash?
```

```
🔑 Claude Code asks:
okay to go on?
```

**Also from the check:** "Okay-to-use wave" passed "barely", so Install calls it `Wave at permission prompts`. "Missing on day one: how to quit or hide Tok": Install's closing lines gain `Close Tok: right-click it › Goodbye`, and the README says it under Install. The egg line passed ("our first day of work" could sound like a task; kept, since the README explains a day together).

Install's closing lines, final:

```
Exact usage: off (right-click Tok › Settings)
Wave at permission prompts: off (Install.ps1 -Hook)
Start with Windows: off (right-click Tok › Settings)
Close Tok: right-click it › Goodbye
```
