# /non-prod/poc/us-east-1/workload/metrics-server/terragrunt.hcl
#
# Cluster-wide metrics endpoint. Required by HPA, `kubectl top`, and any
# autoscaler that consumes resource metrics. Pinned to the bootstrap node
# group so it survives Karpenter consolidation.

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))
  region       = local.region_vars.locals.aws_region
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../../../modules/helm-release"
}

dependency "eks" {
  config_path = "../eks"

  mock_outputs = {
    cluster_name                       = "mock-cluster"
    cluster_endpoint                   = "https://mock.eks.amazonaws.com"
    cluster_certificate_authority_data = "bW9jaw=="
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

inputs = {
  cluster_name                       = dependency.eks.outputs.cluster_name
  cluster_endpoint                   = dependency.eks.outputs.cluster_endpoint
  cluster_certificate_authority_data = dependency.eks.outputs.cluster_certificate_authority_data
  region                             = local.region

  name             = "metrics-server"
  namespace        = "kube-system"
  create_namespace = false

  chart         = "metrics-server"
  repository    = "https://kubernetes-sigs.github.io/metrics-server/"
  chart_version = "3.12.2"

  values = {
    # EKS kubelet uses a cert signed by the cluster CA (not a public CA);
    # metrics-server doesn't ship the cluster CA, so TLS verification fails.
    # --kubelet-insecure-tls skips it (safe inside a VPC; replace with proper
    # CA wiring for hardened setups).
    args = [
      "--kubelet-insecure-tls",
      "--kubelet-preferred-address-types=InternalIP,Hostname",
      "--kubelet-use-node-status-port",
      "--metric-resolution=15s",
    ]

    # Run on the always-on bootstrap NG, not on ephemeral Karpenter nodes —
    # we don't want metrics-server pod migrations on consolidation.
    nodeSelector = {
      "node-role" = "bootstrap"
    }
  }
}
