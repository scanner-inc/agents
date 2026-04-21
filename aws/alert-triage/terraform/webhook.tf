###############################################################################
# API Gateway REST API — webhook ingestion for alert triage
#
# Scanner webhook → API Gateway (API key auth) → SQS → Lambda
#
# The webhook accepts POST /alerts with a JSON body containing alert_id and
# alert_summary. Requests must include a valid API key in the x-api-key header.
###############################################################################

###############################################################################
# IAM Role — allows API Gateway to send messages to SQS
###############################################################################
data "aws_iam_policy_document" "apigw_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["apigateway.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "apigw_sqs" {
  name               = "soc-triage-apigw-sqs"
  assume_role_policy = data.aws_iam_policy_document.apigw_assume.json
}

data "aws_iam_policy_document" "apigw_sqs" {
  statement {
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.alerts.arn]
  }
}

resource "aws_iam_role_policy" "apigw_sqs" {
  name   = "sqs-send"
  role   = aws_iam_role.apigw_sqs.id
  policy = data.aws_iam_policy_document.apigw_sqs.json
}

###############################################################################
# API Gateway REST API
###############################################################################
resource "aws_api_gateway_rest_api" "webhook" {
  name        = "soc-triage-webhook"
  description = "Webhook endpoint for SOC alert triage — forwards alerts to SQS"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

###############################################################################
# Resource: /alerts
###############################################################################
resource "aws_api_gateway_resource" "alerts" {
  rest_api_id = aws_api_gateway_rest_api.webhook.id
  parent_id   = aws_api_gateway_rest_api.webhook.root_resource_id
  path_part   = "alerts"
}

###############################################################################
# Method: POST /alerts (requires API key)
###############################################################################
resource "aws_api_gateway_method" "post_alerts" {
  rest_api_id      = aws_api_gateway_rest_api.webhook.id
  resource_id      = aws_api_gateway_resource.alerts.id
  http_method      = "POST"
  authorization    = "NONE"
  api_key_required = true
}

###############################################################################
# Integration: API Gateway → SQS (direct AWS service integration)
###############################################################################
data "aws_region" "current" {}

resource "aws_api_gateway_integration" "sqs" {
  rest_api_id             = aws_api_gateway_rest_api.webhook.id
  resource_id             = aws_api_gateway_resource.alerts.id
  http_method             = aws_api_gateway_method.post_alerts.http_method
  integration_http_method = "POST"
  type                    = "AWS"
  credentials             = aws_iam_role.apigw_sqs.arn
  uri                     = "arn:aws:apigateway:${data.aws_region.current.name}:sqs:path/${aws_sqs_queue.alerts.name}"

  # Transform the incoming JSON body into SQS SendMessage parameters.
  # The entire request body is forwarded as the SQS message body.
  request_parameters = {
    "integration.request.header.Content-Type" = "'application/x-www-form-urlencoded'"
  }

  request_templates = {
    "application/json" = "Action=SendMessage&MessageBody=$util.urlEncode($input.body)"
  }
}

###############################################################################
# Method Response + Integration Response (200 OK)
###############################################################################
resource "aws_api_gateway_method_response" "ok" {
  rest_api_id = aws_api_gateway_rest_api.webhook.id
  resource_id = aws_api_gateway_resource.alerts.id
  http_method = aws_api_gateway_method.post_alerts.http_method
  status_code = "200"

  response_models = {
    "application/json" = "Empty"
  }
}

resource "aws_api_gateway_integration_response" "ok" {
  rest_api_id = aws_api_gateway_rest_api.webhook.id
  resource_id = aws_api_gateway_resource.alerts.id
  http_method = aws_api_gateway_method.post_alerts.http_method
  status_code = aws_api_gateway_method_response.ok.status_code

  # Return a clean JSON response instead of raw SQS XML
  response_templates = {
    "application/json" = <<-EOF
      {
        "status": "accepted",
        "messageId": "$util.escapeJavaScript($input.path('$.SendMessageResponse.SendMessageResult.MessageId'))"
      }
    EOF
  }

  depends_on = [aws_api_gateway_integration.sqs]
}

###############################################################################
# Deployment + Stage
###############################################################################
resource "aws_api_gateway_deployment" "webhook" {
  rest_api_id = aws_api_gateway_rest_api.webhook.id

  # Redeploy when any of these resources change
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.alerts,
      aws_api_gateway_method.post_alerts,
      aws_api_gateway_integration.sqs,
      aws_api_gateway_method_response.ok,
      aws_api_gateway_integration_response.ok,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_api_gateway_integration.sqs,
    aws_api_gateway_integration_response.ok,
  ]
}

resource "aws_api_gateway_stage" "v1" {
  deployment_id = aws_api_gateway_deployment.webhook.id
  rest_api_id   = aws_api_gateway_rest_api.webhook.id
  stage_name    = "v1"
}

###############################################################################
# API Key + Usage Plan (webhook authentication)
###############################################################################
resource "aws_api_gateway_api_key" "webhook" {
  name    = "soc-triage-webhook-key"
  enabled = true

  # Use a caller-provided value if set, otherwise let AWS generate one
  value = var.webhook_api_key != "" ? var.webhook_api_key : null
}

resource "aws_api_gateway_usage_plan" "webhook" {
  name = "soc-triage-webhook"

  api_stages {
    api_id = aws_api_gateway_rest_api.webhook.id
    stage  = aws_api_gateway_stage.v1.stage_name
  }

  # Rate limiting to prevent abuse
  throttle_settings {
    burst_limit = 10
    rate_limit  = 5 # 5 requests per second
  }

  quota_settings {
    limit  = 10000
    period = "DAY"
  }
}

resource "aws_api_gateway_usage_plan_key" "webhook" {
  key_id        = aws_api_gateway_api_key.webhook.id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.webhook.id
}
