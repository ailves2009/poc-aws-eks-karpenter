# /modules/argocd/main.tf
#
# Bootstrap only: Terraform installs Argo CD and one root Application (app-of-apps).
# Everything after that is GitOps, from three repositories:
#   poc-eks-gitops-root      "what & where"  — ApplicationSets, the projects Application
#   poc-eks-gitops-projects  "who may do what" — AppProjects
#   poc-eks-gitops-values    "with which params" — values per cluster / environment
# Charts deployed by Argo CD live in this repository under charts/.

provider "helm" {
  kubernetes = {
    host                   = var.cluster_endpoint
    cluster_ca_certificate = base64decode(var.cluster_certificate_authority_data)
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", var.cluster_name, "--region", var.region]
    }
  }
}

provider "kubectl" {
  host                   = var.cluster_endpoint
  cluster_ca_certificate = base64decode(var.cluster_certificate_authority_data)
  load_config_file       = false

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", var.cluster_name, "--region", var.region]
  }
}

resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = var.namespace
  create_namespace = true

  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.chart_version

  wait    = true
  timeout = 600

  values = [yamlencode({
    # System component: the always-on bootstrap node group, never ephemeral Karpenter nodes.
    global = {
      nodeSelector = { "node-role" = "bootstrap" }
    }

    configs = {
      params = {
        # No Ingress in the POC: the UI is reached with `kubectl port-forward`, which already
        # tunnels through the API server, so argocd-server serves plain HTTP.
        "server.insecure" = true
      }
      cm = {
        # Local admin only (port-forward). An SSO/OIDC connector would replace it outside a POC.
        "admin.enabled"          = true
        "exec.enabled"           = false
        "timeout.reconciliation" = "120s"
      }
      rbac = {
        # Anyone authenticated may look, nobody may change by default; project roles grant more.
        "policy.default" = "role:readonly"
      }
    }

    # No SSO connector and no notification targets in the POC (phase 2: Notifications).
    dex           = { enabled = false }
    notifications = { enabled = false }
  })]
}

# Root Application (app-of-apps). It is the only object Terraform puts into Argo CD; it syncs
# clusters/<cluster>/ of the root repository, which holds the projects Application and the
# ApplicationSets.
#
# prune + selfHeal: a manifest removed from git is removed from the cluster, a manual edit is
# reverted. Workloads are protected separately (preserveResourcesOnDeletion on the
# ApplicationSets). No resources-finalizer: deleting the root (e.g. `terragrunt destroy`) never
# cascades into the applications it created.
resource "kubectl_manifest" "root" {
  yaml_body = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "root"
      namespace = var.namespace
    }
    spec = {
      project = "default"
      source = {
        repoURL        = var.gitops_root_repo_url
        targetRevision = var.gitops_root_revision
        path           = "clusters/${var.cluster_name}"
        directory      = { recurse = true }
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = var.namespace
      }
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
      }
    }
  })

  depends_on = [helm_release.argocd]
}
