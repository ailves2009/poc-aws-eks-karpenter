# /modules/helm-release/versions.tf

terraform {
  # use_lockfile (S3 native locking) in root.hcl needs >= 1.10.
  required_version = ">= 1.10"

  required_providers {
    helm = {
      source = "hashicorp/helm"
      # `kubernetes = { ... }` attribute syntax in the provider block is 3.x-only.
      version = ">= 3.0"
    }
  }
}
