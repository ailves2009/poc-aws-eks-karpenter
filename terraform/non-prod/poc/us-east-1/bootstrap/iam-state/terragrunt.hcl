# /non-prod/poc/us-east-1/bootstrap/iam-state/terragrunt.hcl

include "bootstrap" {
  path = find_in_parent_folders("bootstrap.hcl")
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))
  region       = local.region_vars.locals.aws_region
}

terraform {
  source = "../../../../../modules/iam-state"
}

inputs = {
  cicd_role_name            = local.account_vars.locals.cicd_role_name
  cicd_account_arn          = "arn:aws:iam::${local.account_vars.locals.aws_account_id}:user/terraform"
  s3_terraform_state        = local.account_vars.locals.s3_terraform_state
  account                   = local.account_vars.locals.aws_account_id
  region                    = local.region
  managed_role_names        = local.account_vars.locals.managed_role_names
  permissions_boundary_name = "cicd-boundary"
  secrets_path_prefix       = local.account_vars.locals.account_name
  tags                      = local.account_vars.locals.tags
}
