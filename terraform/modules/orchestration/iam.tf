# Lambda Role
resource "aws_iam_role" "lambda_role" {
  name = "cloudpress-api-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "cloudpress-api-lambda-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:Scan",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem"
        ]
        Resource = aws_dynamodb_table.sites.arn
      },
      {
        Effect = "Allow"
        Action = [
          "codebuild:StartBuild"
        ]
        Resource = aws_codebuild_project.orchestrator.arn
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = [
          "arn:aws:logs:us-east-1:*:log-group:/aws/lambda/cloudpress-api:*",
          "arn:aws:logs:us-east-1:*:log-group:/aws/lambda/cloudpress-monitor:*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:RebootInstances",
          "ec2:CreateImage",
          "elasticloadbalancing:DescribeLoadBalancers"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "rds:CreateDBSnapshot"
        ]
        Resource = [
          "arn:aws:rds:us-east-1:*:db:cloudpress-*",
          "arn:aws:rds:us-east-1:*:snapshot:cloudpress-db-backup-*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:SendCommand",
          "ssm:GetCommandInvocation"
        ]
        Resource = [
          "arn:aws:ec2:us-east-1:*:instance/*",
          "arn:aws:ssm:us-east-1:*:document/AWS-RunShellScript",
          "arn:aws:ssm:us-east-1:*:*"
        ]
      }
    ]
  })
}

# CodeBuild Role
resource "aws_iam_role" "codebuild_role" {
  name = "cloudpress-orchestrator-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "codebuild.amazonaws.com"
        }
      }
    ]
  })
}

data "aws_caller_identity" "current" {}

resource "aws_iam_role_policy" "codebuild_policy" {
  name = "cloudpress-orchestrator-policy"
  role = aws_iam_role.codebuild_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem"
        ]
        Resource = aws_dynamodb_table.sites.arn
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:us-east-1:*:log-group:/aws/codebuild/cloudpress-orchestrator:*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion"
        ]
        Resource = "${aws_s3_bucket.orchestrator_source.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = [
          aws_s3_bucket.terraform_state.arn,
          "${aws_s3_bucket.terraform_state.arn}/*"
        ]
      },
      {
        # EC2, VPC, ALB
        Effect = "Allow"
        Action = [
          "ec2:*",
          "elasticloadbalancing:*"
        ]
        Resource = [
          "arn:aws:ec2:us-east-1:${data.aws_caller_identity.current.account_id}:*/*",
          "arn:aws:ec2:us-east-1::image/ami-*",
          "arn:aws:elasticloadbalancing:us-east-1:${data.aws_caller_identity.current.account_id}:*/*"
        ]
      },
      {
        # Global or region-agnostic resources needed by EC2
        Effect = "Allow"
        Action = [
          "ec2:Describe*",
          "elasticloadbalancing:Describe*"
        ]
        Resource = "*"
      },
      {
        # IAM bounded to cloudpress prefix
        Effect = "Allow"
        Action = [
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:PutRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
          "iam:CreateInstanceProfile",
          "iam:DeleteInstanceProfile",
          "iam:AddRoleToInstanceProfile",
          "iam:RemoveRoleFromInstanceProfile",
          "iam:PassRole",
          "iam:CreatePolicy",
          "iam:DeletePolicy",
          "iam:TagRole",
          "iam:GetRole",
          "iam:GetPolicy",
          "iam:GetPolicyVersion",
          "iam:ListRolePolicies",
          "iam:ListAttachedRolePolicies",
          "iam:GetInstanceProfile",
          "iam:ListInstanceProfilesForRole"
        ]
        Resource = [
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/cloudpress-*",
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/cloudpress-*",
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:instance-profile/cloudpress-*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "iam:ListPolicies",
          "iam:ListRoles"
        ]
        Resource = "*"
      },
      {
        # RDS bounded
        Effect = "Allow"
        Action = [
          "rds:*"
        ]
        Resource = [
          "arn:aws:rds:us-east-1:${data.aws_caller_identity.current.account_id}:db:cloudpress-*",
          "arn:aws:rds:us-east-1:${data.aws_caller_identity.current.account_id}:subgrp:cloudpress-*"
        ]
      },
      {
        Effect   = "Allow"
        Action   = "rds:Describe*"
        Resource = "*"
      },
      {
        # S3 for media buckets
        Effect = "Allow"
        Action = [
          "s3:*"
        ]
        Resource = [
          "arn:aws:s3:::cloudpress-media-*",
          "arn:aws:s3:::cloudpress-media-*/*"
        ]
      },
      {
        # SecretsManager
        Effect = "Allow"
        Action = [
          "secretsmanager:*"
        ]
        Resource = "arn:aws:secretsmanager:us-east-1:${data.aws_caller_identity.current.account_id}:secret:cloudpress/*"
      },
      {
        # SSM for Ansible
        Effect = "Allow"
        Action = [
          "ssm:StartSession",
          "ssm:SendCommand",
          "ssm:DescribeInstanceInformation"
        ]
        Resource = [
          "arn:aws:ec2:us-east-1:${data.aws_caller_identity.current.account_id}:instance/*",
          "arn:aws:ssm:us-east-1:*:document/AWS-StartSSHSession"
        ]
      },
      {
        # Route53 / CloudFront / CloudWatch Alarms
        Effect = "Allow"
        Action = [
          "route53:*",
          "cloudfront:*",
          "cloudwatch:PutMetricAlarm",
          "cloudwatch:DeleteAlarms",
          "cloudwatch:DescribeAlarms",
          "cloudwatch:ListTagsForResource",
          "cloudwatch:TagResource",
          "cloudwatch:UntagResource"
        ]
        Resource = "*"
      }
    ]
  })
}
