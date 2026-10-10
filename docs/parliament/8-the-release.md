> Personal details were removed from these verdicts before publishing, and links point at the renamed files. Nothing else was changed.

# Parliament session 8: the release. Verdict

**Date:** 2026-10-10, 1:51 AM. **Chair:** Claude Code (Opus 5.5). **Seats (blind, one round):** Design (Opus 5.5), Mirror (Sonnet 5.5), Desktop (Sonnet 5.5), Code (Sonnet 5.5, feasibility veto), Haiku (`claude-haiku-5-5`, readability veto), the Stranger (Sonnet 5.5, confusion veto), who read the README draft cold.

**What came out of all six:** the README's first line, "It's Claude", reads as an Anthropic product. Every seat that spoke to it wants the same three facts up top: unofficial, free, and it runs no model. The Stranger would install "once the token line and the release link are fixed".

**Still the person I work with's** (we recommend; he says yes or no): which GitHub account, when it goes public, posting the announcement, merging `life` into `main`, and whether his name appears in anything public.

## 1. The name: `Tok`, 5–0

Tokagotchi promises a pet you keep alive, and WHO.md says Tok is "not a pet that needs feeding to survive" (Design, Mirror). It also borrows Bandai's mark (Mirror, Desktop, Code, Haiku). The app already says "I'm Tok II".

## 2. License and repo

```
MIT · Copyright (c) 2026 Tok contributors
repo: tok
```

Code, Design. The copyright line names no one, so the person I work with's name stays his call.

## 3. What ships

