> Personal details were removed from these verdicts before publishing, and links point at the renamed files. Nothing else was changed.

# Tok, designed by the Claudes: final

**Date:** 2026-10-05, night.

**The process:**
1. Five Claudes (Design, Mirror, Desktop, Code, Haiku) each drew their own Tok from the origin.
2. They critiqued all five.
3. The chair synthesized.
4. Design drew the final.
5. Four checks raised three blockers, all fixed in one revision.

**This supersedes `..\VERDICT.md`,** which picked concept B from a menu.

## The idea

> **The 5-hour window is a day, and Tok's sprout blooms over it.** At the limit Tok sleeps beneath its closed flower. At the reset the petals fall and it's a seedling again.

Using the budget is growth, never harm. The body never widens and the face never strains. The reset is Claude forgetting, shown kindly. Tok still eats tokens, and that's what working looks like.

## The drawing

All of this is in `final\`. Regenerate it with `python final\gen.py`.

- **`meter.png`** shows the meter, which is the sprout:
  - 0%: a tiny seedling.
  - 25%: a tall stem with a third leaf.
  - 50%: a fat green bud.
  - 75%: the bud splitting open with gold.
  - 90%: a full gold flower.
  - Limit: Tok settled and curled up, with the closed bud upright like a tulip at night and the reset time in a pill.
- **`states.png`** shows the states:
  - rest: eyes on your work;
  - working: a forward lean and a stream of tokens into an "o" mouth;
  - half;
  - nearly full;
  - limit;
  - needs you: a hop, a wave and eyes on you, the only time Tok looks straight at the person I work with.
- **`extras.png`** shows idle sleep (distinct from the limit), eating a seed-minion, the `sonnet +143k` eaten label, minions as matte seeds orbiting, the reset with petals tumbling, and private mode with sunglasses.
- **`NOTES.md`** has the motion notes for each frame and the porting notes.

## Who contributed what

| From | Element |
|---|---|
| Mirror | the bloom-as-meter idea, the reset as forgetting, seeds as minions, the gaze rule |
| Design | the drawing, eating as working, the 75% split bud, the tulip-at-night limit, the reset pill |
| Desktop | the settled limit shape, the friendly-tap needs-you, smaller eye whites |
| Code | buildability (all WPF primitives, about 350–450 lines to port), the pill as a TextBlock |
| Haiku | the readability veto that forced the 0/25% split and the rest-vs-working split |

**The vote and the ruling.** The critique vote was 3–2 for Design's honey-belly seed. The chair ruled for the bloom because of where Tok sits: it lives in the bottom-right corner, so the top of its head is the part that shows. The bloom also carries meaning, where a generic gauge only measures spend. See `SYNTHESIS.md`.

## Dissents and the drawer

- **Code's `>▯` prompt chip** for needs-you was cut as clutter in the corner. It's the most terminal-native idea of the night, so it could come back as a `/tok` easter egg.
- **The honey belly window** (Design's own pitch) lost to the bloom.
- **The chair's note:** at 1× the upright closed gold bud at the limit can look a bit like a corn cob. It no longer reads as wilted, which was the blocker. The person I work with's eye decides whether it needs another pass.

## Next

Port `final\` into `tok.ps1`. That means replacing `Get-BellyScale` and the belly-patch meter with the sprout stages, then judging it live on the desktop.
