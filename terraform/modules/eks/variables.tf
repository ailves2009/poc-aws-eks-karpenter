# /modules/eks/variables.tf

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version. EKS upgrades one minor version at a time; Karpenter must support the target version first (see modules/karpenter)."
  type        = string
  default     = "1.37"
}

variable "addon_versions" {
  description = "Pinned EKS addon versions, keyed by addon name (coredns, kube-proxy, vpc-cni, eks-pod-identity-agent). Addons not in the map use the most recent version for cluster_version. List with: aws eks describe-addon-versions --kubernetes-version <v> --addon-name <name>"
  type        = map(string)
  default     = {}
}

variable "vpc_id" {
  description = "VPC ID where the cluster lives"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs (>= 2 in different AZs). Used for both control plane ENIs and worker nodes."
  type        = list(string)
}

variable "cluster_endpoint_public_access" {
  description = "Whether the EKS API endpoint is reachable from the public internet"
  type        = bool
  default     = true
}

variable "cluster_endpoint_private_access" {
  description = "Whether the EKS API endpoint is reachable from inside the VPC. Karpenter, kubelet, etc. talk to the API via this path when enabled."
  type        = bool
  default     = true
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "CIDRs allowed to reach the public endpoint. POC: open to the internet on purpose (auth is still IAM). Lock down for production."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "permissions_boundary_arn" {
  description = "Permissions boundary attached to every IAM role this module creates (cluster role, node group role)"
  type        = string
}

variable "bootstrap_node_instance_types" {
  description = "Instance types for the bootstrap managed node group. Karpenter pods themselves run on these nodes — keep at least one alive."
  type        = list(string)
  default     = ["t4g.medium"] # Graviton2-based, 2 vCPU and 4 GB RAM. Adjust based on your workload needs.
}

variable "bootstrap_node_min_size" {
  type    = number
  default = 1
}

variable "bootstrap_node_max_size" {
  type    = number
  default = 2
}

variable "bootstrap_node_desired_size" {
  type    = number
  default = 1
}

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default     = {}
}