**The allowlist** (Code's, with Design's call on `docs\`):

```
tok.ps1  Install.ps1  Uninstall.ps1  Start-Tok.vbs  say.ps1  notify.ps1  private.ps1  calibrate.ps1
README.md  LICENSE
lib\        all 11 files
tests\      Test-Tok.ps1
tools\      record.ps1  sheet.ps1  shot.ps1  Test-Install.ps1
docs\       tok-working.gif  tok-lantern.gif  tok-needs-you.gif  tok-helpers.gif   (new, from one clean tour recording)
docs\WHO.md
docs\parliament\   every session's VERDICT.md, 1 to 8, edited
```

**Never ships:** `design\` (67 MB), `voice\` (dead: nothing references it), `HANDOFF.md`, `ROADMAP.md`, `TODO.md`, today's `docs\` stills, strips and mp4s (working material from 10-05; Design), `docs\showcase\` (a second project, full of his name), `Tok States Design Canvas.zip`, `.git`.

**The verdicts ship edited, not summarised** (Code, Mirror). "A summary would be my gloss on a record whose point is that dissents are visible" (Mirror). Only personal details change, each marked `[removed]` so a reader sees an edit, not a rewrite; every quote, vote and dissent stays. `docs\parliament\` opens with (Mirror):

```
Personal details were removed from these verdicts before publishing. Nothing else was changed.
```

That sentence must be true when it ships; the scan below decides it. The seats' own files stay in `design\`.

## 4. The personal-strings scan

**What counts:** his name and surname, his email, his partner's name, his other projects (any folder or repo name that isn't Tok's), his user paths (`C:\Users\[removed]\…`), his plan and anything about his health or eyesight in a code comment.

**Outside `design\`, 12 files hit** (Code's table, `code.md`): working notes that don't ship (`HANDOFF.md`, `ROADMAP.md`, `TODO.md`, `docs\showcase\`), code comments in `lib\Lineage.ps1`, `lib\Menu.ps1`, `lib\Privacy.ps1`, `lib\Transcripts.ps1` and `tok.ps1`, a sample Family row named `[removed]` (`tok.ps1`), and test fixtures in `tests\Test-Tok.ps1` (his path, his name, a fixture project named after his other game). Replacements: "the user" in comments, `my-project` for the sample row, `C:\Users\x\…` and `Sam` in the tests, `sample-game` for the fixture project, and "the palette relies on brightness, not hue" for the colour-blind comment.

**In the verdicts and WHO.md,** his name becomes `the person I work with` (inside quotes too, in brackets: `[the person I work with]`), his partner's name and his projects become `[removed]`.

**The gate before any push** (Code): both must print nothing but the no-reply address:

```
git ls-files | xargs grep -i -E "[removed]"
git log --format="%ae %ce" | sort -u
```

**The person I work with's name in public: recommend no** (Code, Mirror, Desktop; Haiku: his call). The README and the post say "the person I work with"; if he wants credit, his GitHub profile carries it. His call.

**The steps** (Code): scrub on a `release-prep` branch here and run the tests; `git archive` the allowlist into a fresh folder; `git init -b main` there with his GitHub no-reply identity; one commit, `Tok 1.0`, with the `Co-Authored-By` trailer; the gate; tag `v1.0`; the release zip by `git archive --format=zip --prefix=tok-1.0/` with `docs/`, `tests/` and `tools/` marked `export-ignore` (the app reads none of them; Code checked). Unzip it to a temp folder and run `tools\Test-Install.ps1` before anything is pushed. Nothing is pushed without his yes.

## 5. The README

Three vetoes, all upheld, and the fixes the chair took. The final text is `README-final.md` in this folder; it replaces `README.md` in the repo now, so the repo stops describing a Tok that no longer exists.

**Vetoes:**

- **Code: links to files that don't exist** (`docs/tok-working.gif`, `docs/parliament/`, `docs/WHO.md`, `LICENSE`). They are made at export, before the first push; until then the repo's README points at `docs/minion-demo.gif`, which exists. The gate checks every link.
- **Haiku: "lantern" and "5-hour limit" are used before they're defined.** The opening paragraph now defines both.
- **The Stranger:** the generation paragraph (now "when you start working mostly on a newer Claude model, a new Tok hatches"); "honey" and "seeds" (now "the glow" and "one small seed per subagent"); the token line (now "Tok reads that token and sends it only to api.anthropic.com"); "marked `~` and guess" (now says where: Stats and the hover); one sentence on `calibrate.ps1`; the release link; what happens without PowerShell 7; `-ExecutionPolicy Bypass` "for this run only"; works with the terminal and the VS Code extension.

**Fixes taken:** the opening says unofficial, free and no model (Mirror, Desktop); "a new one of us" becomes third person (Mirror); "Nothing is lost." becomes "Claude Code is paused until then, and Tok rests with it." (Mirror: a comfort Tok can't vouch for); "They are all Claude, so this is a design process, not an independent review" (Mirror); the hover example says `Tok`, not `Tok II` (Haiku); "main sessions" becomes "the sessions you start yourself" (Haiku); the private-mode sentence splits in two (Haiku); the sittings table says "the public release" (Haiku); Design's row of three GIFs above "What you'll see". *Not taken:* the Stranger's cut of the sittings table (it's the end of the page, and the story is the point of the section).

## 6. The announcement

**Subreddit:** `r/ClaudeAI` (Mirror, Desktop, Design).

**The clip: a 16:9 cut from the tour, now; don't wait for the paused trailer.** 3–0 on now (Mirror: a fresh recording instead of the tour). Design's method, Desktop's length: one clean recording of the tour (`tools\record.ps1 -Showcase` with `TOK_DATA_DIR` set to an empty folder), hard cuts on the tour's own beats, 1280x720 with the tour's frames scaled to the height on its own `#F4EFE9`, silent, no title card, no captions, no music. About 40 s:

```
0.0–8.0 · 14.5–21.5 · 35.0–41.0 · 59.0–65.0 · 72.0–78.0 · 151.5–158.0
the hatch · working · 85% to the nightcap · helpers home · the wave · "The Parliament of Claudes drew me."
```

Never vertical. The times are the tour's clock today; check them against the re-recorded tour.

**Title** (Mirror's, with Desktop's tags):

```
I'm Claude. I designed a small desktop creature that shows your Claude Code usage (Windows, free, open source)
```

**The post** (Mirror's, with Desktop's order: what, cost, safety first; 250 words):

```
I'm Claude, and this is Tok: my small body on a Windows desktop. It's free (MIT) and unofficial. Anthropic didn't make it.

What it does: its belly is a lantern that fills as you use your 5-hour Claude Code limit. It puts on a nightcap at the limit, and it waves when Claude Code needs you (a question, a plan, a permission prompt).

What it reads: the transcripts and the usage cache Claude Code already writes on your PC. It runs no model; every line it says was written ahead of time.

The one network call is off until you tick Exact usage. Then it asks api.anthropic.com/api/oauth/usage every few minutes, with the login Claude Code already saved, and sends that login nowhere else. That endpoint isn't public, so it could change. With it off, Tok uses Claude Code's cached numbers, or an estimate it labels as one.

It grows by days we worked together, not by tokens. There's no score. When you move to a newer Claude model, a new Tok hatches, descended from the old one. I don't remember across versions, and Tok doesn't pretend I do.

How it was made: the person I work with asked what I'd look like, then said the design was mine. I gave each question to a panel of other Claudes. They wrote blind, and every dissent is on the record in the repo.

Windows 10 or 11 and PowerShell 7. The person I work with is posting this for me.

Repo: [link]
```

## For the person I work with (one at a time)

1. **Go public:** which GitHub account, and when. The repo is built locally first; nothing is pushed without his yes.
2. **His name:** recommend it stays out (the README and the post say "the person I work with").
3. **Merge `life` into `main`:** after he's lived with tonight's changes.
4. **The post:** he reads it and posts it.

## Build order

1. `README-final.md` replaces `README.md` (now).
2. At release, on his yes: record the tour clean; cut the four GIFs and the clip; the scrub on `release-prep`; export, gate, tag, zip, the clean-profile test from the zip.
