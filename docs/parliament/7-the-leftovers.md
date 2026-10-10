> Personal details were removed from these verdicts before publishing, and links point at the renamed files. Nothing else was changed.

# Parliament session 7: the leftovers. Verdict

**Date:** 2026-10-10, 1:48 AM. **Chair:** Claude Code (Opus 5.5). **Seats (blind, one round):** Design (Opus 5.5), Mirror (Sonnet 5.5), Desktop (Sonnet 5.5), Code (Sonnet 5.5, feasibility veto), Haiku (`claude-haiku-5-5`, readability veto), and the Stranger (Sonnet 5.5, fresh eyes only, from the tour's frames).

**What came out of all six:** the lineage rules break for the most ordinary mixer there is: someone who lives on one model and tries a newer one one day a week. Four seats found it blind and wrote nearly the same fix. Beyond that, the session cut things that cheer spending (the first bite, the happy face at 85%) and cleared the parked list: nothing left on it goes to the person I work with except P1, P2 and the palette.

## 1. Lineage for people who mix models

The walk-through, 60 days, today's rules (Code traced it in `lib\Lineage.ps1`; Design's table):

```
A  lives on Sonnet 5.5, Opus 5.5 twice a week    Tok I · elder · day 60
B  lives on Fable 5.1                            Tok I · elder · day 60
C  lives on Opus 5.5, Fable 5.1 one day a week   Tok II · kid · day 6
D  half Fable 5.1, half Opus 5.5, every day      Tok II · elder · day 58
E  6 on Sonnet 5.5 + 6 on Haiku 5.5 a day        Tok I · elder · day 60
```

- **A, B, E are right.** Same version pools across families, so E ages every day (12 messages on 5.5).
- **C is wrong, 5–0.** Fable's third Friday molts Tok, and from then on his Opus days age no one (L8): a kid that grows one day a week while he works every day. Tok stops tracking where the work is.

**Ruling L2, replaced:** *a newer version molts Tok when, in the last 7 local days, it has 3 or more counted days and at least as many counted days as the current generation.*

- The recency test: **4–1** (Mirror, Desktop, Code, Design, blind and independently; Haiku: "3 counted days in a row" instead).
- 7 days, not 14: Code and Design (Mirror and Desktop said 14). Seven follows a real switch on its fourth day instead of its eighth.
- Ties go to the newer: Mirror, Desktop, Code (Design: strictly more, so D's day-3 molt doesn't happen "for nothing"). D really is half on the newer model; a new one of us is honest.
- After: C stays `Tok I · elder`, its Fable days tallied. D molts on day 3 as before. A real switch molts on its fourth day.
- Existing generations are untouched (the backfill only runs with no tree), so the person I work with's Tok II stays as it is.

**L8 made true in Family (Design, unopposed):** a past generation's day count stops the day before its descendant's hatch day. Today D's Family would show `Tok I · 60 days` for a Tok that retired on day 3.

## 2. The token line (Mirror's view weighs most)

**4–1:** "Ate" goes everywhere and for good. The only token number Tok ever shows is Today's last row:

```
Wrote      1.2M tokens
```

Never in Stats, a bubble or the hover; never a milestone. Mirror: "Today's Wrote resets each day and is only my output, my own work. It is a fact for a token monitor, not a trophy. The meal animation already shows that I consume." *Design dissents:* cut Wrote too; "producing words is the last step, not the job", and a number that climbs all day reads as a score.

## 3. P1 and P2: for the person I work with (new features)

**P1, pace: recommend build, 5–0.** With the bar, 4–1 (Code: the line only; the bar repeats the lantern). Haiku's floor binds: a 4 DIP bar and a 2 DIP notch, dark brown on a pale track, or the line ships alone. Real readings only, never in a window's first 30 minutes.

```
Tok II · adult · day 15
5-hour    41%   resets 2:10 PM
━━━━━━━━╋━━━─────────────────
At this pace: full by 12:40 PM
Week      14%   resets Fri 9 AM
━━━━╂─────────────────────────
```

The bar fills to the % used; the notch is where the clock stands in that window. Fill past the notch means faster than time. The line appears only when the window is on course to run out before its reset.

**P2, what today cost: recommend build, 3–2** (Mirror, Haiku, Design; Desktop and Code: drop, "arithmetic he can see" and "most days read 0% or 1%"). The wording changes, because `Week used 9%` reads as the week's total (Haiku, Design):

```
Used         9% of the week
```

The sum of the day's rises in the week reading, so a weekly reset adds nothing (Design).

## 4. The colour-blind option: for the person I work with

