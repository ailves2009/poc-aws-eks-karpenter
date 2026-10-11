# /modules/s3-state/versions.tf

terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # outputs.tf uses data.aws_region.current.region (attribute added in v6).
      version = ">= 6.0"
    }
  }
}
