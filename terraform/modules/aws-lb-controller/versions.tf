# /modules/aws-lb-controller/versions.tf

terraform {
  # use_lockfile (S3 native locking) in root.hcl needs >= 1.10.
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    helm = {
      source = "hashicorp/helm"
      # `kubernetes = { ... }` attribute syntax in the provider block is 3.x-only.
      version = ">= 3.0"
    }
  }
}
