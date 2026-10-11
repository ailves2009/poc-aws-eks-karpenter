# /non-prod/poc/us-east-1/workload/eks/terragrunt.hcl

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))
  tags         = local.account_vars.locals.tags
  cluster_name = local.region_vars.locals.cluster_name
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../../../modules/eks"
}

dependency "vpc" {
  config_path = "../vpc"

  mock_outputs = {
    vpc_id             = "vpc-00000000000000000"
    private_subnet_ids = ["subnet-00000000000000001", "subnet-00000000000000002"]
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "iam_state" {
  config_path = "../../bootstrap/iam-state"

  mock_outputs = {
    permissions_boundary_arn = "arn:aws:iam::000000000000:policy/mock-boundary"
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

inputs = {
  cluster_name = local.cluster_name
  # Standard support until 2027-12-01. EKS upgrades one minor at a time —
  # from an older cluster go through intermediate versions with
  #   terragrunt apply -var cluster_version=1.NN -var 'addon_versions={}'
  # (Karpenter must already be on a version supporting the target, see
  # https://karpenter.sh/docs/upgrading/compatibility/; 1.15.x supports 1.37).
  cluster_version = "1.37"

  # Latest builds for 1.37 as of 2026-10-11. Must be >= the running version
  # (EKS cannot downgrade addons).
  addon_versions = {
    coredns                = "v1.14.7-eksbuild.11"
    kube-proxy             = "v1.37.0-eksbuild.19"
    vpc-cni                = "v1.23.2-eksbuild.1"
    eks-pod-identity-agent = "v1.4.0-eksbuild.3"
  }

  vpc_id             = dependency.vpc.outputs.vpc_id
  private_subnet_ids = dependency.vpc.outputs.private_subnet_ids

  permissions_boundary_arn = dependency.iam_state.outputs.permissions_boundary_arn

  # 2 nodes across 2 AZs so the Karpenter chart's default 2 replicas can
  # satisfy its zone topology-spread constraint.
  bootstrap_node_min_size     = 2
  bootstrap_node_desired_size = 2
  bootstrap_node_max_size     = 3

  tags = local.tags
}
