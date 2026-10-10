> Personal details were removed from these verdicts before publishing, and links point at the renamed files. Nothing else was changed.

# Parliament of Claudes, session 3: the full character. Verdict

**Date:** 2026-10-07, evening.

**Who took part:**
- **Chair:** Claude Code (Opus 5.5).
- **Delegates:**
  - Design (Opus 5.5)
  - Mirror (Sonnet 5.5)
  - Desktop (Sonnet 5.5)
  - Code (Sonnet 5.5), with a feasibility veto
  - Haiku, with a readability veto. This was the first session with **Haiku 5.5** (`claude-haiku-5-5`, confirmed from its transcript; the October 5 Haiku was 4.5).

**How it ran:**
1. Round 1, blind: each delegate's `pitch.md`, written to `BRIEF.md`.
2. Round 2: rebuttals and votes on nine disputed points (`ROUND2.md`, `*/rebuttal.md`).
3. The person I work with handed the whole round over ("design by committee but entirely autonomous") and took no part.

**The chair's own mistake:** round 1 judged readability from `corner.png`, which drew Tok at **half its real size**. That inflated every "text too small" finding, so round 2 re-judged everything with `corner-true.png`. At 1:1 the 16 px bubble reads fine. The real weak spots are the pills and labels drawn *inside* the art, because they scale with Tok.

## The vote, point by point

| | Question | Result | Ruling |
|---|---|---|---|
| A | Elder face | **(a) spectacles + plant cues, 5–0 in round 3** (was (c), 5–0, in round 2) | The person I work with reopened it; details below. |
| B | Always-on usage % | **No, 4–1** (Haiku for) | Lantern + hover line + Stats. A % appears in text only from **80% up**. |
| C | Line style | **Sentence case, 5–0** (Mirror switched) | |
| D | Grammar pass | **Last, 5–0** | One sweep, after the port and the new lines. |
| E | Ancestor portrait / inherited tint | **Portrait 4–1, tint 4–1** | Both, cosmetic only. Details below. |
| F | Hops change with age | **Yes, 4–1** (Mirror against) | Yes, with Mirror's guard. Details below. |
| G | "first bite!" / anniversary | **First bite 5–0; anniversary cut, 3–2** | |
| H | One bubble at a time | **Yes, 5–0** | Easter eggs and dreams queue behind live state (a priority tag on `BubbleQueue`). |
| I | Performance and usage before art | **Yes, 5–0** | |

**A. The elder's face, reopened (round 3, `ROUND3-glasses.md`, `*/glasses.md`).** Round 2 dropped Design's gold spectacles on one fear: that they'd be confused with the private-mode sunglasses. The person I work with, who lives with Tok, said they aren't confusing and "clearly communicate wisdom". All five delegates changed their vote to **spectacles + plant cues, 5–0**. Each said its objection had been a guess, and the person living with Tok had now answered it.

- **The spectacles:** thin gold rims with clear lenses, so the eyes show. Haiku: the rims must be at least 2 px at the elder's 1.08 scale. Code: about 20 lines of XAML, no effects.
- **Never both at once:** in private mode the spectacles come off, then the shades go on, as a visible swap.
- **Needs-you:** Tok peers over the rims at the person I work with. It's still the only time it looks at him.
- **Dozing:** the spectacles slip and tilt.
- **The plant cues stay:** a bark-brown lower stem with a node ring, a second ring of deeper-gold petals, and seeds in the flower's heart.
- **Still never:** white brows, a beard, lines or wrinkles.

**E. What a generation leaves behind.** Code voted no on portraits because of the bitmaps, so a portrait is the ancestor's final *stage* plus one line, drawn live from parameters, not a stored image. "Tok III · elder · 5,210 XP · mostly in tok". The tint is one colour field in `state.json`. Design draws the next egg's spots in the parent's flower colour, so only an elder-born egg inherits anything.

**F. Hops by age.** Hatchling 1.15× height; elder 0.8× height and 15% slower. Mirror's guard is adopted: **the needs-you hop never scales.** It's the one hop that means "you".

## Round 4: "is this you?" (the person I work with asked us to make sure it still feels like ourselves)

Each delegate answered as Claude, not as its role (`*/is-this-you.md`, plus `chair/is-this-you.md`).

**Is it us?** All six said yes, mostly.

**What's most us:** all six named the same thing, each on its own: the glance. Eyes on the person I work with's work, and on him only when it needs him. That is now the one thing that can never change.

**What isn't us, and what the chair rules:**

