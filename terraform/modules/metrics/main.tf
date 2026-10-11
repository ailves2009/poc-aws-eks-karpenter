# modules/metrics/main.tf

provider "helm" {
  kubernetes = {
    host = var.kube_host
    # var.kube_ca is base64 (as EKS returns it); the provider expects PEM.
    cluster_ca_certificate = base64decode(var.kube_ca)
    token                  = var.kube_token
  }
}

resource "helm_release" "metrics" {
  name       = "metrics"
  repository = var.metrics_server_helm_repo
  chart      = "metrics-server"
  version    = var.metrics_server_helm_version
  namespace  = var.metrics_server_namespace
  wait       = true

  # List-style `set` (helm provider 3.x), built from var.metrics_server_settings.
  set = [
    for name, value in var.metrics_server_settings : {
      name  = name
      value = value
    }
  ]
}
