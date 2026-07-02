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
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_chart_version
  namespace  = kubernetes_namespace.argocd.metadata[0].name

  # Ride the root app-of-apps in with the install so ArgoCD self-bootstraps from git.
  values = [yamlencode({
    extraObjects = [yamldecode(file("${path.module}/../../gitops/root-app.yaml"))]
  })]
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
