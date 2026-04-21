output "function_name" {
  value = aws_lambda_function.triage.function_name
}

output "function_arn" {
  value = aws_lambda_function.triage.arn
}

output "sqs_queue_url" {
  value = aws_sqs_queue.alerts.url
}

output "dlq_url" {
  value = aws_sqs_queue.dlq.url
}

output "log_group" {
  value = aws_cloudwatch_log_group.triage.name
}

output "ecr_repository_url" {
  value = aws_ecr_repository.triage.repository_url
}

output "webhook_url" {
  description = "POST alerts to this URL with x-api-key header"
  value       = "${aws_api_gateway_stage.v1.invoke_url}/alerts"
}

output "webhook_api_key" {
  description = "API key for webhook authentication (use in x-api-key header)"
  value       = aws_api_gateway_api_key.webhook.value
  sensitive   = true
}
