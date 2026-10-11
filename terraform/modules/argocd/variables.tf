# /modules/argocd/variables.tf

variable "cluster_name" {
  description = "EKS cluster name. Also selects the root repository directory clusters/<cluster_name>/."
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

variable "region" {
  description = "AWS region — needed for the kubeconfig exec block"
  type        = string
}

variable "namespace" {
  description = "Namespace Argo CD is installed into"
  type        = string
  default     = "argocd"
}

variable "chart_version" {
  description = "argo-cd Helm chart version (argoproj/argo-helm). 10.9.2 = Argo CD v3.5.3."
  type        = string
  default     = "10.9.2"
}

variable "gitops_root_repo_url" {
  description = "Git URL of the root repository (ApplicationSets + projects Application). Public repo: no credentials."
  type        = string
}

variable "gitops_root_revision" {
  description = "Branch or tag of the root repository the root Application tracks"
  type        = string
  default     = "master"
}
