# /non-prod/poc/us-east-1/workload/argocd/terragrunt.hcl
#
# Argo CD + the root Application. Everything else Argo CD deploys comes from the
# poc-eks-gitops-* repositories (see terraform/README.md → GitOps with Argo CD).

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))
  region       = local.region_vars.locals.aws_region
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../../../modules/argocd"
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

# Ordering only: workloads asking for spot capacity need Karpenter, Ingresses need the
# LB controller. Argo CD would retry anyway; this keeps a fresh `run --all apply` tidy.
dependencies {
  paths = ["../karpenter", "../aws-lb-controller"]
}

inputs = {
  cluster_name                       = dependency.eks.outputs.cluster_name
  cluster_endpoint                   = dependency.eks.outputs.cluster_endpoint
  cluster_certificate_authority_data = dependency.eks.outputs.cluster_certificate_authority_data
  region                             = local.region

  gitops_root_repo_url = "https://github.com/ailves2009/poc-eks-gitops-root.git"
  gitops_root_revision = "master"
}
