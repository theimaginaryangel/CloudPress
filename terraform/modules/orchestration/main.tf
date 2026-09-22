# 1. DynamoDB
resource "aws_dynamodb_table" "sites" {
  name         = "cloudpress-sites"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "site_id"

  attribute {
    name = "site_id"
    type = "S"
  }
}

# 2. S3 Bucket for CodeBuild Source
resource "aws_s3_bucket" "orchestrator_source" {
  bucket_prefix = "cloudpress-orchestrator-src-"
}

# 3. CodeBuild Project
resource "aws_codebuild_project" "orchestrator" {
  name         = "cloudpress-orchestrator"
  service_role = aws_iam_role.codebuild_role.arn

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = "aws/codebuild/standard:7.0"
    type            = "LINUX_CONTAINER"
    privileged_mode = false
  }

  source {
    type      = "S3"
    location  = "${aws_s3_bucket.orchestrator_source.bucket}/source.zip"
    buildspec = "api/buildspec.yml"
  }
}

# 4. API Lambda
data "archive_file" "api_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../../../api"
  output_path = "${path.module}/api.zip"
}

resource "aws_lambda_function" "api" {
  filename         = data.archive_file.api_zip.output_path
  function_name    = "cloudpress-api"
  role             = aws_iam_role.lambda_role.arn
  handler          = "app.handler"
  source_code_hash = data.archive_file.api_zip.output_base64sha256
  runtime          = "python3.10"
  timeout          = 30

  environment {
    variables = {
      TABLE_NAME   = aws_dynamodb_table.sites.name
      PROJECT_NAME = aws_codebuild_project.orchestrator.name
      STATE_BUCKET = aws_s3_bucket.terraform_state.bucket
    }
  }
}

# 5. API Gateway
resource "aws_apigatewayv2_api" "api" {
  name          = "cloudpress-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["*"]
    allow_headers = ["*"]
  }
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id           = aws_apigatewayv2_api.api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.api.invoke_arn
}

resource "aws_apigatewayv2_route" "routes" {
  for_each = toset([
    "GET /sites",
    "GET /sites/{site_id}",
    "POST /sites",
    "DELETE /sites/{site_id}",
    "POST /sites/{site_id}/reboot",
    "GET /sites/{site_id}/logs",
    "POST /sites/{site_id}/backup"
  ])

  api_id    = aws_apigatewayv2_api.api.id
  route_key = each.key
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.api.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.api.execution_arn}/*/*"
}

output "api_endpoint" {
  value = aws_apigatewayv2_api.api.api_endpoint
}

# Shared State Bucket for dynamically deployed sites
resource "aws_s3_bucket" "terraform_state" {
  bucket_prefix = "cloudpress-tf-state-"
}

output "terraform_state_bucket" {
  value = aws_s3_bucket.terraform_state.bucket
}

output "source_bucket" {
  value = aws_s3_bucket.orchestrator_source.bucket
}
# 6. Monitor Lambda
resource "aws_lambda_function" "monitor" {
  filename         = data.archive_file.api_zip.output_path
  function_name    = "cloudpress-monitor"
  role             = aws_iam_role.lambda_role.arn
  handler          = "monitor.handler"
  source_code_hash = data.archive_file.api_zip.output_base64sha256
  runtime          = "python3.10"
  timeout          = 300 # 5 minutes for monitoring loop

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.sites.name
    }
  }
}

# 7. EventBridge Schedule for Monitor
resource "aws_cloudwatch_event_rule" "monitor_schedule" {
  name                = "cloudpress-monitor-schedule"
  description         = "Trigger the cloudpress monitor lambda every hour"
  schedule_expression = "rate(1 hour)"
}

resource "aws_cloudwatch_event_target" "monitor_target" {
  rule      = aws_cloudwatch_event_rule.monitor_schedule.name
  target_id = "cloudpress_monitor"
  arn       = aws_lambda_function.monitor.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.monitor.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.monitor_schedule.arn
}
