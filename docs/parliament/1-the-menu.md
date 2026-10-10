> Personal details were removed from these verdicts before publishing, and links point at the renamed files. Nothing else was changed.

> **Superseded the same night** by the generative session: [2-the-look.md](2-the-look.md) (the blooming sprout). This file is kept as the record of the menu-pick round.

# The Parliament of Claudes: verdict

- **Date:** 2026-10-05, night.
- **Chair:** Claude Code (Opus 5.5).
- **Delegates:**
  - Code, the Builder (Sonnet), with a feasibility veto
  - Design, the Artist (Opus)
  - Desktop, the Companion (Sonnet)
  - Haiku, the Glance (Haiku), with a readability veto
  - Mirror, the Self (Sonnet)
- **Question:** `design\canvas\REVIEW-PROMPT.md`. Which direction goes forward: glow concepts A, B, C or D, a hybrid, or Round 5?
- **Record:**
  - `round3\` holds the blind answers to that question.
  - `round1\`, `round2\` and `VERDICT-v1-stale-brief.md` answered the older PROMPT.md, before the canvas arrived. They're kept because most of their rulings carry over.

## Decision: B, Tok lit from inside. 5–0, blind.

**Why.** It's the only option that stops Tok getting fat without changing who Tok is: same eyes, sprout, arms, feet and orange. The meter becomes warmth instead of weight. Mirror put it this way: *"Claude doesn't get fat, it runs hotter."*

**Who lost most:**
- A and D are character redesigns presented as meter options. Both swap the sprout for a flame.
- C reads best at 1×, but it looks like a gauge glued onto a mascot: "orange shorts."
- Round 5's widening belly drifts toward a plush toy.

**The vibe:**
> A small orange sprout who lives on your title bar, eats your token budget, and is quietly Claude.

## B's one weakness, and the fix it ships with

Every delegate saw the same two problems on their own:
1. **Fresh and half look alike at 1×.** On light windows the glow nearly vanishes, and Tok can read as "off".
2. **The red core at the limit, under closed eyes, reads as fever, alarm or anger.** Three of the five named this.

**The fix is a stepped glow ramp that changes size, brightness and warmth.** It is never zero and never red. Design leads the hues; Code and Haiku set the floor.

| Window | Core (on the belly patch) | Notes |
|---|---|---|
| fresh 0–25% | small warm ember, r ≈ 16, `#FFB45A` at 0.55 | **never zero**, so Tok never reads as off |
| half ~50% | 40×22, `#FFC46A` at 0.8, soft halo | |
| 85%+ | 74×38, bright `#FFE9A8` core, wide halo, **1 px warm rim** `#E8803A` | the rim keeps it visible on light windows |
| limit | **banked**: dim deep amber `#C8643A` → `#E8803A` at ~0.45, no halo | Tok puts the candle out to sleep. Rest, not warning |

- **Motion:**
  - The core brightens a notch on each bite.
  - The slow idle pulse is a WPF `DoubleAnimation` on Opacity.
  - Nothing animates per-frame.
- **Build (Code):**
  - `RadialGradientBrush` ellipses only, with **no BlurEffect**, which forces software rendering in a transparent window.
  - About 40 lines in `Update-Look`.
  - It deletes `Get-BellyScale` and the width stretch, so round 2's face-counter-scale wrapper is never needed.

## What carries over from the first verdict

| Ruling | Status |
|---|---|
| The face never stretches | **Satisfied by design.** Nothing stretches in B. |
| No lids and no frowns, anywhere (hungry, dizzy, chewing, worried and ouch get non-grumpy shapes) | **Binding** |
| Nothing animates per-frame; no minion trail | **Binding** |
| Coma: upright, face toward the viewer, clock at the right, no 78° rotation | **Binding**, now drawn the Round 5 way: arms flopped, no nightcap, no `z Z`, plus the wake-up stretch back to normal. The `z Z` was wrong. |
| Minions: no faces, cream pill label in ink | **Binding**, drawn the Round 5 way: **matte** motes with a colored dot in the pill. The glow now belongs to the meter, so the minions don't glow. |
| Eating: gape, chew, gulp, content | **Round 5 art as drawn** |
| Belly width ×0.86→×1.30, patch growth, sheen, cheek lerp | **Moot** |
| Separate Full and Stuffed faces (belly pat, `> <`, puffed cheeks, sweat) | **Moot.** Fullness is the glow alone, so the face stays Tok's normal attentive face all the way up. |

## Chair's rulings on the two loose ends

These two are worth a glance from the person I work with, because his later Design sessions may have decided them on purpose.

1. **Mouth at rest.** Round 5 dropped it: no mouth at rest, and a mouth only for eating, finishing or real moments. Code warns that a mouthless face plus a dim fresh state reads "blank."
   - **Ruling:** keep Round 5's choice. The never-zero ember answers the "is it on?" problem.
   - **Overrule if** the first-night smile is part of what you miss.
2. **Pumpkin.** Round 5 went "barely there": a tint, a curly stem, a candle belly, no paint. Design and Haiku say put the face paint back, because the person I work with asked for it directly on 10-05 ("an actual recolor, like face paint").
   - **Ruling:** Round 5 is the later direction, so ship it barely there, with the candle belly as the B glow, warm yellow.
   - **Overrule if** you still want the paint. The full paint spec is in `VERDICT-v1-stale-brief.md` and is ready to drop in.

## Next step

A full states pass in B, then port it into `tok.ps1`. The pass covers:
- the age × glow grid;
- eating;
- coma and stretch;
- minions;
- pumpkin.

The canvas source (`design\canvas\source\tok-art.js`) already draws B, so the port works from those shapes. Judge it on the live desktop, not on contact sheets.
