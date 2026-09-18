#!/usr/bin/env python3
"""Send the labeled prompts to LiteLLM from inside the mesh and record what the router did.

Calls go from a probe pod running as the `cost-sentinel` ServiceAccount — the only identity
platform/istio/policies/litellm-allow-list.yaml lets through — so they take the real network path,
not a port-forward that would skip ztunnel.

Usage (needs kubectl pointed at the aria cluster):
    python run.py --model smart-router    > results/smart-router.jsonl
    python run.py --model bedrock-opus-5  > results/reference-opus-5.jsonl

With --model smart-router, the response's `model` field is the real model that answered
(return_raw_model_name: true in configmap.yaml). Each tier maps to a distinct model, so that
names the tier.
"""
import argparse
import json
import os
import subprocess
import sys
import time
from pathlib import Path

NS = "kagent"
PROBE = "router-eval-probe"
URL = "http://litellm.litellm.svc.cluster.local:4000/v1/chat/completions"
CTX = os.environ.get("KCTX")  # kubectl context for the aria cluster; current context if unset

# Substring of the served model name → tier (platform/litellm/configmap.yaml `smart-router`).
TIER_BY_MODEL = [
    ("claude-3-haiku", "SIMPLE"),   # checked before haiku-4-5: both contain "haiku"
    ("haiku-4-5", "MEDIUM"),
    ("sonnet-5", "COMPLEX"),
    ("opus-5", "REASONING"),
]


def kubectl(*args, stdin=None):
    context = ["--context", CTX] if CTX else []
    return subprocess.run(
        ["kubectl", *context, "-n", NS, *args],
        input=stdin, capture_output=True, text=True, encoding="utf-8",
    )


def ensure_probe():
    if kubectl("get", "pod", PROBE).returncode == 0:
        return
    overrides = json.dumps({"spec": {"serviceAccountName": "cost-sentinel"}})
    kubectl("run", PROBE, "--restart=Never", "--image=curlimages/curl:8.10.1",
            f"--overrides={overrides}", "--command", "--", "sleep", "7200")
    kubectl("wait", "--for=condition=Ready", f"pod/{PROBE}", "--timeout=120s")


def master_key():
    out = kubectl("get", "secret", "litellm-gateway-key", "-o",
                  "jsonpath={.data.LITELLM_MASTER_KEY}").stdout
    import base64
    return base64.b64decode(out).decode()


def tier_of(model):
    for needle, tier in TIER_BY_MODEL:
        if needle in (model or ""):
            return tier
    return None


def call(key, model, prompt):
    body = json.dumps({
        "model": model,
        "messages": [{"role": "user", "content": prompt}],
        "user": "router-eval",
    })
    started = time.monotonic()
    res = kubectl(
        "exec", "-i", PROBE, "--", "curl", "-sS", "-m", "180", "-D", "/dev/stderr",
        "-H", f"Authorization: Bearer {key}", "-H", "Content-Type: application/json",
        "--data-binary", "@-", URL,
        stdin=body,
    )
    elapsed = round(time.monotonic() - started, 2)
    headers = {}
    for line in res.stderr.splitlines():
        if ":" in line:
            name, _, value = line.partition(":")
            headers[name.strip().lower()] = value.strip()
    try:
        payload = json.loads(res.stdout)
    except json.JSONDecodeError:
        payload = {"error": res.stdout[:500] or res.stderr[:500]}
    return payload, headers, elapsed


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", default="smart-router")
    parser.add_argument("--prompts", default=str(Path(__file__).with_name("prompts.jsonl")))
    args = parser.parse_args()

    ensure_probe()
    key = master_key()
    for line in Path(args.prompts).read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        item = json.loads(line)
        payload, headers, elapsed = call(key, args.model, item["prompt"])
        served = payload.get("model")
        usage = payload.get("usage") or {}
        tier = tier_of(served)
        record = {
            **item,
            "requested_model": args.model,
            "served_model": served,
            "tier": tier,
            "tier_ok": tier in item["acceptable"] if tier else None,
            "prompt_tokens": usage.get("prompt_tokens"),
            "completion_tokens": usage.get("completion_tokens"),
            "response_cost_header": headers.get("x-litellm-response-cost"),
            "model_id_header": headers.get("x-litellm-model-id"),
            "latency_s": elapsed,
            "answer": ((payload.get("choices") or [{}])[0].get("message") or {}).get("content"),
            "error": payload.get("error"),
        }
        print(json.dumps(record, ensure_ascii=False), flush=True)
        print(f"{item['id']:>3} {item['category']:<22} -> {tier or '?':<9} {served}", file=sys.stderr)


if __name__ == "__main__":
    main()
