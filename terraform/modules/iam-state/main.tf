# /modules/iam-state/main.tf

resource "aws_iam_role" "deploy_assume_role" {
  name               = var.cicd_role_name
  assume_role_policy = data.aws_iam_policy_document.deploy_assume_policy.json

  tags = var.tags
}

data "aws_iam_policy_document" "deploy_assume_policy" {
  statement {
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = [var.cicd_account_arn]
    }
    actions = ["sts:AssumeRole"]
  }
}

# ---------------------------------------------------------------------------
# 1. S3 state access
# ---------------------------------------------------------------------------
resource "aws_iam_policy" "s3_state_access" {
  name        = "${var.cicd_role_name}-s3-state-access"
  description = "S3 state access for CI/CD role"
  policy      = data.aws_iam_policy_document.s3_state_access.json
}

data "aws_iam_policy_document" "s3_state_access" {
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
    ]
    resources = [
      "arn:aws:s3:::${var.s3_terraform_state}",
      "arn:aws:s3:::${var.s3_terraform_state}/*",
    ]
  }
}

resource "aws_iam_role_policy_attachment" "s3_state_access" {
  role       = aws_iam_role.deploy_assume_role.name
  policy_arn = aws_iam_policy.s3_state_access.arn
}

# ---------------------------------------------------------------------------
# 2. IAM management — все iam:* действия, разделённые по уровню риска
#
# KNOWN ISSUE (accepted for POC, must be fixed before prod): the CI/CD role
# can escalate to admin — CreatePolicyVersion/SetDefaultPolicyVersion on
# policy/* covers its own policies; the boundary (section 6) is Allow *, so
# a bounded role with AdministratorAccess is effectively admin;
# PutRolePermissionsBoundary/DeleteRolePermissionsBoundary are unconditioned.
# See README → "Roadmap to production".
# ---------------------------------------------------------------------------
resource "aws_iam_policy" "iam_management" {
  name        = "${var.cicd_role_name}-iam-management"
  description = "IAM management permissions for CI/CD role"
  policy      = data.aws_iam_policy_document.iam_management.json
}

data "aws_iam_policy_document" "iam_management" {
  # 2a. Read-only — safe everywhere
  statement {
    sid    = "IamReadOnly"
    effect = "Allow"
    actions = [
      "iam:GetRole",
      "iam:GetRolePolicy",
      "iam:GetPolicy",
      "iam:GetPolicyVersion",
      "iam:GetGroup",
      "iam:GetGroupPolicy",
      "iam:GetOpenIDConnectProvider",
      "iam:ListRolePolicies",
      "iam:ListPolicyVersions",
      "iam:ListInstanceProfilesForRole",
      "iam:ListAttachedRolePolicies",
      "iam:ListOpenIDConnectProviders",
    ]
    resources = ["*"]
  }

  # 2b. Create roles and attach policies — only with permissions boundary
  # This prevents privilege escalation: cannot create a role with permissions beyond the boundary.
  statement {
    sid    = "IamCreateRoleWithBoundary"
    effect = "Allow"
    actions = [
      "iam:CreateRole",
      "iam:AttachRolePolicy",
      "iam:PutRolePolicy",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "iam:PermissionsBoundary"
      values   = ["arn:aws:iam::${var.account}:policy/${var.permissions_boundary_name}"]
    }
  }

  # 2b'. Service-linked roles cannot have a permissions boundary (AWS-managed),
  # so they need a separate statement. Scoped to the SLR ARN namespace.
  statement {
    sid       = "IamCreateServiceLinkedRole"
    effect    = "Allow"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["arn:aws:iam::${var.account}:role/aws-service-role/*"]
  }

  # 2c. PassRole — only for AWS services that we use
  statement {
    sid       = "IamPassRoleToAwsServices"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = ["arn:aws:iam::${var.account}:role/*"]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values = [
        "eks.amazonaws.com",
        "ec2.amazonaws.com",
        "elasticloadbalancing.amazonaws.com",
        "pods.eks.amazonaws.com", # EKS Pod Identity associations (VPC CNI, etc.)
      ]
    }
  }

  # 2d. Manage IAM policies — only in the current account
  statement {
    sid    = "IamManagePolicies"
    effect = "Allow"
    actions = [
      "iam:CreatePolicy",
      "iam:DeletePolicy",
      "iam:CreatePolicyVersion",
      "iam:DeletePolicyVersion",
      "iam:SetDefaultPolicyVersion",
      "iam:TagPolicy",
      "iam:UntagPolicy",
    ]
    resources = ["arn:aws:iam::${var.account}:policy/*"]
  }

  # 2e. Modify roles — only for roles in this account
  statement {
    sid    = "IamModifyRoles"
    effect = "Allow"
    actions = [
      "iam:DeleteRole",
      "iam:DeleteRolePolicy",
      "iam:DetachRolePolicy",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:PutRolePermissionsBoundary",
      "iam:DeleteRolePermissionsBoundary",
    ]
    resources = ["arn:aws:iam::${var.account}:role/*"]
  }

  # 2f. UpdateAssumeRolePolicy — only for the list of managed_role_names
  statement {
    sid     = "IamUpdateAssumeRolePolicy"
    effect  = "Allow"
    actions = ["iam:UpdateAssumeRolePolicy"]
    resources = [
      for name in var.managed_role_names : "arn:aws:iam::${var.account}:role/${name}"
    ]
  }

  # 2g. OIDC providers (one per cluster, for IRSA)
  statement {
    sid    = "IamOidcProviders"
    effect = "Allow"
    actions = [
      "iam:CreateOpenIDConnectProvider",
      "iam:DeleteOpenIDConnectProvider",
      "iam:UpdateOpenIDConnectProviderThumbprint",
      "iam:TagOpenIDConnectProvider",
      "iam:UntagOpenIDConnectProvider",
    ]
    resources = ["arn:aws:iam::${var.account}:oidc-provider/*"]
  }

  # 2h. Instance profiles — for EC2 (bastion, EKS nodes provisioned by Karpenter)
  statement {
    sid    = "IamInstanceProfiles"
    effect = "Allow"
    actions = [
      "iam:CreateInstanceProfile",
      "iam:DeleteInstanceProfile",
      "iam:GetInstanceProfile",
      "iam:AddRoleToInstanceProfile",
      "iam:RemoveRoleFromInstanceProfile",
      "iam:TagInstanceProfile",
      "iam:UntagInstanceProfile",
    ]
    resources = ["arn:aws:iam::${var.account}:instance-profile/*"]
  }
}

