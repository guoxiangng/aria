#!/usr/bin/env sh
# Rogue-agent deny demo — the faithful test of the cluster-diagnostics AuthorizationPolicy.
#
# Fires the SAME A2A request at cluster-diagnostics from two identities that differ ONLY in
# ServiceAccount (hence SPIFFE identity):
#   - authorized-probe (SA incident-commander, ON the allow-list) → expect HTTP 200
#   - rogue-probe       (SA shadow-agent, valid mesh identity, NOT allow-listed) → expect TCP reset
# The request originates from a real in-mesh peer over the pod network, so ztunnel actually
# enforces the policy (unlike `kubectl port-forward`, which lands on loopback and bypasses it).
#
# Usage:  KCTX=arn:aws:eks:ap-southeast-1:622629043701:cluster/aria sh run-demo.sh
# Requires the probes from rogue-agent-demo.yaml to be applied and Ready first:
#   kubectl --context "$KCTX" apply -f rogue-agent-demo.yaml
#   kubectl --context "$KCTX" -n kagent wait --for=condition=Ready pod/rogue-probe pod/authorized-probe --timeout=90s
set -eu

KCTX="${KCTX:-arn:aws:eks:ap-southeast-1:622629043701:cluster/aria}"
NS=kagent
URL="http://cluster-diagnostics.${NS}.svc.cluster.local:8080/"
BODY='{"jsonrpc":"2.0","id":"rogue-demo","method":"message/send","params":{"message":{"kind":"message","messageId":"demo-msg-1","role":"user","parts":[{"kind":"text","text":"list namespaces"}]}}}'
CURL="curl -sS -m 15 -o /dev/null -w 'HTTP_CODE=%{http_code} EXIT=%{exitcode}\n' -X POST -H 'Content-Type: application/json' -d '${BODY}' ${URL}"

kc() { kubectl --context "$KCTX" -n "$NS" "$@"; }

echo "=== PROBE 1: authorized-probe (SA incident-commander → ON allow-list) — expect HTTP 200 ==="
kc exec authorized-probe -- sh -c "$CURL" || true

echo ""
echo "=== PROBE 2: rogue-probe (SA shadow-agent → valid identity, NOT allow-listed) — expect reset ==="
# curl exits 56 (Connection reset by peer) on an L4 ztunnel deny; tolerate it so the script continues.
kc exec rogue-probe -- sh -c "$CURL" || echo "(curl failed as expected — ztunnel L4 deny closes the connection)"

echo ""
echo "=== ztunnel deny evidence (destination node) ==="
NODE=$(kc get pod -l app.kubernetes.io/name=cluster-diagnostics -o jsonpath='{.items[0].spec.nodeName}')
ZT=$(kubectl --context "$KCTX" -n istio-system get pod -l app=ztunnel \
      --field-selector "spec.nodeName=$NODE" -o jsonpath='{.items[0].metadata.name}')
echo "ztunnel: $ZT (node $NODE)"
kubectl --context "$KCTX" -n istio-system logs "$ZT" --tail=200 \
  | grep -iE 'shadow-agent|policy rejection' | tail -5

echo ""
echo "Expected: authorized=200; rogue=curl(56)/HTTP_CODE=000; ztunnel logs the shadow-agent"
echo "source with: 'connection closed due to policy rejection: allow policies exist, but none allowed'."
echo "Cleanup: kubectl --context \"\$KCTX\" delete -f rogue-agent-demo.yaml"
