# /modules/karpenter/variables.tf

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "cluster_endpoint" {
  description = "EKS API server endpoint"
  type        = string
}

variable "cluster_certificate_authority_data" {
  description = "Base64-encoded EKS cluster CA"
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the IAM OIDC provider for the cluster (used for IRSA on the Karpenter controller)"
  type        = string
}

variable "region" {
  description = "AWS region — needed for the kubeconfig exec block"
  type        = string
}

variable "permissions_boundary_arn" {
  description = "Permissions boundary attached to all IAM roles created by this module"
  type        = string
}

variable "karpenter_chart_version" {
  description = "Version of the vendored karpenter and karpenter-crd Helm charts (both .tgz must exist in charts/). 1.15.x supports Kubernetes 1.31–1.37."
  type        = string
  default     = "1.15.0"
}

variable "ami_alias" {
  description = "EC2NodeClass amiSelectorTerms alias, pinned to an EKS AL2023 AMI release (family@vYYYYMMDD). Resolved per cluster Kubernetes version, so it stays valid across control-plane upgrades."
  type        = string
  default     = "al2023@v20261003"
}

variable "instance_categories" {
  description = "Allowed EC2 instance categories for the default NodePool (c=compute, m=general, r=memory)"
  type        = list(string)
  default     = ["c", "m", "r"]
}

variable "instance_cpu_choices" {
  description = "Allowed vCPU counts for the default NodePool"
  type        = list(string)
  default     = ["2", "4", "8", "16"]
}

variable "node_pool_cpu_limit" {
  description = "Maximum total CPUs Karpenter is allowed to provision through the default NodePool. Cost guard-rail: the nginx demo peaks at ~5 vCPU of requests (10 × 500m)."
  type        = string
  default     = "32"
}

variable "tags" {
  description = "Tags applied to all AWS resources"
  type        = map(string)
  default     = {}
}
