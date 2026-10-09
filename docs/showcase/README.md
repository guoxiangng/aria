# Showcase — the shared content store

> **What this solves.** The product page and the articles both need the same things: diagrams, verified
> evidence, a live inventory. Before this existed, each was re-derived from prose every time the page was
> touched — two stages of generation, and the page drifted from reality within weeks, twice.
>
> **The rule: write it here once, consume it in both places.** A build thread that lands something
> demonstrable drops the artifact here. The site and the articles reference it. Neither re-invents it.

---

## What lives where

| Content | Path | Consumed by |
|---|---|---|
| **Diagrams** (SVG, self-contained + theme-aware) | `../../site/diagrams/*.svg` | the site (`<img>`), articles (embed or link) |
| **Evidence** — a proof, with the command, the real output, and what it establishes | `evidence/*.md` | the site's Evidence page, article evidence blocks |
| **Inventory** — what is actually running, captured from the cluster | `inventory.md` | the site's Fleet page, `ARCHITECTURE.md` §2 cross-check |

Diagrams live under `site/diagrams/` rather than here because **GitHub Pages only publishes `site/`** —
anything outside it isn't servable. This file is their registry; that directory is their home. One copy,
no duplication.

## Rules

1. **Public repo — scrub before you write.** No AWS account ID, no internal hostnames, no tokens, no
   employer-internal references. Use `<ACCOUNT_ID>` and friends. This is why `ARCHITECTURE.md` stays
   local-only and this directory does not.
2. **Evidence is real executed output or it isn't evidence.** Paste what the command returned. Truncate
   with an explicit marker. Never tidy, never reconstruct from memory. Every file carries the date it was
   captured and the version it was captured against — a proof with no date is a claim.
3. **Negative results belong here too.** "Both runtimes installed, neither headline feature held up" is
   the most valuable kind of entry and the kind nobody else publishes. Don't quietly drop a disproof.
4. **Diagrams must be self-contained.** Each SVG carries its own `<style>` with a
   `prefers-color-scheme` block, because an SVG loaded via `<img>` inherits nothing from the page.
5. **This store describes; it doesn't decide.** Build state stays in `_STATUS.md`; system shape stays in
   `ARCHITECTURE.md`. If an entry here and `ARCHITECTURE.md` disagree, the cluster settles it and both
   get fixed.

## For `/aria-sync`

Step 5 reads this directory instead of re-deriving prose. The flow is:

```
build thread ships something
      │
      ├─ writes evidence/<name>.md  (the proof, dated)
      ├─ writes site/diagrams/<name>.svg  (if it needs a picture)
      └─ refreshes inventory.md     (from live kubectl)
            │
            ▼
      /aria-sync step 5 → site pages + portfolio card
```

An evidence file that no page references yet is fine — it's banked, not lost. The reverse is not: a page
claim with no entry here is exactly the drift this store exists to stop.
