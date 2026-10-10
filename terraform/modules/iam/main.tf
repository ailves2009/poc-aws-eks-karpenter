# modules/iam/main.tf
#
# LEGACY: not referenced by any terragrunt unit — superseded by
# modules/iam-state (boundary-scoped CI/CD role). Kept for reference only.
# Several statements below are intentionally broad ("*" resources,
# iam:PassRole/CreateRole without a permissions boundary) and must be
# tightened before this module is used anywhere.

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

# S3 policy
resource "aws_iam_policy" "s3_state_access_policy" {
  name        = "${var.cicd_role_name}-s3-state-access-policy"
  description = "S3 state access permissions for CI/CD role"

  policy = data.aws_iam_policy_document.s3_state_access_permissions.json
}
data "aws_iam_policy_document" "s3_state_access_permissions" {
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket"
    ]
    resources = [
      "arn:aws:s3:::${var.s3_terraform_state}",
      "arn:aws:s3:::${var.s3_terraform_state}/*"
    ]
  }
}

resource "aws_iam_role_policy_attachment" "deploy_assume_s3_state_policy_attachment" {
  role       = aws_iam_role.deploy_assume_role.name
  policy_arn = aws_iam_policy.s3_state_access_policy.arn
}

// deploy-core-policy
resource "aws_iam_policy" "deploy_core_policy" {
  name        = "${var.cicd_role_name}-core-policy"
  description = "Core permissions for CI/CD role"

  policy = data.aws_iam_policy_document.deploy_core_permissions.json
}