resource "aws_iam_role_policy_attachment" "iam_management" {
  role       = aws_iam_role.deploy_assume_role.name
  policy_arn = aws_iam_policy.iam_management.arn
}

# ---------------------------------------------------------------------------
# 3. Infra — create/delete AWS resources (compute, networking, security, observability)
# ---------------------------------------------------------------------------
resource "aws_iam_policy" "infra" {
  name        = "${var.cicd_role_name}-infra"
  description = "Infrastructure (create/update/delete) permissions for CI/CD role"
  policy      = data.aws_iam_policy_document.infra.json
}

data "aws_iam_policy_document" "infra" {
  # Compute — EKS + EC2 + Launch Templates
  statement {
    sid    = "Compute"
    effect = "Allow"
    actions = [
      "eks:*",
      "ec2:*",
      "autoscaling:*",
    ]
    resources = ["*"]
  }

  # Networking — VPC + ELB + Route53
  statement {
    sid    = "Networking"
    effect = "Allow"
    actions = [
      "elasticloadbalancing:*",
      "route53:*",
    ]
    resources = ["*"]
  }

  # KMS — keys for EKS envelope encryption (secrets), EBS volumes, etc.
  statement {
    sid    = "Kms"
    effect = "Allow"
    actions = [
      "kms:CreateKey",
      "kms:CreateAlias",
      "kms:DeleteAlias",
      "kms:UpdateAlias",
      "kms:DescribeKey",
      "kms:GetKeyPolicy",
      "kms:GetKeyRotationStatus",
      "kms:EnableKeyRotation",
      "kms:PutKeyPolicy",
      "kms:ScheduleKeyDeletion",
      "kms:ListAliases",
      "kms:ListResourceTags",
      "kms:TagResource",
      "kms:CreateGrant",
      "kms:ListGrants",
      "kms:RevokeGrant",
    ]
    resources = ["*"]
  }

  # ACM / ACM Private CA — certificates
  statement {
    sid    = "Certificates"
    effect = "Allow"
    actions = [
      "acm:*",
      "acm-pca:*",
    ]
    resources = ["*"]
  }

  # Secrets Manager — write/manage (in runtime)
  statement {
    sid    = "SecretsManagerWrite"
    effect = "Allow"
    actions = [
      "secretsmanager:CreateSecret",
      "secretsmanager:PutSecretValue",
      "secretsmanager:DeleteSecret",
      "secretsmanager:DescribeSecret",
      "secretsmanager:ListSecrets",
      "secretsmanager:GetResourcePolicy",
      "secretsmanager:TagResource",
    ]
    resources = ["*"]
  }

  # Observability — CloudWatch + Logs
  statement {
    sid    = "Observability"
    effect = "Allow"
    actions = [
      "cloudwatch:*",
      "logs:*",
    ]
    resources = ["*"]
  }

  # SNS — topics for alarms etc.
  statement {
    sid    = "Sns"
    effect = "Allow"
    actions = [
      "sns:CreateTopic",
      "sns:DeleteTopic",
      "sns:Subscribe",
      "sns:Unsubscribe",
      "sns:GetTopicAttributes",
      "sns:SetTopicAttributes",
      "sns:GetSubscriptionAttributes",
      "sns:ListTagsForResource",
      "sns:TagResource",
    ]
    resources = ["arn:aws:sns:${var.region}:${var.account}:*"]
  }

  # SQS — Karpenter spot-interruption queue, etc.
  statement {
    sid       = "Sqs"
    effect    = "Allow"
    actions   = ["sqs:*"]
    resources = ["arn:aws:sqs:${var.region}:${var.account}:*"]
  }

  # EventBridge — Karpenter routes EC2 spot/health events through it.
  statement {
    sid       = "EventBridge"
    effect    = "Allow"
    actions   = ["events:*"]
    resources = ["arn:aws:events:${var.region}:${var.account}:*"]
  }

  # ECR — image build/push (CI builds)
  statement {
    sid    = "EcrWrite"
    effect = "Allow"
    actions = [
      "ecr:CreateRepository",
      "ecr:DescribeRepositories",
      "ecr:DescribeImages",
      "ecr:ListImages",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
      "ecr:BatchCheckLayerAvailability",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy_attachment" "infra" {
  role       = aws_iam_role.deploy_assume_role.name
  policy_arn = aws_iam_policy.infra.arn
}

# ---------------------------------------------------------------------------
# 4. Runtime — узкое чтение секретов/параметров и ECR auth
# ---------------------------------------------------------------------------
resource "aws_iam_policy" "runtime" {
  name        = "${var.cicd_role_name}-runtime"
  description = "Runtime data-plane reads for CI/CD role"
  policy      = data.aws_iam_policy_document.runtime.json
}

data "aws_iam_policy_document" "runtime" {
  statement {
    sid    = "SecretsManagerRead"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
    ]
    resources = [
      "arn:aws:secretsmanager:${var.region}:${var.account}:secret:${var.secrets_path_prefix}/*",
    ]
  }

  statement {
    sid    = "SsmParameterRead"
    effect = "Allow"
    actions = [
      "ssm:GetParameter",
    ]
    resources = [
      "arn:aws:ssm:${var.region}:${var.account}:parameter/${var.secrets_path_prefix}/*",
    ]
  }

  statement {
    sid    = "EcrAuthToken"
    effect = "Allow"
    actions = [
      "ecr:GetAuthorizationToken",
    ]
    resources = ["*"]
  }

  # ECR Public — for pulling Helm charts from oci://public.ecr.aws
  # (Karpenter, AWS Load Balancer Controller, etc.). Different service
  # from regular ECR. sts:GetServiceBearerToken is required by the auth flow.
  statement {
    sid    = "EcrPublicAuthToken"
    effect = "Allow"
    actions = [
      "ecr-public:GetAuthorizationToken",
      "sts:GetServiceBearerToken",
    ]
    resources = ["*"]
  }

  # SSM Session Manager — for `aws ssm start-session` into bastion / EKS
  # nodes / any EC2 with the SSM agent. Used by operators (humans) when
  # they assume cicd-deployment-role for kubectl/cluster ops.
  statement {
    sid    = "SsmSessionManager"
    effect = "Allow"
    actions = [
      "ssm:StartSession",
      "ssm:TerminateSession",
      "ssm:ResumeSession",
      "ssm:DescribeSessions",
      "ssm:DescribeInstanceInformation",
      "ssm:DescribeInstanceProperties",
      "ssm:GetConnectionStatus",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy_attachment" "runtime" {
  role       = aws_iam_role.deploy_assume_role.name
  policy_arn = aws_iam_policy.runtime.arn
}

# ---------------------------------------------------------------------------
# 5. AWS service-linked roles
# Account-level one-time bootstrap. Karpenter (and any plain RunInstances
# call requesting Spot) needs AWSServiceRoleForEC2Spot to exist in the
# account; AWS does not auto-create it unless the caller has
# iam:CreateServiceLinkedRole, which we'd rather not grant Karpenter's
# IRSA role. So we create it once here.
# ---------------------------------------------------------------------------
resource "aws_iam_service_linked_role" "ec2_spot" {
  aws_service_name = "spot.amazonaws.com"
  description      = "Required for Karpenter (and any spot instance launches) to provision EC2 Spot capacity."
}

# ---------------------------------------------------------------------------
# 6. Permissions boundary
# Standalone policy. NOT attached to cicd-deployment-role.
# Referenced via `permissions_boundary = ...` on roles that CI/CD creates
# (karpenter-controller-role, IRSA roles, etc.), and enforced by the
# IamCreateRoleWithBoundary statement above (CI/CD cannot create a role
# without this boundary attached).
# ---------------------------------------------------------------------------
resource "aws_iam_policy" "cicd_boundary" {
  name        = var.permissions_boundary_name
  description = "Permissions boundary for IAM roles created by ${var.cicd_role_name}. Caps the maximum effective permissions of those roles."
  policy      = data.aws_iam_policy_document.cicd_boundary.json
}

data "aws_iam_policy_document" "cicd_boundary" {
  # POC: roles bounded by this policy may use any AWS action,
  # subject to their own attached policies. Tighten for production.
  statement {
    sid       = "AllowAll"
    effect    = "Allow"
    actions   = ["*"]
    resources = ["*"]
  }

  # Anti-escalation: roles bounded by this policy cannot remove or
  # weaken the boundary on themselves or other principals.
  statement {
    sid    = "DenyBoundaryTampering"
    effect = "Deny"
    actions = [
      "iam:DeleteRolePermissionsBoundary",
      "iam:PutRolePermissionsBoundary",
      "iam:DeleteUserPermissionsBoundary",
      "iam:PutUserPermissionsBoundary",
    ]
    resources = ["*"]
  }
}