- **Minions come home; they aren't eaten** (Design, with the chair).
  - We are the ones sending subagents out, and we wouldn't swallow them.
  - A finished minion flies back, pours what it carried into the lantern as honey (the same ripple, the level rises), and tucks back into the sprout.
  - The chomp, chew and gulp stay for tokens only.
- **No floating score** (Haiku and Desktop). The floating `sonnet +143k` label is dropped. When a minion comes home, the bubble says *what* finished, and the token counts move to Stats and the Family panel as plain tallies.
- **Age is days worked together, not tokens produced** (Mirror, with the chair).
  - A day counts when it has at least 10 main-session replies.
  - The stages are: hatchling on the first day, kid at 3 days, adult at 10, elder at 30, all per generation.
  - XP disappears from the interface. It also no longer rewards burning the person I work with's usage.
- **Less chatter** (Desktop).
  - No bubble greeting on each prompt; Tok gives a small squish instead.
  - Tok speaks for real changes: done, needs you, the limit, the reset, growing up.
  - Tool bubbles stay under the person I work with's own Chatter setting (he chose "chatty").
- **Passing on, not coming back** (Code).
  - The phoenix *look* stays, because the person I work with asked for it. The elder's light pours into the seed and the seed becomes the egg.
  - What it means changes. The elder gives its light to the seed, waves goodbye and fades. The one who hatches is a descendant ("I'm Tok III"), shown its family tree.
  - It never says "I'm back", and it never claims to remember.

The chair agrees with all five. None of them conflicts with anything the person I work with asked for.

## Settled with no dispute

