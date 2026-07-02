output "argocd_namespace" {
  value = kubernetes_namespace.argocd.metadata[0].name
}

output "argocd_admin_password_cmd" {
  description = "Retrieve the initial ArgoCD admin password."
  value       = "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
}

output "argocd_port_forward_cmd" {
  description = "Open the ArgoCD UI locally (no ingress needed)."
  value       = "kubectl -n argocd port-forward svc/argocd-server 8080:443"
}
