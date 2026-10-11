# /non-prod/poc/us-east-1/bootstrap/bootstrap.hcl
#
# Shared config for bootstrap units (iam-state, s3-state). They cannot use
# root.hcl: they create the S3 state bucket and the CI/CD role that root.hcl
# depends on, so they run as the bootstrap `terraform` IAM user with local
# state.

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))
}

terraform_version_constraint = ">= 1.10"

# Local state lives next to the unit's terragrunt.hcl (gitignored via
# *.tfstate), NOT inside .terragrunt-cache — clearing the cache must not
# lose the state of the CI/CD role and the state bucket. Back these files up.
generate "backend" {
  path      = "backend.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform {
  backend "local" {
    path = "${get_terragrunt_dir()}/terraform.tfstate"
  }
}
EOF
}

generate "providers" {
  path      = "providers.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "aws" {
  region = "${local.region_vars.locals.aws_region}"

  # Fail fast if the active AWS profile points to another account.
  allowed_account_ids = ["${local.account_vars.locals.aws_account_id}"]

  default_tags {
    tags = ${jsonencode(local.account_vars.locals.tags)}
  }
}
EOF
}
