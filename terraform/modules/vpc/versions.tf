# /modules/vpc/versions.tf

terraform {
  # use_lockfile (S3 native locking) in root.hcl needs >= 1.10.
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}
