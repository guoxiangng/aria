# idp/ — the Backstage self-service front door

Design: `docs/spec-idp-golden-path.md` (the golden-path brief, 2026-10-11) — supersedes the scope of
`docs/spec-backstage-idp-integration.md`, which stays the record for template mechanics. This README
covers what actually exists here and how to run it.

## Status (2026-10-18) — P1 catalog

- `backstage/values.yaml` — Backstage on EKS via ArgoCD (`gitops/apps/backstage.yaml`, upstream chart
  2.10.2, upstream image pinned by digest), namespace `idp`, one pod, in-memory SQLite, guest sign-in.
  Nothing built: the upstream example image already carries the catalog, scaffolder + GitHub module
  and guest provider (verified in-image: backend-defaults 0.18.0, scaffolder-backend 4.2.0).
- `catalog/all.yaml` — 27 entities: system `aria`, group `platform-team`, the gateway + 4 model
  configs, 7 MCP servers, 13 agents. Seeded from the live CRs. Each agent carries an eval-coverage
  tag (`evals` / `no-evals` / `eval-known-unevaluable`) — the first scorecard signal: 7 have suites,
  5 have none, incident-commander is known-unevaluable.
- Verified locally before deploy, same image + the chart-rendered config: ready in ~12 s, 27 entities
  ingested with zero validation errors, relations resolved, ~485 MiB at idle.
- Gotchas: the image's own `app-config.production.yaml` hard-wires Postgres, so `args` load only
  `app-config.yaml`; in production mode the guest provider needs `dangerouslyAllowOutsideDevelopment`;
  catalog `locations`/`rules` arrays REPLACE the image's examples (arrays don't merge across files).
- GitHub token: `backstage-github-token`, synced by ESO from `aria/github-pat-write` (reused — a POC
  trade-off recorded in `platform/external-secrets/manifests/externalsecret-backstage-github-token.yaml`).
  Authenticated catalog reads + the scaffolder's PR step. Read at pod start only — a new token value
  needs a pod restart.

Access: `kubectl -n idp port-forward svc/backstage 7007:7007` → http://localhost:7007 (Enter as guest).

## Status (2026-10-18) — P2 onboarding template

`templates/kagent-agent/` — rebuilt to `docs/spec-idp-golden-path.md` §5. The form asks for intent
(name, purpose, owner, data sensitivity, instructions, tier, model route, read tools, mutating tools
for tier 2, agents it may call, callers, 3–5 example questions). The PR it opens adds six files and
edits none:

| File | What the platform guarantees in it |
|---|---|
| `agents/<name>/agent.yaml` | `stage: sandbox`; system message **composed by kagent** (`promptTemplate`) from the platform fragments + the author's prompt; every mutating tool in `requireApproval` |
| `agents/<name>/prompt.yaml` | The author-owned instructions (ConfigMap) — iterate here, in git |
| `platform/istio/policies/<name>-inbound.yaml` | `kagent-controller` always allowed (the UI path), plus chosen callers |
| `platform/istio/policies/<name>-outbound.yaml` | One new ALLOW per callee + the LiteLLM gateway — Istio ORs ALLOW policies, so nothing existing is edited |
| `eval/<name>.promptfooconfig.yaml` | Groundedness gate + one case per example; reaches the agent via the controller's A2A proxy |
| `idp/catalog/agents/<name>.yaml` | Catalog entry, picked up by the glob location in `backstage/values.yaml` after merge |

Platform side, also in this change: `platform/kagent/prompt-fragments.yaml` (the shared guardrails,
synced by the `models` app). Editing a fragment re-renders every templated agent — the kagent
controller watches referenced ConfigMaps (verified in the v0.10.0-rc1 source) — so a guardrail fix is
not one PR per agent. That is the answer to "templates are one-shot".

**Verified (2026-10-18)** with Backstage's own dry-run API on the in-cluster instance (the real engine,
nothing published): a tier-2 case (2 callees, a caller, 3 examples) and a minimal tier-1 case both
rendered all six files; every Kubernetes object passed `kubectl apply --dry-run=server`.

