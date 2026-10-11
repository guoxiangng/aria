# Evidence — a budget cap that enforced nothing, and a fallback proven by kill test

- **Captured:** 2026-09-26 · LiteLLM gateway, all Bedrock, Pod Identity (no API keys)
- **Source:** `platform/litellm/README.md` — full decision record and version log
- **Establishes:** budgets only enforce with a database; cross-family fallback works; and correct
  routing costs *more* than not routing at this fleet's mix.

## 1. The cap that accepted every config and blocked nothing

Caps are per deployment (`max_budget` + `budget_duration`). Measured both ways, because the "before"
half is the finding:

| | Result |
|---|---|
| **Without a database** | `$0.000001/day` cap, 4 calls, **none blocked**. Same outcome for `router_settings.provider_budget_config` and for `rpm: 1`. Every shape accepted the config and enforced nothing. |
| **With Postgres** | call 1 answered, calls 2-4 **HTTP 429** — `No deployments available - crossed budget: Exceeded budget for deployment model_name: nova-micro ... 4.662e-06` |

Upstream states it in its own source, `proxy_server.py::_warn_budget_without_db`: *"the budget will NOT
be enforced and requests will never be blocked. Set DATABASE_URL"*. Nothing in the running system
signalled it.

**A config key being accepted is not the same as a control existing.** Same shape as Agent Sandbox's
accepted-but-unenforced network allow-list — found independently, a month apart, in different projects.

## 2. Fallbacks, proven rather than asserted

Four of six tiers cross to a **different model family** on the first hop (including the fleet's own,
`haiku-4-5 → nova-pro`); two stay in-family deliberately. A route was pointed at a non-existent Bedrock
profile — standing in for the Azure resource deleted on 18 September — and the request was **served by
`nova-micro` instead of failing**.

Had this existed then, that outage would have been a quality degradation instead of four dead agents,
seven broken ones, and six days before anyone noticed the chart-managed built-ins were still pointed at
the dead resource while reporting `Ready: True`.

Fallbacks also make the caps safe: a tier that hits its budget is filtered from the pool and a fallback
catches the request, rather than the caller seeing a 429.

## 3. Two results that cut against the usual pitch

- **Correct routing cost 1.8× not routing.** A 30-prompt eval put the LLM classifier at 27/30 — but the
  classifier call is not free, and at this fleet's prompt mix it outweighs the cheap-tier saving. The
  classifier stays on haiku-3 precisely because 27/30 was measured *with* that classifier; swapping it
  for something cheaper would invalidate the result rather than bank a saving.
- **The first classifier escalated nothing.** A heuristic version was measured first and never escalated
  a single prompt — it would have sent everything to the cheap tier and looked like a win.
- **A real cheap floor exists:** `nova-lite` takes the SIMPLE tier at $0.063/1M in, roughly 4× cheaper
  than haiku-3. A second *family*, not just more models, is what gives fallbacks a non-vendor-locked
  destination.

## Open gap

All 11 agents share one master key, so at the gateway they are **indistinguishable and equally
privileged** — no per-agent attribution or limit. Per-agent virtual keys are the next increment; the
Postgres added here is their prerequisite.

## Scope

One gateway, one cluster, Bedrock only, a 30-prompt eval. The cost ratio is specific to this prompt mix
and these model prices — re-measure before carrying the 1.8× anywhere else.