data "aws_iam_policy_document" "deploy_core_permissions" {
  #EKS permissions 4*
  statement {
    effect = "Allow"
    actions = [
      "eks:CreateNodegroup",
      "eks:DescribeNodegroup",
      "eks:DeleteNodegroup",
      "eks:DescribeCluster",
      "eks:CreateCluster",
      "eks:CreateAddon",
      "eks:UpdateClusterConfig",
      "eks:UpdateNodegroupConfig",
      "eks:DescribeAddon",
      "eks:TagResource",
      "eks:ListAddons",
      "eks:ListNodegroups"
    ]
    resources = [
      "*"
      # "arn:aws:eks:${var.region}:${var.account}:cluster/${var.client}-${var.env}-eks"
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "sns:CreateTopic",
      "sns:TagResource",
      "sns:ListTagsForResource",
      "sns:Subscribe",
      "sns:Unsubscribe",
      "sns:Publish",
      "sns:DeleteTopic",
      "sns:GetTopicAttributes",
      "sns:SetTopicAttributes",
      "sns:GetSubscriptionAttributes"
    ]
    resources = [
      "arn:aws:sns:${var.region}:${var.account}:*"
    ]
  }

  # IAM permissions 4 role/eks-irsa-role
  statement {
    effect = "Allow"
    actions = [
      "iam:UpdateAssumeRolePolicy"
    ]
    resources = [
      "arn:aws:iam::${var.account}:role/eks-irsa-role",
      "arn:aws:iam::${var.account}:role/rds-app-access-role",
    ]
  }

  # KMS permissions 4*
  statement {
    effect = "Allow"
    actions = [
      "kms:UpdateAlias"
    ]
    resources = [
      "*"
      # "arn:aws:kms:${var.region}:${var.account}:alias/eks/${var.env}-${var.client}-eks"
    ]
  }

  # Amplify permissions 4*
  statement {
    effect = "Allow"
    actions = [
      "amplify:CreateApp",
      "amplify:*"
    ]
    resources = [
      "*"
      #"arn:aws:amplify:${var.region}:${var.account}:apps/*"
    ]
  }

  # SSM permissions 4*
  statement {
    effect = "Allow"
    actions = [
      "ssm:GetParameter"
    ]
    resources = [
      "*"
    ]
  }

  # IAM permissions 4*
  statement {
    effect = "Allow"
    actions = [
      "iam:DeletePolicyVersion",
      "iam:CreatePolicyVersion",
      "iam:UpdateAccountPasswordPolicy",
      "iam:GetAccountPasswordPolicy",
      "iam:DeleteAccountPasswordPolicy",
      "iam:SetDefaultPolicyVersion",

    ]
    resources = [
      "*"
      #"arn:aws:iam::${var.account}:policy/cicd-deployment-role-policy"
      #"arn:aws:iam::${var.account}:policy/eks-irsa-role-policy"
    ]
  }

  # allow creating/managing instance profiles and passing roles (for CI/CD role that runs Terraform)
  statement {
    effect = "Allow"
    actions = [
      "iam:CreateInstanceProfile",
      "iam:DeleteInstanceProfile",
      "iam:AddRoleToInstanceProfile",
      "iam:RemoveRoleFromInstanceProfile",
      "iam:GetInstanceProfile",
      "iam:ListInstanceProfilesForRole",
      "iam:ListInstanceProfiles",
      "iam:PassRole",
      "iam:CreateServiceLinkedRole",
      "iam:TagInstanceProfile",
    ]
    resources = ["*"]
  }

  # ECR permissions 4*
  statement {
    effect = "Allow"
    actions = [
      "ecr:DescribeImages",
      "ecr:CreateRepository",
      "ecr:GetAuthorizationToken",
      "ecr:DescribeRepositories",
      "ecr:ListImages",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
      "ecr:BatchCheckLayerAvailability"
    ]
    resources = [
      "*"
    ]
  }

  # Route53 permissions 4*
  statement {
    effect = "Allow"
    actions = [
      "route53:CreateHostedZone",
      "route53:GetHostedZone",
      "route53:ListHostedZones",
      "route53:ChangeResourceRecordSets",
      "route53:ListResourceRecordSets",
      "route53:DeleteHostedZone",
      "route53:GetChange",
      "route53:ListTagsForResource",
      "route53:ChangeTagsForResource"
    ]
    resources = [
      "*"
    ]
  }

  # S3 permissions 4*
  statement {
    effect = "Allow"
    actions = [
      "s3:PutBucketVersioning",
      "s3:PutBucketPolicy",
      "s3:PutBucketLogging",
      "s3:PutEncryptionConfiguration",
      "s3:ListBucket",
      "s3:GetBucketLocation",
      "s3:DeleteBucket",
      "s3:CreateBucket",
      "s3:GetBucketTagging",
      "s3:GetBucketPolicy",
      "s3:GetBucketAcl",
      "s3:GetBucketCORS",
      "s3:GetBucketWebsite",
      "s3:GetBucketVersioning",
      "s3:GetAccelerateConfiguration",
      "s3:GetBucketRequestPayment",
      "s3:GetBucketLogging",
      "s3:GetLifecycleConfiguration",
      "s3:GetReplicationConfiguration",
      "s3:GetEncryptionConfiguration",
      "s3:GetBucketObjectLockConfiguration",
      "s3:PutBucketTagging",
      "s3:GetBucketOwnershipControls",
      "s3:GetBucketPublicAccessBlock",
      "s3:GetObject",
      "s3:PutObject",
      "s3:ObjectOwnerOverrideToBucketOwner",
      "s3:PutObjectTagging", # for replication from client-xxx-detections

      "s3:ListAllMyBuckets",
      "s3:PutBucketPublicAccessBlock",
      "s3:PutBucketOwnershipControls",
      "s3:PutBucketAcl",
      "s3:PutBucketNotification",
      "s3:GetBucketNotification",
      "s3:PutBucketPolicy",
      "s3:PutBucketCORS",
      "s3:ListBucketVersions",
      "s3:DeleteBucketPolicy",
      "s3:DeleteObjectVersion"
    ]
    resources = [
      "*"
    ]
  }
}

resource "aws_iam_role_policy_attachment" "deploy_assume_core_policy_attachment" {
  role       = aws_iam_role.deploy_assume_role.name
  policy_arn = aws_iam_policy.deploy_core_policy.arn
}

// deploy-infra-policy
resource "aws_iam_policy" "deploy_infra_policy" {
  name        = "${var.cicd_role_name}-infra-policy"
  description = "Infra permissions for CI/CD role"

  policy = data.aws_iam_policy_document.deploy_infra_permissions.json
}

