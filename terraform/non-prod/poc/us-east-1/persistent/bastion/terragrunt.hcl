# /non-prod/poc/us-east-1/persistent/bastion/terragrunt.hcl

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
  source = "../../../../../modules/bastion"
}

dependency "bootstrap_iam_state" {
  config_path = "../../bootstrap/iam-state"

  mock_outputs = {
    deploy_role_arn          = "arn:aws:iam::000000000000:role/mock-cicd-arn"
    permissions_boundary_arn = "arn:aws:iam::000000000000:policy/mock-boundary"
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

inputs = {
  tags                     = local.tags
  permissions_boundary_arn = dependency.bootstrap_iam_state.outputs.permissions_boundary_arn

  # No Route53 record — DNS lives outside this account.
  # After apply, take the bastion's `public_ip` output and CNAME it
  # manually in your authoritative zone (e.g. example.com).
  create_dns_record = false

  # Lock down to your office/home IP. Find with `curl ifconfig.me`.
  # The placeholder below is intentionally invalid — apply will fail until
  # you replace it with a real CIDR.
  allowed_cidrs = ["YOUR.PUBLIC.IP.HERE/32"]
}
