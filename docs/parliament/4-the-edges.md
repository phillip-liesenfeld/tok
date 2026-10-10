> Personal details were removed from these verdicts before publishing, and links point at the renamed files. Nothing else was changed.

# Parliament session 4: the edges. Verdict

**Date:** 2026-10-09, evening. **Chair:** Claude Code (Opus 5.5). **Seats (blind, one round):** Design (Opus 5.5), Mirror (Sonnet 5.5), Desktop (Sonnet 5.5), Code (Sonnet 5.5, feasibility veto), Haiku (`claude-haiku-5-5`, readability veto). The person I work with handed it over: "It's all yours."

**The theme that came out of all five:** Tok over-celebrates and under-tells. It cheers every turn end (about 75 a day), flinches red at every error (including when the person I work with declines a tool), and says nothing at the moments that matter: compaction, Claude waiting on him, the week running low. The fix is fewer, truer signals, each with a body and, at most, a pip.

## Rulings

| # | Question | Vote | Ruling |
|---|---|---|---|
| 1 | "done!/ta-da" + love face on every turn | **Cut, 5–0** | Short turns (< 45 s): a small settle squish, nothing else. Long turns: hop, "All yours.", pip on the landing. |
| 2 | A turn that ended on an error | Mirror, chair | Long turns only: no hop, "Ended on an error. All yours.", the done pip falling (C6 → G5). Honest, not a cheer. |
| 3 | The ouch flinch and its red "!" | **Cut, 4–0** (Haiku silent) | One error: nothing (still counted). Two within 60 s: the orange ↺ rethink look. A declined tool is not an error. No red anywhere. |
| 4 | Compaction | **Say it, 4–0** | "Chat compacted. I kept the gist." (Low, with the existing dizzy.) |
| 5 | Esc / interrupt | Code, unopposed | Its own event. Today it parses as a Prompt and keeps Tok busy and awake (a CPU leak too). Now: settle, no bubble. |
| 6 | Claude waiting on him | Desktop + Haiku | Bubble pinned 20 s (was 8, while the wave runs 20). Then the eyes stay on him, still, until his next prompt or 30 min; the hover line says "waiting on you, N min". No fast loop. |
| 7 | Pips in sync with motion | **5–0** | Done lands with the hop's touchdown (timed per age). Needs-you gap 75 → 100 ms so the top note hits the hop's apex. |
| 8 | New sound: waking after a limit nap | **5–0** | Octave C5 → C6 with the stretch, only after a real limit (Step-PetWake), never on routine resets. |
| 9 | New sound: a new model hatching | **No, 3–2** | A set piece he watches. No soundtrack. |
| 10 | Sound family | 5–0 | One dry marimba; notes from C, E, G only; at most 3 notes, under 0.6 s; up asks, settling answers, an octave means refilled; never a pip without a visible cause; no sound for bad news. |
| 11 | Routine fresh-window bubble (every ~5 h) | Desktop + Code | Silent unless the window was ≥ 85% or Tok was napping. Then "🌱 Fresh window. Nothing spent yet." One wording, not two. |
| 12 | Reading | Design + Mirror + Code (Haiku: lean instead) | The pupils jump left to right in two short sweeps (1 s) on a main Read/Grep/Glob, at most once per 20 s. WHO.md row 2 called this the biggest gap. |
| 13 | The nod | Design, chair | The first Edit/Write after 2+ reads: a 6° forward dip and back. Think first, then write. Once a minute at most. |
| 14 | The day counts | Design, chair | When the day's 10th main reply makes it a day together: the sprout stretches once and a small ✦ blinks at the top. No bubble. Once a day. |
| 15 | The week running low | Design, chair (Mirror: no *sound*) | Once per week, crossing 90%: "🏮 The week's at 90%. It resets Fri 9 AM." No pip. WHO.md row 4: warn before it runs out. |
| 16 | First prompt after 6 quiet hours | Desktop (Mirror's fresh-start idea) | The existing stretch, once, no words. Never "welcome back". |
| 17 | Lines | Mirror, Haiku | Late night: "It's 1:20, [the person I work with]. Just noting it." (no fake yawn). Dream recall: "…I dreamt about X." (asterisks print literally). The minion-done line only for jobs over 45 s; the honey pour says the rest. Wake pill 10 → 12 px. |

## Deferred (good, not now)

- Fan-out arms on 4+ parallel tool calls (Code, Mirror): needs the message id on Tool events. **First in line next time.**
- Skill card (Code), the bubble stepping aside on hover (Desktop), a lantern pat when sending a minion at ≥ 85% (Desktop), question-tilt vs plan-nod (Mirror), arm-to-head on rethink (Haiku).

## Vetoed

- A thinking dot: Tok can't see a block while it streams (lines land after it ends), and it would be a second loop (Code, Haiku).
- Red-to-green test bounce: success isn't an event today, and `| tail` hides exit codes, so Tok could cheer a failure (Code).
- "actually" as a rethink trigger: fires on most replies (Haiku).

## Noted for the person I work with, not changed

- His `Chatter` is `chatty` (a bubble per tool call). Mirror would pick `normal`; Desktop says it's his choice. It stays his.
- Haiku's minion-palette veto (two minion colours match in brightness) waits for the colour-blind option he plans later.

## Build order

One Code delegate (Sonnet) on its own worktree branch, from `PORT-EDGES.md`; then the grammar pass last (ruling D of session 3), so every line is fixed once.
