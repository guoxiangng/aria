# Evidence — two isolation runtimes installed, neither headline feature held up

- **Captured:** 2026-08-16 → 2026-08-18 · kagent 0.10.0-rc1 · Agent Substrate + Agent Sandbox both running
- **Source:** `docs/execution-environment.md` §§10-11 (full technical record)
- **Establishes:** both platforms install and run real workloads on EKS. The two things they are chosen
  *for* could not be observed working.

This is the entry worth reading. Everything else here is something that worked.

## What was built

Both isolation backends installed side by side, GitOps-managed, each with a probe agent reaching a
genuine `Ready: True`. Getting there took four real bugs beyond the known registry issue: a stale
`ActorTemplate` never garbage-collected, a **shared `WorkerPool` across both platform selectors**, a
dangling orphan object, and a missing runtime image.

## Finding 1 — Substrate never suspended

Agent Substrate's headline capability is suspending idle actors to reclaim resources. `substrate-probe`
sat **genuinely idle for over two days** and was never observed suspending. Not a misconfiguration that
was then fixed — an expected behaviour that did not occur.

## Finding 2 — Agent Sandbox's isolation was accepted but unenforced

Two separate claims, both configured, neither effective:

- **Network egress allow-list** — present in the spec and accepted by the API. A live test reached
  `example.com`, which was *not* allow-listed. Istio was ruled out as the cause.
- **Kernel isolation** — `kubectl get runtimeclass` returns nothing. **No `RuntimeClass` exists on the
  cluster at all**, so no gVisor or Kata sandboxing was ever actually provisioned. Getting it active
  needs node-level runtime-handler installation: real infrastructure work, not a CRD field.

This also **corrects an earlier claim of my own** from 2026-08-07, where network-deny was recorded as
verified. It wasn't — only the schema text had been read, not the behaviour tested.

## What this says about reading schemas

A CRD field that accepts a value proves the API accepts it. It does not prove anything is enforcing it.
Both of these configs applied cleanly, reported healthy, and did nothing — which is the same silent
failure shape as the eval harness that saw no tool calls and the deny test that bypassed the mesh.

## Scope

One cluster, 2×t3.large, stock EKS node groups, the versions above, measured over days not weeks. Both
projects move fast; these are **dated observations, not permanent properties.** Re-test before relying
on either.