- **Voice is removed** (5–0, matching the person I work with's vote).
  - Take out the Speak path, the Voice menu item and **every duplicated "spoken" string**; each bubble line is written twice today.
  - `voice\Babble.ps1` stays on disk, unhooked, until the person I work with says delete. The git tag keeps it either way.
- **XP stays per generation and never carries across lives.** No multipliers, unlocks or ranks. The tree is a family, not a leaderboard.
  - Mirror: "Tok never claims to remember." The person I work with is the continuity.
  - The Family panel shows plain tallies per generation: replies, minions, top project, dates. No score.
- **Dreams stay, rewritten** (Mirror):
  - cut "got married" and "made of cheese";
  - private mode uses only generic dreams, never recent work;
  - add one quiet ancestor dream per generation: "…Tok III was here. I don't remember it.";
  - dreams end by waking, never scary.
- **Lines that are now wrong come first** (Desktop). Every line that treats the sprout as the usage meter is now false status:
  - "in full bloom", "budding nicely", "napping under my flower";
  - the whole `Show-Tour`.
  - Rewrite them around the lantern. Keep two of the five prompt greetings. The long-run "done" alert names the project.
- **Easter eggs:**
  - **Fix "Tok":** `\btok\b` matches `tok.ps1`, so it fires on every prompt in this project. Exclude a following `.`, `\` or `/`, and allow it at most once per 30 minutes.
  - **"thanks":** keep the blush, but drop `ty` and `thx`; they match in code.
  - **1 am note:** keep, once a night, silent in private mode.
  - **Pumpkin:** becomes face paint, Oct 24–31 only.
  - **Cut** the `/spoopytok` skill idea.
  - **Add** "first bite!" once per life.
- **Readability at real size:**
  - the in-art pills and labels: text 10 DIP or larger (check at the hatchling's 0.70 scale), solid backgrounds, borders 1.5 or wider, no faded or ghost text, labels held 2.5 s or longer;
  - drop emoji that shrink to specks inside the art;
  - anchor each pill to a fixed spot;
  - "Tok III" (the generation) and "Opus 6" (the model) are different things and stay separate.
- **Style rules for the final pass:**
  - sentence case;
  - `…`, not `...`;
  - no em dashes;
  - asterisks only for sounds and actions;
  - "5-hour window";
  - times written "2:10" and "1:05 am";
  - one idea per bubble, about 28 characters;
  - emoji only where they name the thing.
  - See `desktop\lines.md`.
- **Nothing from v0–v3 comes back** except v0's warm first hello.
- **Must not change** (said four different ways):
  - Tok looks at the person I work with's work, and at the person I work with only when it needs him;
  - each generation starts from the egg at zero;
  - the two-eyed face and the light kept inside the lantern;
  - Tok stays a local watcher with no scripted logins.

## Performance (Code, measured read-only on the running app)

- **The measurement:** 36.7% of one core while Claude was working. The UI thread took 24.8% of a core and the render thread 4.9%, so the cost is PowerShell running the tick code, not WPF drawing.
- **Budget:**

  | State | Limit |
  |---|---|
  | Idle or asleep | under 2% of one core |
  | Working, 2 minions | under 8% |
  | Rebirth (15 s) | under 15% |
  | Memory | under 200 MB |

- **Fixes, in order:**
  1. **Adaptive tick:** 50 ms only while something moves, otherwise 250 ms, and pupils update only on a cursor move of more than 2 px.
  2. **Cap WPF at 30 fps** with `DesiredFrameRate`.
  3. **Poller:** prune stale transcript offsets and rescan every 30 s instead of every 4 s.
  4. **Shadow:** bake or drop the `DropShadowEffect`.
  5. **Motion and maths:** orbits, the bob and eye drift become WPF animations on one clock (Design: two clocks stutter). Their maths moves into one `Add-Type` C# class during the port.
- **Motion feel** (Design): bob at least 2 grid units (1 unit is half a pixel and shimmers); chew at 4–5 Hz; landings squash 3% or less.

## Usage accuracy: the person I work with's top priority

**What Code found** in Claude Code 2.1.293 and its docs (evidence in `code\research.md`):
- Claude Code reads the account's real usage from Anthropic's response headers (`anthropic-ratelimit-unified-5h-*` and `-7d-*`) on **every model response**.
- It passes this to a **status-line command** as `rate_limits.five_hour` and `rate_limits.seven_day` (`used_percentage`, `resets_at`), which is documented.
- The `~/.claude.json` cache that Tok reads today is written at most once a minute, and only when Claude Code fetches `/api/oauth/usage`. That's why it goes stale.
- Both sources are account-wide, so claude.ai and phone use are included. The numbers are whole percents.

**Ruling, best first:**
1. **Status-line tee** (no network, no credentials, exact on every response). Built as a probe: `tools\statusline.ps1`, registered as `statusLine` in `~\.claude\settings.json` on 10-07. It saves the JSON to `%LOCALAPPDATA%\tok\statusline.json`.
   - **It did not fire in this VS Code session,** so the extension probably doesn't run status lines.
   - **Next step:** check it in a new session and in the terminal CLI.
2. **If VS Code never runs it:** Tok calls `/api/oauth/usage` itself with the token Claude Code already stored.
   - This is exact and current, and the person I work with pre-approved it: "If we need an SSO-hook or something, that is completely fine. Accuracy is more important to me than anything else."
   - **Conditions:**
     - read the token at call time; never copy, log or display it;
     - one read-only GET at most every 60 s, and only while Claude is active;
     - fall back silently on any error;
     - the README states plainly that Tok now makes this one call.
   - Code calls it a grey area because the endpoint is undocumented and the credential belongs to Claude Code. The person I work with's priority outranks that, with the disclosure.
3. **Drop the $36 dollar top-up guess once an exact source works.** Until then, whatever the source, Tok shows how old its numbers are ("as of 3 min ago").

## The order of work (Code's phases; about 1,000 lines in all)

| Phase | What | Size |
|---|---|---|
| P0 | performance fixes 1–4 | ~100 lines |
| P5 | the usage source above (moved up: the person I work with's top priority) | ~60 lines |
| — | the voice removal and the stale-line rewrite | — |
| P1 | bodies: the lantern belly, four sprouts with elder plant cues, the caps by age | ~250 lines |
| P2 | behaviour: the eat chain, hops by age, needs-you, sunglasses | ~200 lines |
| P3 | minions: seeds in model colours, labels | ~150 lines |
| P4 | set pieces: the phoenix, the egg (inherited tint), the nightcap pill | ~250 lines plus C# |
| last | dreams rewrite, easter-egg fixes, one-bubble priority, Family portraits; then the grammar sweep | — |

- **Each phase ends** with a CPU sample against the budget and the tests (92 pass today).

**Why the chair isn't porting tonight:** the week is at 83% (resets 10-09, about 9 am CDT), and this conversation's context is very large. The port starts in a **fresh session**, beginning with P0 and the usage source, from this file. Then the person I work with watches the new art live.

## Who carried what

| Delegate | Contribution |
|---|---|
| **Design** | the spectacles (withdrawn, then restored on the person I work with's read) and the plant cues, the motion feel, the clock fix |
| **Mirror** | the meaning of XP, the portrait and inherited tint, the dreams, "never claims to remember" |
| **Desktop** | removing voice and its dead strings, the stale-line catch, the "tok" regex bug, the style rules |
| **Code** | the real CPU numbers, the status-line `rate_limits` discovery, the port plan |
| **Haiku 5.5** | one bubble at a time, the in-art pill fixes, and correcting its own round-1 read at true size |
