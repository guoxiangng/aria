# infra/00-prereqs — local tooling (step 0)

Codifies the CLIs needed to run the 0→1. Run once:

```powershell
powershell -ExecutionPolicy Bypass -File infra/00-prereqs/install-prereqs.ps1
```

Installs **terraform**, **aws**, **kubectl** (Windows/winget). Reopen the shell afterward so PATH updates.

> **helm is NOT a prerequisite** — ArgoCD renders Helm charts server-side (its repo-server has Helm built in).
> Install helm only for local chart inspection (commented in the script).

One-time manual step (AWS console, can't be codified in this repo): enable **Bedrock model access** for
Claude **Sonnet 4.6** + **Haiku 4.5** in **ap-southeast-1**.
