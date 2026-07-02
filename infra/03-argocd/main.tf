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

resource "kubernetes_secret" "kagent_azure" {
  metadata {
    name      = "kagent-azure-openai"
    namespace = kubernetes_namespace.kagent.metadata[0].name
  }
  data = {
    AZUREOPENAI_API_KEY = var.azure_openai_api_key
  }
}
