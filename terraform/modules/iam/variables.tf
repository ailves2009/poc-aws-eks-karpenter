# modules/iam/variables.tf

variable "cicd_role_name" {
  description = "Имя IAM роли для Assume Role"
  type        = string
}

variable "cicd_account_arn" {
  description = "ARN CICD аккаунта, который может Assume Role"
  type        = string
}

variable "tags" {
  description = "Tags for IAM roles and policies"
  type        = map(string)
  default     = {}
}

variable "region" {
  description = "AWS region where the IAM role will be created"
  type        = string
}

variable "account" {
  description = "Target AWS account ID where the IAM role will be created"
  type        = string
}

variable "client" {
  description = "Client name"
  type        = string
  default     = "poc"
}

variable "env" {
  description = "Environment name (e.g., dev, stg, prd)"
  type        = string
  default     = "dev"
}

variable "s3_terraform_state" {
  description = "S3 bucket name for Terraform state"
  type        = string
  default     = "xxx-terraform-state"
}
