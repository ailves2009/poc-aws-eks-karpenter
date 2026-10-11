# /modules/bastion/variables.tf

variable "create_dns_record" {
  description = "Whether to create a Route53 A-alias record for the bastion. Requires the hosted zone for var.domain_name to exist in this account. Set false if DNS lives elsewhere (then add a CNAME externally to the EIP exported by this module)."
  type        = bool
  default     = false
}

variable "domain_name" {
  description = "Hosted zone domain. Only used when create_dns_record=true."
  type        = string
  default     = ""
}

variable "subdomain" {
  description = "Subdomain label for the bastion host. Only used when create_dns_record=true."
  type        = string
  default     = "bastion"
}

variable "allowed_cidrs" {
  description = "CIDRs allowed to reach the bastion via SSH (TCP/22) and OpenVPN (UDP/1194). Lock down to your office/home IP."
  type        = list(string)
}

variable "ssh_public_key" {
  description = "OpenSSH public key for an EC2 key pair attached to the bastion (user ec2-user). Empty = no key pair; use EC2 Instance Connect or SSM instead. Changing it replaces the instance."
  type        = string
  default     = ""
}

variable "instance_type" {
  description = "EC2 instance type (must match AMI architecture; default is ARM Graviton). t4g.nano (512MB) is too small — first-boot dnf update + openvpn/easy-rsa setup hits OOM. t4g.small (2GB) is the realistic floor."
  type        = string
  default     = "t4g.small"
}

variable "permissions_boundary_arn" {
  description = "Permissions boundary ARN to attach to the bastion IAM role"
  type        = string
}

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default     = {}
}
