# /non-prod/poc/us-east-1/workload/aws-lb-controller/terragrunt.hcl

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))
  region       = local.region_vars.locals.aws_region
  tags         = local.account_vars.locals.tags
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../../../modules/aws-lb-controller"
}

dependency "vpc" {
  config_path = "../vpc"

  mock_outputs = {
    vpc_id = "vpc-00000000000000000"
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "eks" {
  config_path = "../eks"

  mock_outputs = {
    cluster_name                       = "mock-cluster"
    cluster_endpoint                   = "https://mock.eks.amazonaws.com"
    cluster_certificate_authority_data = "bW9jaw=="
    oidc_provider_arn                  = "arn:aws:iam::000000000000:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/MOCK"
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
  cluster_name                       = dependency.eks.outputs.cluster_name
  cluster_endpoint                   = dependency.eks.outputs.cluster_endpoint
  cluster_certificate_authority_data = dependency.eks.outputs.cluster_certificate_authority_data
  oidc_provider_arn                  = dependency.eks.outputs.oidc_provider_arn

  vpc_id = dependency.vpc.outputs.vpc_id
  region = local.region

  permissions_boundary_arn = dependency.iam_state.outputs.permissions_boundary_arn

  tags = local.tags
}
