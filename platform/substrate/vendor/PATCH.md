# Vendored: Agent Substrate chart (upstream v0.0.10) + one ARIA patch

**Why vendored (not pulled from OCI like kagent/istio):** the upstream `substrate` chart
**hardcodes a 6-node valkey (Redis Cluster)** — 3 masters + 3 replicas — in the cluster
**init job**, in a way that is *not* exposed through any value. Two separate hardcodes:

1. `valkey.replicas` exists as a value, but the init job iterates a **fixed** pod list
   `for i in 0 1 2 3 4 5` (both the DNS-wait loop and the IP-collection loop). At
   `replicas: 3` the init hangs forever waiting on `valkey-cluster-3/-4/-5` DNS that never
   exists.
2. `redis-cli --cluster create ... --cluster-replicas 1` is hardcoded, so every master
   gets one replica and `create` refuses < 3 masters → the floor is locked at 6.

On ARIA's 2× t3.large lab the binding constraint is **VPC-CNI pod-slots (35/node)**, not CPU
(the valkey containers set no resource requests — best-effort QoS). Six valkey pods + the
rest of the Substrate control plane (~16 pods total) overruns the free pod-slots on an
already-busy node, which would otherwise force a 3rd node purely to hold Redis replicas we
don't need in a lab.

## The patch (the only change vs upstream v0.0.10)

`templates/valkey.yaml` — parameterize what upstream baked in:

```diff
- for i in 0 1 2 3 4 5; do                     # (x2: DNS-wait loop + IP-collection loop)
+ for i in {{ range $i := until (int .Values.valkey.replicas) }}{{ $i }} {{ end }}; do

- --cluster-replicas 1 \                        # (x2: mtls path + jwt path)
+ --cluster-replicas {{ .Values.valkey.clusterReplicas }} \
```

`values.yaml` — add the new key with an upstream-preserving default:

```diff
  valkey:
    replicas: 6
+   clusterReplicas: 1   # default preserves upstream 3m+3r; ARIA overrides to 0
```

ARIA's overlay (`platform/substrate/values.yaml`) then sets `valkey.replicas: 3` +
`clusterReplicas: 0` → **3 masters, 0 replicas** (minimum viable Redis Cluster; no HA — fine
for a lab). All 4 edits are marked inline with `ARIA-PATCH`.

Nothing else in the chart assumes 6 nodes — `ate-api` reaches Redis via the single
`ATE_API_REDIS_ADDRESS` headless-service env and discovers topology like any cluster client.

## Patch 2 — CA bundle from a Secret, not a ConfigMap (2 files)

ARIA disables the chart's JWT self-bootstrap (`auth.jwt.bootstrap.enabled: false`) because it
uses Helm `lookup` to reuse cert material, which returns empty under ArgoCD's `helm template`
(certs would regenerate every sync). Instead all four bootstrap objects are supplied via ESO
from Secrets Manager (`infra/03-argocd/substrate-certs.tf` + `../manifests/`). Three are Secrets
already; the CA bundle upstream is a **ConfigMap**, but ESO emits Secrets — so the two consumers
that mount it are patched to read a Secret:

```diff
  # templates/ate-controller.yaml  AND  templates/atenet-router.yaml
  - name: ateapi-ca
-   configMap:
-     name: {{ .Values.auth.jwt.caBundleConfigMap }}
+   secret:                                          # ARIA-PATCH
+     secretName: {{ .Values.auth.jwt.caBundleConfigMap }}
```

`ca.crt` is a public cert (no secret material); it rides in the same SM secret as the server
cert so the CA/leaf pair can't drift. All edits are marked inline with `ARIA-PATCH`.

## Upstream sync

Pinned to substrate **v0.0.10** (`appVersion` in `vendor/substrate/Chart.yaml`). On a version
bump: re-pull `oci://ghcr.io/kagent-dev/substrate/helm/substrate`, diff, and re-apply the 4
edits above (search `ARIA-PATCH`). The parameterization is upstreamable — worth a PR so this
fork can eventually be dropped.
