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

  # Lock down to your office/home IP, passed via env so it is never committed:
  #   export BASTION_ALLOWED_CIDRS="$(curl -s https://checkip.amazonaws.com)/32"
  # (comma-separated for several). Without it the placeholder is used and
  # apply fails on the invalid CIDR — intentionally.
  allowed_cidrs = split(",", get_env("BASTION_ALLOWED_CIDRS", "YOUR.PUBLIC.IP.HERE/32"))

  # Optional EC2 key pair: put an OpenSSH public key into bastion.pub next to
  # this file (see runbooks/bastion-access.md). Adding, changing or removing
  # it replaces the instance.
  ssh_public_key = fileexists("${get_terragrunt_dir()}/bastion.pub") ? trimspace(file("${get_terragrunt_dir()}/bastion.pub")) : ""
}
