# /modules/argocd/outputs.tf

output "namespace" {
  description = "Namespace Argo CD runs in"
  value       = helm_release.argocd.namespace
}

output "chart_version" {
  description = "Installed argo-cd chart version"
  value       = helm_release.argocd.version
}

output "ui_port_forward" {
  description = "How to reach the UI (no Ingress in the POC)"
  value       = "kubectl -n ${helm_release.argocd.namespace} port-forward svc/argocd-server 8080:80  →  http://localhost:8080 (admin / kubectl -n ${helm_release.argocd.namespace} get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)"
}
