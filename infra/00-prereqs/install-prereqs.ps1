# ARIA prereqs — install the CLIs needed to run the codified 0->1 (Windows / winget).
# ArgoCD renders Helm charts SERVER-SIDE, so `helm` is OPTIONAL (local debugging only).
$ErrorActionPreference = "Stop"

$tools = @(
  @{ id = "Hashicorp.Terraform"; name = "terraform" },
  @{ id = "Amazon.AWSCLI";       name = "aws" },
  @{ id = "Kubernetes.kubectl";  name = "kubectl" }
)

foreach ($t in $tools) {
  if (Get-Command $t.name -ErrorAction SilentlyContinue) {
    Write-Host "$($t.name): already installed"
  } else {
    Write-Host "installing $($t.name)..."
    winget install --id $t.id -e --silent --accept-package-agreements --accept-source-agreements
  }
}

# Optional — only for local Helm chart inspection; NOT required for the GitOps flow:
#   winget install --id Helm.Helm -e

Write-Host ""
Write-Host "Done. Reopen your shell so PATH updates take effect."
Write-Host "Also (one-time, AWS console): enable Bedrock model access for Claude Sonnet 4.6 + Haiku 4.5 in ap-southeast-1."
