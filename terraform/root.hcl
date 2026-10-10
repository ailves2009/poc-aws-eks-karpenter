# ---------------------------------------------------------------------------------------------------------------------
# TERRAGRUNT CONFIGURATION
# Terragrunt is a thin wrapper for Terraform/OpenTofu that provides extra tools for working with multiple modules,
# remote state, and locking: https://github.com/gruntwork-io/terragrunt
# ---------------------------------------------------------------------------------------------------------------------

locals {
  # Automatically load account-level variables
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))

  # Automatically load region-level variables
  region_vars = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  # Extract the variables we need for easy access
  account_name   = local.account_vars.locals.account_name
  account_id     = local.account_vars.locals.aws_account_id
  aws_region     = local.region_vars.locals.aws_region
  cicd_role_name = local.account_vars.locals.cicd_role_name
  tags           = local.account_vars.locals.tags
}

# use_lockfile (S3 native state locking) below requires Terraform >= 1.10.
terraform_version_constraint = ">= 1.10"

# Generate an AWS provider block
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "aws" {
  region = "${local.aws_region}"

  # Only these AWS Account IDs may be operated on by this template
  allowed_account_ids = ["${local.account_id}"]

  # Baseline tags on every taggable AWS resource, including ones created
  # inside upstream modules that don't forward var.tags everywhere.
  default_tags {
    tags = ${jsonencode(local.tags)}
  }
}
EOF
}

# Configure Terragrunt to automatically store tfstate files in an S3 bucket
remote_state {
  backend = "s3"
  config = {
    encrypt      = true
    bucket       = local.account_vars.locals.s3_terraform_state
    key          = "${path_relative_to_include()}/tf.tfstate"
    region       = local.aws_region
    use_lockfile = true
  }
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
}

iam_role = "arn:aws:iam::${local.account_id}:role/${local.cicd_role_name}"
