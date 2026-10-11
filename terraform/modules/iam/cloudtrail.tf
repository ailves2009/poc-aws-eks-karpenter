# modules/iam/cloudtrail.tf
# IAM policies for CloudTrail management and SOC2 compliance

# Policy for CICD role to manage CloudTrail resources
resource "aws_iam_role_policy" "cicd_cloudtrail_policy" {
  name = "cloudtrail-management-policy"
  role = aws_iam_role.deploy_assume_role.id # "poc-cicd-role

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "CloudTrailManagement",
        Effect = "Allow",
        Action = [
          "cloudtrail:CreateTrail",
          "cloudtrail:UpdateTrail",
          "cloudtrail:DeleteTrail",
          "cloudtrail:DescribeTrails",
          "cloudtrail:GetTrailStatus",
          "cloudtrail:StartLogging",
          "cloudtrail:StopLogging",
          "cloudtrail:PutEventSelectors",
          "cloudtrail:GetEventSelectors",
          "cloudtrail:PutInsightSelectors",
          "cloudtrail:GetInsightSelectors",
          "cloudtrail:ListTags",
          "cloudtrail:AddTags",
          "cloudtrail:RemoveTags"
        ],
        Resource = [
          "arn:aws:cloudtrail:*:${var.account}:trail/*",
          "arn:aws:cloudtrail:*:${var.account}:eventdatastore/*"
        ]
      },
      {
        Sid    = "CloudTrailS3Access",
        Effect = "Allow",
        Action = [
          "s3:CreateBucket",
          "s3:DeleteBucket",
          "s3:GetBucketLocation",
          "s3:GetBucketPolicy",
          "s3:PutBucketPolicy",
          "s3:DeleteBucketPolicy",
          "s3:GetBucketVersioning",
          "s3:PutBucketVersioning",
          "s3:GetBucketAcl",
          "s3:PutBucketAcl",
          "s3:GetBucketLogging",
          "s3:PutBucketLogging",
          "s3:GetBucketNotification",
          "s3:PutBucketNotification",
          "s3:GetBucketPublicAccessBlock",
          "s3:PutBucketPublicAccessBlock",
          "s3:GetBucketEncryption",
          "s3:PutBucketEncryption",
          "s3:GetBucketLifecycleConfiguration",
          "s3:PutBucketLifecycleConfiguration",
          "s3:DeleteBucketLifecycleConfiguration",
          "s3:GetBucketTagging",
          "s3:PutBucketTagging",
          "s3:DeleteBucketTagging",
          "s3:ListBucket",
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:PutLifecycleConfiguration",
          "s3:GetBucketCORS",
          "s3:GetBucketWebsite",
          "s3:GetAccelerateConfiguration",
          "s3:GetBucketRequestPayment",
          "s3:GetReplicationConfiguration",
          "s3:GetEncryptionConfiguration",
          "s3:GetBucketObjectLockConfiguration"
        ],
        Resource = [
          "arn:aws:s3:::*cloudtrail*",
          "arn:aws:s3:::*cloudtrail*/*",
          "arn:aws:s3:::${var.client}-cloudtrail-logs-*",
          "arn:aws:s3:::${var.client}-cloudtrail-logs-*/*"
        ]
      },
      {
        Sid    = "CloudTrailKMSAccess",
        Effect = "Allow",
        Action = [
          "kms:CreateKey",
          "kms:CreateAlias",
          "kms:UpdateAlias",
          "kms:DeleteAlias",
          "kms:DescribeKey",
          "kms:GetKeyPolicy",
          "kms:PutKeyPolicy",
          "kms:EnableKeyRotation",
          "kms:DisableKeyRotation",
          "kms:GetKeyRotationStatus",
          "kms:TagResource",
          "kms:UntagResource",
          "kms:ListResourceTags",
          "kms:ScheduleKeyDeletion",
          "kms:CancelKeyDeletion",
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ],
        Resource = [
          "arn:aws:kms:*:${var.account}:key/*",
          "arn:aws:kms:*:${var.account}:alias/cloudtrail-*"
        ]
      },
      {
        Sid    = "CloudTrailCloudWatchLogs",
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:DeleteLogGroup",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          "logs:PutRetentionPolicy",
          "logs:DeleteRetentionPolicy",
          "logs:TagLogGroup",
          "logs:UntagLogGroup",
          "logs:ListTagsLogGroup",
          "logs:PutLogEvents",
          "logs:CreateLogStream"
        ],
        Resource = [
          "arn:aws:logs:*:${var.account}:log-group:/aws/cloudtrail/*",
          "arn:aws:logs:*:${var.account}:log-group:/aws/cloudtrail/*:*"
        ]
      },
      {
        Sid    = "CloudTrailIAMAccess",
        Effect = "Allow",
        Action = [
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:GetRole",
          "iam:UpdateRole",
          "iam:PutRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:GetRolePolicy",
          "iam:ListRolePolicies",
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
          "iam:ListAttachedRolePolicies",
          "iam:TagRole",
          "iam:UntagRole",
          "iam:GetGroup",
          "iam:ListRoleTags",
          "iam:PassRole"
        ],
        Resource = [
          "arn:aws:iam::${var.account}:role/CloudTrail-*",
          "arn:aws:iam::${var.account}:role/*cloudtrail*"
        ]
      },
      {
        Sid    = "CloudTrailServiceAccess",
        Effect = "Allow",
        Action = [
          "cloudtrail:ListTrails",
          "cloudtrail:DescribeTrails",
          "organizations:DescribeOrganization",
          "organizations:ListAccounts"
        ],
        Resource = "*"
      }
    ]
  })
}
