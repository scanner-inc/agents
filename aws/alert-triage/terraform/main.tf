###############################################################################
# Secrets Manager — store API keys securely
###############################################################################
resource "aws_secretsmanager_secret" "anthropic_key" {
  name                    = "soc-triage/anthropic-api-key"
  recovery_window_in_days = 0 # Allow immediate deletion for dev
}

resource "aws_secretsmanager_secret_version" "anthropic_key" {
  secret_id     = aws_secretsmanager_secret.anthropic_key.id
  secret_string = var.anthropic_api_key
}

###############################################################################
# IAM Role for Lambda
###############################################################################
data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = "soc-triage-lambda"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "lambda_secrets" {
  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.anthropic_key.arn]
  }

  statement {
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
    ]
    resources = [aws_sqs_queue.alerts.arn]
  }
}

resource "aws_iam_role_policy" "lambda_secrets" {
  name   = "secrets-and-sqs"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda_secrets.json
}

###############################################################################
# CloudWatch Log Group
###############################################################################
resource "aws_cloudwatch_log_group" "triage" {
  name              = "/aws/lambda/soc-triage-agent"
  retention_in_days = 14
}

###############################################################################
# ECR Repository
###############################################################################
resource "aws_ecr_repository" "triage" {
  name                 = "soc-triage-lambda"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
}

###############################################################################
# Lambda Function (container image deployment)
###############################################################################
resource "aws_lambda_function" "triage" {
  function_name = "soc-triage-agent"
  role          = aws_iam_role.lambda.arn
  package_type  = "Image"
  image_uri     = "${aws_ecr_repository.triage.repository_url}:latest"
  timeout       = 900 # 15 minutes
  memory_size   = 1024

  environment {
    variables = {
      ANTHROPIC_API_KEY   = var.anthropic_api_key
      SCANNER_MCP_URL     = var.scanner_mcp_url
      SCANNER_MCP_API_KEY = var.scanner_mcp_api_key
      MODEL               = var.model
      SLACK_BOT_TOKEN     = var.slack_bot_token
      SLACK_TEAM_ID       = var.slack_team_id
      SLACK_CHANNEL_ID    = var.slack_channel_id
      SLACK_CHANNEL_NAME  = var.slack_channel_name
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic,
    aws_cloudwatch_log_group.triage,
  ]
}

###############################################################################
# SQS Queue + DLQ
###############################################################################
resource "aws_sqs_queue" "dlq" {
  name                      = "soc-triage-dlq"
  message_retention_seconds = 1209600 # 14 days
}

resource "aws_sqs_queue" "alerts" {
  name                       = "soc-triage-alerts"
  visibility_timeout_seconds = 960 # Slightly > Lambda timeout

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 2
  })
}

resource "aws_lambda_event_source_mapping" "sqs" {
  event_source_arn = aws_sqs_queue.alerts.arn
  function_name    = aws_lambda_function.triage.arn
  batch_size       = 1
  enabled          = true
}
