# /non-prod/poc/us-east-1/bootstrap/s3-state/terragrunt.hcl

include "bootstrap" {
  path = find_in_parent_folders("bootstrap.hcl")
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
}

terraform {
  source = "../../../../../modules/s3-state"
}

dependency "bootstrap_iam_state" {
  config_path = "../iam-state"

  mock_outputs = {
    deploy_role_arn = "arn:aws:iam::000000000000:role/mock-cicd-role"
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

inputs = {
  bucket_name     = local.account_vars.locals.s3_terraform_state
  versioning      = false                                                  # POC: accepted risk, see review notes
  deploy_role_arn = dependency.bootstrap_iam_state.outputs.deploy_role_arn # needed for assign policy for s3 bucket
}
