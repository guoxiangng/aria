# site/ — ARIA product pages (draft)

Two self-contained HTML pages, both draft, both iterated as the platform is built:

- **`index.html`** — the polished product/brochure page. Open-source, Kubernetes-native
  positioning; the "own every layer" + focused-scope angle, with the open-stack diagram and the
  eval-gated-delivery signature capability. This is the primary page.
- **`product-notes.html`** — an earlier, more internal-facing one-pager: the raw-kagent-vs-ARIA
  gap, the workflow diagram, rough user stories, and the cluster-admin RBAC finding as evidence.
  Kept as the terser "engineering notes" companion to the brochure.

Both are meant to be iterated, not finished marketing sites.

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
