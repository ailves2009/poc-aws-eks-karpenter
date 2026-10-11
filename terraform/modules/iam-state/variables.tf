# /modules/iamstate/variables.tf

variable "cicd_role_name" {
  description = "Имя IAM роли для Assume Role"
  type        = string
}

variable "cicd_account_arn" {
  description = "ARN CICD аккаунта, который может Assume Role"
  type        = string
}

variable "tags" {
  description = "Теги для IAM роли"
  type        = map(string)
  default     = {}
}

variable "account" {
  description = "Target AWS account ID where the IAM role will be created"
  type        = string
}

variable "region" {
  description = "AWS region where the resources will be created"
  type        = string
}

variable "s3_terraform_state" {
  description = "Name of the S3 bucket for Terraform state"
  type        = string
}

variable "managed_role_names" {
  description = "Names of IAM roles whose AssumeRole policy this CI/CD role can update (e.g., IRSA-bound roles: karpenter-controller-role, aws-load-balancer-controller-role)"
  type        = list(string)
  default     = []
}

variable "permissions_boundary_name" {
  description = "Name of the IAM policy used as permissions boundary for IAM roles that this CI/CD role creates. Created by this module (aws_iam_policy.cicd_boundary)."
  type        = string
  default     = "cicd-boundary"
}

variable "secrets_path_prefix" {
  description = "Prefix in Secrets Manager / SSM Parameter Store that this CI/CD role can read (e.g. \"poc\" -> arn:...secret:poc/*)"
  type        = string
  default     = "poc"
}
