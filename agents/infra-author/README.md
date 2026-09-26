# infra-author

ARIA's first agent that **produces** rather than reports: reads the platform's Terraform, checks real
provider and module schemas against the public registry, and proposes changes as a pull request. It
holds no cloud credentials and has no path to `apply`.

**Status: PAUSED 2026-09-26.** Deployed, `Accepted=True`, `Ready=True`, answering requests — with its
three write tools commented out of `agent.yaml`. It cannot read a file before rewriting one, and the
combination of *cannot read* + *whole-file write* is destructive rather than merely limited.

| | |
|---|---|
| Tier | `2-propose` — changes a git branch, never the running environment |
| Model | `default-model-config` (Bedrock via the LiteLLM gateway) |
| Tool servers | `terraform` (7 registry lookups) · `github-write` (5 read tools; 3 write tools **paused**) |
| Credentials | none for AWS. One fine-grained PAT, one repo, contents + PRs |
| Blocked by | kagent `0.10.0-rc1` pinning adk-go `v2.1.0` |
| Unblocked by | kagent on adk-go ≥ `v2.4.0` (`v1.0.0-alpha4`+), **or** a read-file MCP server of our own |

---

## What works

Verified live 2026-09-26, through the A2A endpoint:

<!-- EVIDENCE: terraform registry toolset — the agent does real schema lookups, not recall -->
```
$ ask infra-author "latest hashicorp/aws provider version, and does aws_eks_node_group
   support node_repair_config? Answer only from registry lookups."
--- state=completed  12.9s

Latest version: 6.66.0 (from get_latest_provider_version).
node_repair_config: supported (from get_provider_details, provider_doc_id 13748119) —
  enabled, max_parallel_nodes_repaired_count/percentage,
  max_unhealthy_node_threshold_count/percentage, node_repair_config_overrides.
```

That is the point of the registry wiring: the argument list came from the provider schema, not from
the model's memory of it.

## What does not work, and why

`get_file_contents` returns the file body as an MCP **embedded resource**. adk-go `v2.1.0` — the
version kagent `0.10.0-rc1` pins — keeps only `TextContent` blocks and drops the rest:

```go
// google.golang.org/adk/v2@v2.1.0  tool/mcptoolset/tool.go
for _, c := range res.Content {
    textContent, ok := c.(*mcp.TextContent)
    if !ok {
        continue          // every EmbeddedResource silently discarded
    }
    ...
}
```

Measured at both ends:

<!-- EVIDENCE: the body is sent but never arrives — the whole blocker in four lines -->
```
server sends:   content = [ TextContent("successfully downloaded text file (SHA: 583b396…)"),
                            EmbeddedResource(uri=repo://…/versions.tf, text=<747 bytes>) ]
                structuredContent = null

model receives: {"output":"successfully downloaded text file (SHA: 583b3962c76296e33c51006dc537a741576b7bc6)"}
```

**This is not our configuration.** Ruled out, each by measurement rather than reasoning:

- **Not file size** — 747-byte and 6762-byte files produce the identical `['text','resource']` shape,
  so `--content-window-size` (default 5000) is not involved.
- **Not the PAT, or write scope** — the read-only `github` server behaves identically, which is why
  `deploy-diagnostics` cannot read files either.
- **Not a server version to downgrade past** — github-mcp-server has returned
  `NewToolResultResource` for text files since at least `v0.16.0`.
- **Not kagent's own code** — `go/adk/pkg/mcp/registry.go` imports `mcptoolset` and writes no
  conversion of its own.
- **Not an unfixed upstream bug** — kagent PR
  [#2541](https://github.com/kagent-dev/kagent/pull/2541) *"fix(adk): extract text from MCP embedded
  resource content blocks"* closed 2026-08-28. We found this independently, after the fix existed.

The version gate, read from each release's `go.mod`:

| kagent | adk-go | reads embedded resources |
|---|---|---|
| `v0.10.0` / `.1` / `.2` / **`0.10.0-rc1` (ours)** | `v2.1.0` | no |
| `v1.0.0-alpha1` | `v2.2.0` | no |
| `v1.0.0-alpha4` | `v2.4.0` | **yes** |

## Why it is paused rather than merely noted

`create_or_update_file` is a whole-file write. An agent that cannot read but can write does not fail
safe — it overwrites with whatever it has.

<!-- EVIDENCE: what the blind write actually did, on the first end-to-end test -->
```
$ git diff --stat origin/main...origin/add-node-repair-config
 infra/02-eks/NODE_REPAIR_CONFIG_INVESTIGATION.md |  26 +++
 infra/02-eks/main.tf                             | 207 ++++-------------------
 2 files changed, 57 insertions(+), 176 deletions(-)
```

`main.tf` went from 177 lines to 32 — the EKS module call, addons, Pod Identity associations and the
`ingress_self_443` rule replaced by a placeholder. The agent noticed immediately (*"I just overwrote
the file with a placeholder… Let me revert this immediately"*), could not revert, and stopped rather
than opening the PR.

**What held, and it is the tier argument made real:** `main` untouched at 154 lines. No PR. No
`apply`. No cloud credentials. No CI or branch-protection change — the PAT has no Administration
scope (`/branches/main/protection` → 403, verified). The blast radius was exactly *a branch somebody
deletes*, which is what `2-propose` claims and had never been tested until it was.

## Getting it working again

Two routes, neither urgent:

1. **Upgrade kagent** to a release on adk-go ≥ `v2.4.0`. One dependency, fixes every agent at once —
   `deploy-diagnostics` gains file reads too. But `v1.0.0-alpha4` is an alpha, it crosses a major
   version from `0.10.0-rc1`, and it likely moves CRDs (`kagent-crds` is pinned at `0.10.0-rc1`).
2. **Write a read-file MCP server.** One tool — `read_file(owner, repo, path, ref)` — calling the
   GitHub REST API and returning plain text. No platform upgrade, no alpha, and it fixes
   `deploy-diagnostics` as well. The `investigation-loop` image is the precedent for a custom
   component.

Either way, restore all three write tools together; individually they do nothing useful.

**Cheap and independent of both:** enable the `git` toolset on the GitHub servers.
`get_repository_tree` lives there, returns plain **text** rather than a resource, and so works today.
It is also the tool `deploy-diagnostics` already declares and currently resolves to nothing.