data "aws_iam_policy_document" "deploy_infra_permissions" {
  # KMS, IAM, EKS, SQS, EC2, APIGW, LOGS, SECRETSMANAGER, RDS, ACM-PCA, ELB, CLOUDFORMATION, SNS, CLOUDWATCH permissions 4*
  statement {
    effect = "Allow"
    actions = [
      "kms:TagResource",
      "kms:ScheduleKeyDeletion",
      "kms:ListResourceTags",
      "kms:GetKeyRotationStatus",
      "kms:GetKeyPolicy",
      "kms:EnableKeyRotation",
      "kms:DescribeKey",
      "kms:CreateKey",
      "kms:CreateAlias",
      "kms:ListAliases",
      "kms:DeleteAlias",
      "kms:PutKeyPolicy",

      "iam:TagRole",
      "iam:PassRole",
      "iam:ListRolePolicies",
      "iam:ListPolicyVersions",
      "iam:ListInstanceProfilesForRole",
      "iam:ListAttachedRolePolicies",
      "iam:GetRole",
      "iam:GetPolicyVersion",
      "iam:GetPolicy",
      "iam:DeleteRole",
      "iam:DeletePolicy",
      "iam:CreateRole",
      "iam:CreatePolicy",
      "iam:AttachRolePolicy",
      "iam:PutRolePolicy",
      "iam:GetRolePolicy",
      "iam:CreateServiceLinkedRole",
      "iam:GetInstanceProfile",

      "iam:CreateOpenIDConnectProvider",
      "iam:TagOpenIDConnectProvider",
      "iam:UntagOpenIDConnectProvider",
      "iam:GetOpenIDConnectProvider",
      "iam:DeleteOpenIDConnectProvider",
      "iam:UpdateOpenIDConnectProviderThumbprint",
      "iam:ListOpenIDConnectProviders",

      "iam:DeleteRolePolicy",
      "iam:DetachRolePolicy",
      "iam:TagPolicy",
      "iam:UntagRole",
      "iam:UntagPolicy",
      "iam:UntagRole",
      "iam:GetGroup",
      "iam:GetGroupPolicy",

      "eks:*",
      "sqs:CreateQueue",
      "sqs:tagqueue",
      "sqs:getqueueattributes",
      "sqs:listqueuetags",
      "sqs:deletequeue",
      "sqs:SetQueueAttributes",
      "sqs:TagQueue",
      "sqs:UntagQueue",

      "ec2:*", # !!!!
      "ec2:CreateVpc",
      "ec2:DescribeVpcs",
      "ec2:DeleteVpc",
      "ec2:CreateTags",
      "ec2:DescribeTags",
      "ec2:DescribeVpcAttribute",
      "ec2:ModifyVpcAttribute",
      "ec2:DescribeAvailabilityZones",
      "ec2:CreateSubnet",
      "ec2:DescribeSubnets",
      "ec2:DeleteSubnet",
      "ec2:CreateRouteTable",
      "ec2:DescribeRouteTables",
      "ec2:DeleteRouteTable",
      "ec2:AssociateRouteTable",
      "ec2:DisassociateRouteTable",
      "ec2:CreateRoute",
      "ec2:ReplaceRoute",
      "ec2:DeleteRoute",
      "ec2:CreateInternetGateway",
      "ec2:DescribeInternetGateways",
      "ec2:DeleteInternetGateway",
      "ec2:AttachInternetGateway",
      "ec2:DetachInternetGateway",
      "ec2:CreateNatGateway",
      "ec2:DescribeNatGateways",
      "ec2:DeleteNatGateway",
      "ec2:AllocateAddress",
      "ec2:ReleaseAddress",
      "ec2:DescribeAddresses",
      "ec2:DescribeSecurityGroups",
      "ec2:CreateSecurityGroup",
      "ec2:DeleteSecurityGroup",
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:RevokeSecurityGroupIngress",
      "ec2:AuthorizeSecurityGroupEgress",
      "ec2:RevokeSecurityGroupEgress",
      "ec2:DescribeAddressesAttribute",
      "ec2:DescribeSecurityGroupRules",
      "ec2:CreateLaunchTemplate",
      "ec2:DescribeLaunchTemplates",
      "ec2:DescribeLaunchTemplateVersions",
      "ec2:RunInstances",
      "ec2:CreateLaunchTemplate",
      "ec2:DeleteLaunchTemplate",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DisassociateAddress",
      "ec2:CreateClientVpnEndpoint",
      "ec2:AssociateAddress",

      #for apigateway
      "ec2:DescribeVpcEndpoints",
      "ec2:DescribeVpcEndpointServices",
      "ec2:CreateVpcEndpointServiceConfiguration",
      "ec2:DeleteVpcEndpointServiceConfigurations",
      "elasticloadbalancing:DescribeLoadBalancers",
      "elasticloadbalancing:DescribeListeners",
      "elasticloadbalancing:DescribeTargetGroups",
      "apigateway:GET",
      "apigateway:POST",
      "apigateway:PUT",
      "apigateway:PATCH",
      "apigateway:DELETE",

      "logs:CreateLogGroup",
      "logs:DescribeLogGroups",
      "logs:PutRetentionPolicy",
      "logs:DeleteLogGroup",
      "logs:TagResource",
      "logs:ListTagsForResource",
      "logs:CreateLogDelivery",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:PutResourcePolicy",
      "logs:*",

      "secretsmanager:CreateSecret",
      "secretsmanager:PutSecretValue",
      "secretsmanager:DeleteSecret",
      "secretsmanager:TagResource",
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
      "secretsmanager:ListSecrets",
      "secretsmanager:GetResourcePolicy",

      "rds:CreateDBSubnetGroup",
      "rds:CreateDBParameterGroup",
      "rds:DescribeDBSubnetGroups",
      "rds:DescribeDBParameterGroups",
      "rds:ModifyDBSubnetGroup",
      "rds:ModifyDBParameterGroup",
      "rds:DeleteDBSubnetGroup",
      "rds:DeleteDBParameterGroup",
      "rds:AddTagsToResource",
      "rds:ListTagsForResource",
      "rds:DescribeDBParameters",
      "rds:CreateDBInstance",
      "rds:DescribeDBInstances",
      "rds:DeleteDBInstance",
      "rds:CreateDBSnapshot",
      "rds:DeleteDBSnapshot",
      "rds:ModifyDBInstance",

      "acm-pca:PutPolicy",
      "acm-pca:GetPolicy",
      "acm-pca:DeletePolicy",
      "acm:RequestCertificate",
      "acm:DescribeCertificate",
      "acm:DeleteCertificate",
      "acm:AddTagsToCertificate",
      "acm:ListCertificates",
      "acm:ListTagsForCertificate",
      "acm-pca:CreateCertificateAuthority",
      "acm-pca:TagCertificateAuthority",
      "acm-pca:DescribeCertificateAuthority",
      "acm-pca:GetCertificate",
      "acm-pca:GetCertificateAuthority",
      "acm-pca:GetCertificateAuthorityCertificate",
      "acm-pca:GetCertificateAuthorityCsr",
      "acm-pca:ListTags",
      "acm:ImportCertificate",
      "acm-pca:UpdateCertificateAuthority",
      "acm-pca:DeleteCertificateAuthority",
      "acm-pca:ListCertificateAuthorities",
      "acm-pca:ImportCertificateAuthorityCertificate",
      "acm-pca:IssueCertificate",
      "acm-pca:RevokeCertificate",
      "acm-pca:UntagCertificateAuthority",
      "acm-pca:ListTagsForResource",
      "acm-pca:CreatePermission",
      "acm-pca:DeletePermission",
      "acm-pca:ListPermissions",

      "elasticloadbalancing:*",

      "cloudformation:ListStacks",
      "cloudformation:CreateStack",

      "cloudwatch:PutMetricAlarm",
      "cloudwatch:PutDashboard",
      "cloudwatch:DescribeAlarms",
      "cloudwatch:GetDashboard",
      "cloudwatch:ListTagsForResource",
      "cloudwatch:DeleteAlarms",
      "cloudwatch:DeleteDashboards",
      "cloudwatch:TagResource"
    ]

    resources = ["*"] # tbd конкретные ресурсы
  }
}

resource "aws_iam_role_policy_attachment" "deploy_assume_infra_policy_attachment" {
  role       = aws_iam_role.deploy_assume_role.name
  policy_arn = aws_iam_policy.deploy_infra_policy.arn
}

resource "aws_iam_group" "developers" {
  name = "developers"
}

resource "aws_iam_group_policy" "developers_ecr" {
  name  = "developers-ecr"
  group = aws_iam_group.developers.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:GetRepositoryPolicy",
          "ecr:DescribeRepositories",
          "ecr:ListImages",
          "ecr:DescribeImages",
          "ecr:BatchGetImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage"
        ]
        Resource = "*"
      }
    ]
  })
}
