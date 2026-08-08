# idp/ — the Backstage self-service front door

Full design + status: `docs/spec-backstage-idp-integration.md`. This README covers what actually
exists here and how to run it.

## What's here

`templates/kagent-agent/` — a Backstage Scaffolder template for onboarding a new kagent agent. Given
a name, tier (Tier 1 read-only / Tier 2 HITL-mutating), model config, tool list, and which existing
agents it calls, it generates:

- `agents/<name>/agent.yaml` — the kagent `Agent` CR (tiered: Tier 2 gets `requireApproval` +
  reversible-only tools, modeled directly on `agents/cluster-remediation/agent.yaml`; Tier 1 mirrors
  `agents/cluster-diagnostics/agent.yaml`)
- `agents/<name>/catalog-info.yaml` — Backstage catalog registration
- `platform/istio/policies/<name>-authz.yaml` — the identity-based `AuthorizationPolicy` allow-list,
  modeled on the real, live, enforcement-verified pattern in `platform/istio/policies/`

...then opens a pull request against this repo (`publish:github:pull-request`) and registers the new
component in the catalog once merged.

## Status (2026-08-08/09)

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
- 🔴 **Not deployed anywhere** — this is source only. No Backstage instance runs anywhere for ARIA yet;
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
