# /non-prod/poc/account.hcl

# Account-wide variables. Read by root.hcl (remote state, provider, IAM role)
# and by the bootstrap units.
locals {
  # Replace with your AWS account ID before first apply. Keep the real value
  # local: `git update-index --skip-worktree terraform/non-prod/poc/account.hcl`.
  # Every provider is pinned to this ID via allowed_account_ids, so a wrong
  # AWS profile fails fast instead of creating resources in another account.
  aws_account_id = "111122223333"
  account_name   = "poc"
  env            = "plt"
  client         = "poc"
  # Placeholder. The POC does not own a Route53 zone in this account, so
  # this value is only used as a Host-header suffix for the nginx Ingress
  # rule (tested via `curl --resolve`). Replace with a domain you control
  # if you want real DNS resolution + ACM. See README → "Before you start".
  domain_name        = "poc-eks-karpenter.domain.xyz"
  cicd_role_name     = "cicd-deployment-role"
  s3_terraform_state = "nyd-plt-tf-state"
  # Roles whose trust policy the CI/CD role may rewrite (IRSA / Pod Identity
  # trust changes, e.g. after an OIDC provider is recreated). Must match the
  # names the modules actually create; wildcards cover name_prefix suffixes.
  managed_role_names = [
    "KarpenterController-*",          # modules/karpenter (controller, IRSA)
    "Karpenter-*",                    # modules/karpenter (node role)
    "aws-load-balancer-controller-*", # modules/aws-lb-controller (IRSA)
    "vpc-cni-*",                      # modules/eks (Pod Identity)
    "eks-irsa-app-*",                 # reserved for application IRSA roles
  ]
  tags = {
    Env     = "plt"
    Client  = "poc"
    Managed = "terraform"
    Project = "poc-aws-eks-karpenter"
    Github  = "github.com/ailves2009/poc-aws-eks-karpenter"
  }
}