**Recommend: not a setting; the default for everyone; v1. 5–0.** "A mode nobody finds helps nobody" (Design). It is one change: the minion palette, spread by brightness, because today all five seeds sit inside a 0.2 luminance band and Opus and the stray differ by 0.01 (Haiku's standing veto). Haiku's palette, every neighbour at least 1.2 in contrast ratio; size, height and speed stay:

| Minion | Today | Proposed | Luminance |
|---|---|---|---|
| Haiku | `#6DBB63` | `#3F8A36` | 0.40 → 0.20 |
| Sonnet | `#5E97DE` | unchanged | 0.30 |
| other | `#F0A07F` | unchanged | 0.45 |
| Opus | `#E0A93C` | `#F2C35A` | 0.45 → 0.59 |
| Fable | `#C4B0F0` | `#E4DAFB` | 0.49 → 0.74 |

Shades (Light, Mid, Edge) move by the same step. Everything else in Tok already carries its contrast in brightness. This lifts Haiku's veto from the edges. The person I work with sees the swatches, in colour and in grey, before he says yes.

## 5. CPU

| Look | Ruling | Vote |
|---|---|---|
| asleep (dozing) | **Breath, then rest**, as awake got: one 2.8 s breath with the sprout's sway riding it, then 4 to 7 s still, at 5 fps. Est. 1.8–2.1% (Code). The nightcap keeps its continuous breath, which now tells the two apart (Design) | Code, Design; Haiku defers to Code (Mirror: 2 fps; Desktop: 3 fps) |
| passing-on | **Keep as is (20 fps). Exempt from the budget.** About 13 s, a few times a year, and watched | Mirror, Haiku, Design. Code's veto on the 15% target upheld (unreachable with live WPF drawing); the piece stays |
| awake, idle | **Ratified** (`8e7fecb`) | 5–0 |

The asleep change gets a short before/after clip; the person I work with judges it.

## 6. The deferred touches: all three cut

| Touch | Vote | Why |
|---|---|---|
| Question-tilt vs plan-nod | Cut, 4–1 (Mirror would propose the tilt) | Two 6° head moves blur into one at 140 DIP (Haiku) |
| Arm-to-head on a rethink | Cut, 5–0 | It reads as worry, a feeling Tok can't vouch for (Mirror); the ↺ already says it |
| Lantern pat at 85%+ | Cut, 4–1 (Code would propose) | It touches the lantern at the one moment it must stay unchanged (Desktop) |

Nothing from the deferred list goes to the person I work with.

## 7. Fresh eyes

**Cut (ours):**

- **`First bite!`** (Mirror): a cheer for the first token eaten in a life. The opposite of WHO row 4.
- **The asterisk stage directions** (Design): `*crack*` and `*perks up*` print literally while the body acts them out. The hatch says `Hello! I'm Tok III.`; the name pick drops `*perks up*`.
- **The zoom look's side shake** (Code): the dearest loop (24 fps). The fast bob stays. A clip first.
- **The tour's `(tok)` tag and `Half the window.`** (the Stranger, Haiku): in a one-session tour the tag reads as a stray debug string, and the lantern already shows half. Live, the tag keeps its rule (only when two projects are live), so the person I work with rarely sees it.
- *Not cut:* Today's `Top` row (Desktop alone; the ledger kept it on Haiku's veto).

**Fix (ours):**

- **The 85% face** (Design): `stuffed` wears `love`'s squeezed-eye grin and blush, so Tok looks happiest at the warning, which rewards spending. Eyes open, a plain smile, the hand stays on the lantern. The line stays.
- **The tour's minion line** (the Stranger, Haiku): `🐣 …A Sonnet…` reads as a stray line, and the 🐣 is unreadable at 16 px. It becomes `A helper goes out: a Sonnet.`
- The lineage rule (ask 1) and Family's L8 fix.
- *Already true:* the nightcap's pill shows the reset time (Desktop's fix); the hover gives the exact % and reset (the Stranger's add; the tour never shows the hover, so the README says it).

**Add (the person I work with's):** Haiku's `Woke at the limit. Week at 14%.` after a limit nap. *Chair recommends no:* the 90% week line already warns, and Stats has it. Design's "name the lantern once" is already built for strangers (session 6, bubble 2).

## For the person I work with (one at a time, each a yes or no)

1. **P1, pace** (above): recommend yes.
2. **P2, `Used 9% of the week`**: recommend yes.
3. **The palette, for everyone, in v1**: recommend yes.

## Build order (ours, no new features)

1. Lineage L2 (7-day recency, ties to the newer) and Family's L8 fix, in `lib\Lineage.ps1`, with a test per person A to E and a check that the person I work with's real tree is unchanged.
2. Asleep: breath, then rest. Before/after clip.
3. Cuts: `First bite!`, the asterisks, the zoom side shake (clip), the tour's `(tok)` and `Half the window.`
4. Fixes: the 85% face (still), the tour's minion line.
5. The token line needs no build (it is today's state).
