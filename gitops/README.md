# gitops/ — ArgoCD Applications (app-of-apps)

`infra/argocd` (Terraform) installs ArgoCD and points it at `root-app.yaml`, which syncs everything under
`apps/` by sync-wave:

| Wave | App | Source | Notes |
|------|-----|--------|-------|
| -1 | `namespace-bootstrap` | `charts/namespace-bootstrap` + `envs/dev.yaml` | agent namespaces (quota/limitrange/SA/RBAC) |
| 0 | `kagent-crds` | upstream OCI chart | CRDs (server-side apply) |
| 1 | `kagent` | upstream OCI chart + `platform/kagent/values.yaml` | operator + built-in agents |
| 2 | `models` | `platform/kagent/modelconfig-bedrock.yaml` | Bedrock ModelConfig CRs |
| 5 | `agents` | `agents/` | our InfraOps agents (later) |

Nothing is vendored — the kagent charts are referenced from `ghcr.io/kagent-dev/kagent/helm`.

## ⚠️ Pin the kagent chart version before first sync
`apps/kagent-crds.yaml` and `apps/kagent.yaml` have `targetRevision: "0.0.0"` placeholders. Set the real
version (both must match the chart release):
```bash
# needs helm:
helm show chart oci://ghcr.io/kagent-dev/kagent/helm/kagent | grep ^version
# or browse: https://github.com/kagent-dev/kagent/pkgs/container/kagent%2Fhelm%2Fkagent
```
Then replace `0.0.0` in both files and commit.