**Design rules the form enforces, and why:**
- `callsAgents` offers only agents that already HAVE an allow-list (cluster-diagnostics,
  cloud-diagnostics, cost-sentinel). The first ALLOW policy on an open workload makes it deny everyone
  else — a grant to deploy-diagnostics would cut off incident-commander and the UI.
- Tools come from kagent's built-in tool server only (it has no allow-list). Offering AWS/GitHub MCP
  servers needs per-pair grants on their lists — next increment.
- `catalog-info` lives under `idp/catalog/agents/`, not `agents/<name>/`: the ArgoCD `agents` app
  applies every `agents/*/*.yaml`, and a Backstage entity is not a Kubernetes object.

**Not yet:** a real end-to-end run (form → PR → merge → running agent); the PR-time policy check and
stage-aware evals (P3) — CI evals have not completed since July (runner pods are outside the mesh,
and agents with allow-lists reject them); promotion (P4).

## The August template (superseded — kept for the record)

### Template status as of 2026-08-09 (historical)

- ✅ **Template logic fully built and validated** — every file rendered and parsed as valid YAML for
  both tiers, using the *actual* Backstage templating engine (Nunjucks configured with the real custom
  `${{ }}` delimiters, verified directly from `@backstage/plugin-scaffolder-backend`'s
  `SecureTemplater.cjs.js` — not assumed). Three real bugs were found and fixed this way: missing `$`
  prefix on loop variables (`${{ tool }}` inside `{% for %}`), on the catalog tag reference, and on the
  **templated filename** itself (`${{ values.name }}-authz.yaml`).
- 🟡 **Not yet run against a live Backstage server** — a local Docker-based instance was stood up and
  the backend confirmed reachable (real `401`, not a network failure), but submitting the form through
  the actual Scaffolder API needs either a browser session (guest login) or a `GITHUB_TOKEN` to script
  the call directly — neither was available in that working session (remote/mobile control). The
  template logic itself does not depend on this — it was validated independently against the real
  rendering engine, not through a live run.
- ~~🔴 **Not deployed anywhere**~~ (superseded 2026-10-18 — Backstage now runs in-cluster, see top) — this was source only. No Backstage instance runs anywhere for ARIA yet;
  standing one up (locally or otherwise) is a separate, later decision. See the spec's §5.4 (local-first
  recommendation) and §9 (deploy-layers.md compliance — an eventual real Backstage instance is a
  platform-layer, ArgoCD-managed concern, not a manual install).

## Known real gotchas (found the hard way, worth knowing before touching this again)

- **`create-app`'s own scaffolded `.yarnrc.yml` is version-drifted from the yarn release it pins** — it
  ships `npmMinimalAgeGate` / `npmPreapprovedPackages` settings that the pinned `yarn@4.4.1` doesn't
  recognize (`Usage Error: Unrecognized or legacy configuration settings found`). Fix: strip those two
  keys, keep only `nodeLinker` and `yarnPath`.
- **Backstage's dev server needs a Unix-like build environment** (`make`, `python3`, node-gyp for
  `better-sqlite3`/`keytar`/`isolated-vm`/`tree-sitter` native modules) — not available in plain Git
  Bash/PowerShell on Windows. Run it inside a Linux container (`node:22-bookworm` + `build-essential
  python3 git`) instead of fighting WSL.
- **`backstage-cli repo start --host 0.0.0.0` does not work** — `repo start`'s own arg parsing chokes
  on it (`Error: Unable to find package by name '0.0.0.0'`). Run `packages/app` and `packages/backend`
  as two separate `backstage-cli package start` processes instead (two containers, or two backgrounded
  processes) — `yarn workspace app start --host 0.0.0.0` is the correct level for that flag.
- **Docker Desktop on Windows + a bind-mounted volume makes the first compile very slow** (~10 min for
  the backend to go from process-start to actually listening) — this is disk I/O through the
  Windows↔WSL2↔container translation layer, not a real problem with the app. Budget for it; check
  `docker exec <container> ps aux` (state `Dl` = still doing real work, not stuck) rather than assuming
  a hang.
- **`permission.enabled: false` does NOT let you skip auth on raw API calls** — it only disables the
  *authorization* layer (are you allowed to do X), not *authentication* (do you have a valid token at
  all). A guest token still has to be obtained first.
