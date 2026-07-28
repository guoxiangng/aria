###############################################################################
# ArgoCD — installed via the upstream Helm chart (not vendored).
# Bootstraps the app-of-apps as an extraObject, so after this apply ArgoCD
# owns everything else (namespaces, kagent, models, agents) from git.
###############################################################################

resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
  }
}

resource "helm_release" "argocd" {
  name = "argocd"
  # OCI chart — pulls directly, avoids the local HTTP repo-index cache (which had a stale kyverno entry).
  chart     = "oci://ghcr.io/argoproj/argo-helm/argo-cd"
  version   = var.argocd_chart_version
  namespace = kubernetes_namespace.argocd.metadata[0].name
  # wait=true (default) — release (incl. the Application CRD) is Ready before the root app applies.
}

# App-of-apps root — applied AFTER ArgoCD + its Application CRD exist (can't ride in the same release).
resource "kubectl_manifest" "root_app" {
  yaml_body  = file("${path.module}/../../gitops/root-app.yaml")
  depends_on = [helm_release.argocd]
}

###############################################################################
# kagent platform namespace + Azure OpenAI secret.
# (Platform-core namespace carrying a secret -> Terraform-owned. Tenant/agent
#  namespaces are pure CaC via ArgoCD + charts/namespace-bootstrap.)
###############################################################################

resource "kubernetes_namespace" "kagent" {
  metadata {
    name = "kagent"
    labels = {
      "managed-by" = "terraform"
    }
  }
}

###############################################################################
# The kagent-azure-openai and kagent-langfuse-otel Secrets are NO LONGER created
# here. They moved to External Secrets Operator (see eso.tf + platform/external-secrets/):
# the values live in AWS Secrets Manager, and git-committed ExternalSecret pointer CRs
# (owned by ArgoCD) materialize the in-cluster Secrets. This removes secret material
# from Terraform state and makes secret provisioning pure GitOps.
#
# The azure_openai_api_key / langfuse_* variables are still used — eso.tf reads them to
# seed the initial Secrets Manager values (after which Secrets Manager is the source of
# truth and rotation happens there, not in tfvars).
###############################################################################
