# site/ — ARIA product page (draft)

A single self-contained `index.html` — the product/brochure page for ARIA. Marked **draft**;
it's meant to be iterated as the platform is built, not a finished marketing site.

- **Self-contained**: all CSS inline, no external fonts/scripts/assets — opens directly in a
  browser or serves as a static file anywhere (GitHub Pages, S3, `python -m http.server`, etc.).
- **Themed**: respects light/dark via `prefers-color-scheme`.
- **Honest by design**: the roadmap distinguishes shipped (running on a live cluster today) from
  next/later (sequenced, not sold). Keep that distinction accurate as things ship — move items up
  the roadmap columns rather than overstating current state.

## Editing

Just edit `index.html`. When a roadmap item ships, move it from **Next** to **Shipped** and, if
it's substantial, consider whether it deserves its own section (the trust loop and eval-gated
delivery are the two that earned dedicated sections).
