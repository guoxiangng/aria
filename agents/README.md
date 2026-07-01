# agents/ — the catalog

One folder per agent. Each "fills the template" with a `values.yaml` + a `content-pack/`:

```
agents/<name>/
├── values.yaml            # fills platform/agent-template
└── content-pack/
    ├── golden.jsonl       # eval scenarios + expected behavior
    ├── rubric.yaml        # scoring criteria
    ├── redteam.jsonl      # prompt-injection / secret-exfil tests
    └── skills/            # optional procedural playbooks
```

First agents (see proposal): `cluster-diagnostics` (read-only), then `cluster-remediation`
(approval-gated), then `runbook-rag`.
