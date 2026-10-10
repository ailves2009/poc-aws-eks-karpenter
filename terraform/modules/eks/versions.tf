# /modules/eks/versions.tf

terraform {
  # use_lockfile (S3 native locking) in root.hcl needs >= 1.10.
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # terraform-aws-modules/eks/aws v20 is capped below 6.0.
      version = ">= 5.95, < 6.0"
    }
  }
}
