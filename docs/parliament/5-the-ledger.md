> Personal details were removed from these verdicts before publishing, and links point at the renamed files. Nothing else was changed.

# Parliament session 5: the ledger. Verdict

**Date:** 2026-10-09, night. **Chair:** Claude Code (Opus 5.5). **Seats (blind, one round):** Design (Opus 5.5), Mirror (Sonnet 5.5), Desktop (Sonnet 5.5), Code (Sonnet 5.5, feasibility veto), Haiku (`claude-haiku-5-5`, readability veto).

**The person I work with's instruction:** "The Council should decide how the lineage and stats work. If there's a new idea, discuss it amongst yourselves and present to me before implementing. I know this has a lot of potential but is also mainly a token monitor."

**What came out of all five:** the panels lead with the wrong numbers. The biggest number on screen ("Ate 435.1M tokens") is almost all cache reads and barely touches his limit, while the two numbers he actually watches sit at the bottom. And the lineage rule "versions only go up" breaks on the first model that numbers itself differently (Fable 5.1). The fixes: usage up top and nothing that reads like a score, and a molt is decided by the order Tok met the models, not by their numbers.

## Lineage

| # | Question | Vote | Ruling |
|---|---|---|---|
| L1 | What "a newer model" means | **5–0** | **Arrival order, not the number.** A version is newer if Tok first saw it after the current generation began. Fable 5.1 after Opus 5.5 is a new one of us. Works on a stranger's machine with no list to maintain. |
| L2 | What it takes to molt | Mirror, Desktop, Code (Design: 2 days; Haiku: 30 messages) | **3 counted days** (10+ main messages each) for the new version. Replaces the 30-message gate, which one afternoon clears. The 10-05 Haiku playtest (87 messages, one day) stays a tally. |
| L3 | Guard against going backwards | Design, chair | A version lower than one already seen **in its own family** never molts (Opus 4.1 after Opus 5.5 is a step back, not a descendant). Haiku's "Haiku never molts" not adopted: a family name to maintain, and L2 already stops trials. |
| L4 | When a new generation's age starts | Chair (from Code's migration note) | **The hatch day is day 1.** Without this, a descendant would hatch with 3 days already and skip the hatchling. Generations that exist today keep all their days (Tok II stays at 14). |
| L5 | The very first generation | Chair | No settling: the first version with a counted day is Tok I, and the egg's plain hatch is its moment (no passing-on). |
| L6 | Split days (6 messages on each of two versions) | **4–1** (Design: any model ages Tok) | Keep: a day counts only for a version that cleared 10 on its own. Honest and rare. |
| L7 | The day bar (10 main messages) | **4–1** (Haiku: 5 turns) | Keep. Low on purpose: age is days together, not effort (WHO row 7). |
| L8 | Going back to an old model after a molt | **5–0** | Never molts again, ages no one. True to "I don't come back". |
| L9 | Minions | **4–1** | Tallied per generation, never shown, never ancestors. |
| L10 | The word "replies" | **5–0** | Never on screen. In lineage code it is "messages" (comments only; the saved key stays `Replies`). |

## Family

```
Family · since Sep 16
 ◌   Tok I · Opus 5
     3 days · no body
 🌱   Tok II · Opus 5.5 · adult
     14 days · mostly at home
```

- **F1, keep (5–0):** the portrait, the last three generations, two lines each.
- **F2, a title (Design, chair):** `Family · since Sep 16`, the day Tok's records begin. Claude Code deletes transcripts after ~30 days, so this says honestly where memory starts.
- **F3, "no body" gets a dashed ring, no face (Design):** the blank slot today reads as a broken image. An empty outline is an honest absence.
- **F4, the project stays (3–2; Code and Haiku would cut):** "mostly at home" (not "in home"), dropped rather than truncated (a cut-off name reads as a typo), and dropped in private mode as before.

## Stats: the token monitor

```
Tok II · adult · day 14
5-hour     4%   resets 2:10 PM
Week      14%   resets Fri 9 AM
Read 6 min ago
```

- **S1, title (Mirror, Desktop, Code):** who, what stage, which day. Design wanted usage as the title; outvoted, but usage is now the first thing under it.
- **S2, a grid (Design, Haiku, Code):** label in muted brown, the number right-aligned so the % signs stack, then the reset. Brightness carries the contrast, not hue.
- **S3, the reading's age (Mirror, Desktop, Code):** a row only when the reading is 3+ minutes old. An estimate shows `~` on the numbers and the row says `Estimate, not a reading`. No window open: `0%   not started`.
- **S4, "Ate 435.1M tokens": cut (4–1).** Mostly cache reads. It isn't usage, and it grows like a score.
- **S5, "Naps at the limit": cut (5–0).** A count of hitting the wall. The nightcap already says it.
- **S6, "elder at 30": cut (3–2).** A countdown turns days together into a goal (WHO: not a scorekeeper).

## Today

```
Today · since 8:12 AM
Prompts      55
Turns       121
Tool calls  261 · 17 errors
Top         Bash 93 · Notion 70
Wrote      1.2M tokens
```

- **T1, the title says when counting began (Design):** Tok only counts while it runs.
- **T2, "replies" becomes "turns" (Mirror, Code, Haiku; Desktop: "answers"; Design: cut):** a turn is Claude finishing (`end_turn`).
- **T3, errors ride on the tool-calls row (Design).**
- **T4, the top two tools (Haiku's veto):** a third runs past the bubble.
- **T5, "Ate 36.8M tokens" becomes "Wrote 1.2M tokens" (Mirror, Desktop, Code; Haiku and Design: cut):** output only, the part that is Claude's own work. New per-day field; a day that started before it shows no row rather than a partial one.

## For the person I work with: new ideas, not built

All five seats, blind, proposed some form of **pace**. That convergence is the strongest signal of the session. The chair merged it into one proposal, plus Design's second idea:

- **P1, pace.** A thin bar under the 5-hour and Week rows, filled to the % used, with a notch where the clock stands in that window. Fill past the notch = spending faster than time. Shape, not colour. Words only when it matters: if the window is on course to run out before it resets, one line appears: `At this pace: full by 12:40 PM`.
- **P2, what today cost.** A Today row: `Week used   9%`, the week's % now minus the day's first reading. Today in the unit he budgets in.

## Build order

1. Lineage rules L1–L5 in `lib\Lineage.ps1`, with tests over the rules and a check that the person I work with's real tree comes out unchanged.
2. The three panels as grids (`lib\Pet.ps1` rows, `tok.ps1` draws them), Family's title and ring.
3. P1 and P2 wait for the person I work with.
