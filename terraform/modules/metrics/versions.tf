# modules/metrics/versions.tf
# NOTE: legacy module, not referenced by any terragrunt unit
# (metrics-server is deployed via modules/helm-release).

terraform {
  required_version = ">= 1.10"

  required_providers {
    helm = {
      source = "hashicorp/helm"
      # `kubernetes = { ... }` and list-style `set = [...]` are 3.x-only.
      version = ">= 3.0"
    }
  }
}
