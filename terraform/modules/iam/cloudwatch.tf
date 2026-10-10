# modules/iam/cloudwatch.tf
# https://repost.aws/questions/QUUWdk2GyPRKeTadZ9EpO3aQ/least-privilege-cloudwatch-logs-policy-for-api-gateway

resource "aws_iam_role" "apigw_cloudwatch_logs" {
  name = "cloudwatch-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "apigateway.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "apigw_cloudwatch_logs" {
  name = "cloudwatch-logs-policy"
  role = aws_iam_role.apigw_cloudwatch_logs.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "CloudWatchAccess1",
        Effect = "Allow",
        Action = [
          "logs:GetLogEvents",
          "logs:PutLogEvents"
        ],
        Resource = "arn:aws:logs:${var.region}:${var.account}:log-group:*:log-stream:*"
      },
      {
        Sid    = "CloudWatchAccess2",
        Effect = "Allow",
        Action = [
          "logs:CreateLogStream",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          "logs:FilterLogEvents",
          "logs:CreateLogGroup"
        ],
        Resource = "arn:aws:logs:${var.region}:${var.account}:log-group:*"
      }
    ]
  })
}
