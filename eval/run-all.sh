#!/bin/sh
# Runs all promptfoo eval configs against the real in-cluster agent Services
# (no port-forward needed - runs directly on an ARC self-hosted runner pod inside
# the cluster, see platform/arc/). Exits non-zero if any suite fails, so this can
# gate a CI check on its exit code.
#
# Local dev configs point at localhost:1808X for the agents and localhost:4000 for
# the judge (both via kubectl port-forward, see each config's header comment) -
# swapped for real in-cluster Service DNS here.
#
# Requires LITELLM_API_KEY in the environment: the judge routes through the
# gateway now, not Azure. Without it every assertion errors and - see below -
# that is deliberately no longer mistaken for a test failure.
set -eu

# A JSON reader is mandatory, not optional. The checks below are the only thing
# standing between "the suite passed" and "the suite never ran", so a runner
# without python3 or jq must fail loudly rather than skip them.
if command -v python3 >/dev/null 2>&1; then
  JSON=python3
elif command -v jq >/dev/null 2>&1; then
  JSON=jq
else
  echo "FATAL: neither python3 nor jq found - cannot verify results. Refusing to report a pass." >&2
  exit 2
fi

for f in *.promptfooconfig.yaml; do
  sed -i \
    -e 's#http://localhost:18080/#http://cluster-diagnostics.kagent:8080/#' \
    -e 's#http://localhost:18081/#http://incident-commander.kagent:8080/#' \
    -e 's#http://localhost:18082/#http://investigation-loop.kagent:8080/#' \
    -e 's#http://localhost:4000/v1#http://litellm.litellm.svc.cluster.local:4000/v1#' \
    "$f"
done

overall_status=0

# Why this is more than `if ! promptfoo eval`: in one session this suite reported
# a result three separate times without testing anything, each time exiting 0.
#   1. A corrupt npx cache meant promptfoo never started.
#   2. --filter-pattern matched no tests (they had no `description`), giving
#      "0 passed, 0 failed" - which reads as a clean run.
#   3. The judge was unreachable, so every assertion ERRORED, and the summary
#      line said "3/3 failed" - indistinguishable from agents hallucinating.
# (1) and (2) are false greens, (3) is a false red. All three are worse than a
# real failure because they look like signal. So: require a non-zero test count,
# and treat assertion errors as a separate, louder outcome than assertion
# failures.
check_run() {
  out="$1"
  cfg="$2"
  if [ ! -f "$out" ]; then
    echo "=== NO RESULTS FILE: $cfg - promptfoo did not produce output ==="
    return 1
  fi
  if [ "$JSON" = "python3" ]; then
    python3 - "$out" "$cfg" <<'PY'
import json, sys
out, cfg = sys.argv[1], sys.argv[2]
d = json.load(open(out, encoding="utf-8"))
res = d.get("results", {})
rows = res.get("results") or []
if not rows:
    print("=== ZERO TESTS RAN: %s - a pass here means nothing ===" % cfg)
    sys.exit(1)
errors = 0
for r in rows:
    for c in (r.get("gradingResult") or {}).get("componentResults") or []:
        reason = c.get("reason") or ""
        if reason.startswith("API call error") or reason.startswith("API error"):
            errors += 1
failed = sum(1 for r in rows if not r.get("success"))
print("    %d tests, %d failed, %d assertion errors" % (len(rows), failed, errors))
if errors:
    print("=== ASSERTION ERRORS in %s - the judge or provider was unreachable. "
          "These are NOT agent failures; the run proved nothing. ===" % cfg)
    sys.exit(2)
sys.exit(1 if failed else 0)
PY
  else
    n=$(jq '[.results.results[]] | length' "$out")
    if [ "$n" -eq 0 ]; then
      echo "=== ZERO TESTS RAN: $cfg - a pass here means nothing ==="
      return 1
    fi
    e=$(jq '[.results.results[].gradingResult.componentResults[]?
             | select(.reason | tostring | startswith("API call error") or startswith("API error"))]
            | length' "$out")
    fl=$(jq '[.results.results[] | select(.success != true)] | length' "$out")
    echo "    $n tests, $fl failed, $e assertion errors"
    if [ "$e" -gt 0 ]; then
      echo "=== ASSERTION ERRORS in $cfg - judge or provider unreachable. NOT agent failures. ==="
      return 2
    fi
    [ "$fl" -eq 0 ] || return 1
  fi
}

for f in *.promptfooconfig.yaml; do
  echo "=== Running $f ==="
  out="results-$(basename "$f" .promptfooconfig.yaml).json"
  # `|| true`: a non-zero exit from promptfoo means tests failed, which is a
  # real result. It is check_run below that decides whether a result exists.
  promptfoo eval -c "$f" --no-cache -o "$out" || true
  if ! check_run "$out" "$f"; then
    rc=$?
    if [ "$rc" -eq 2 ]; then
      echo "=== BROKEN: $f (infrastructure, not behaviour) ==="
    else
      echo "=== FAILED: $f ==="
    fi
    overall_status=1
  fi
done

exit $overall_status
