output "ecr_repository_url" {
  value = aws_ecr_repository.triage.repository_url
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.soc.name
}

output "eventbridge_rule" {
  value = aws_cloudwatch_event_rule.threat_hunt.name
}

output "log_group" {
  value = aws_cloudwatch_log_group.triage.name
}

output "vpc_id" {
  value = aws_vpc.main.id
}
