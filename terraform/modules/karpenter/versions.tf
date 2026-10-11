# /modules/karpenter/versions.tf

terraform {
  # use_lockfile (S3 native locking) in root.hcl needs >= 1.10.
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # terraform-aws-modules/eks/aws v20 is capped below 6.0.
      version = ">= 5.95, < 6.0"
    }
    helm = {
      source = "hashicorp/helm"
      # `kubernetes = { ... }` attribute syntax in the provider block is 3.x-only.
      version = ">= 3.0"
    }
    # alekc/kubectl (maintained fork of gavinbunney/kubectl) applies CRs whose
    # CRDs were just installed — cleaner than hashicorp/kubernetes_manifest,
    # which insists on the API server already knowing the kind at plan time.
    kubectl = {
      source  = "alekc/kubectl"
      version = "~> 2.4"
    }
  }
}
