#!/bin/sh
# Runs all promptfoo eval configs against the real in-cluster agent Services
# (no port-forward needed - runs directly on an ARC self-hosted runner pod inside
# the cluster, see platform/arc/). Exits non-zero if any suite fails, so this can
# gate a CI check on its exit code.
#
# Local dev configs point at localhost:1808X (via kubectl port-forward, see each
# config's header comment) - swap those for real in-cluster Service DNS here.
set -eu

for f in *.promptfooconfig.yaml; do
  sed -i \
    -e 's#http://localhost:18080/#http://cluster-diagnostics.kagent:8080/#' \
    -e 's#http://localhost:18081/#http://incident-commander.kagent:8080/#' \
    -e 's#http://localhost:18082/#http://investigation-loop.kagent:8080/#' \
    "$f"
done

overall_status=0

for f in *.promptfooconfig.yaml; do
  echo "=== Running $f ==="
  if ! ./node_modules/.bin/promptfoo eval -c "$f" --no-cache; then
    echo "=== FAILED: $f ==="
    overall_status=1
  fi
done

exit $overall_status
