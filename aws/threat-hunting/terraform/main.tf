###############################################################################
# Secrets Manager
###############################################################################
resource "aws_secretsmanager_secret" "agent_secrets" {
  name                    = "soc-triage-agent/secrets"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "agent_secrets" {
  secret_id = aws_secretsmanager_secret.agent_secrets.id
  secret_string = jsonencode({
    ANTHROPIC_API_KEY   = var.anthropic_api_key
    SCANNER_MCP_API_KEY = var.scanner_mcp_api_key
    SLACK_BOT_TOKEN     = var.slack_bot_token
    ABUSECH_AUTH_KEY    = var.abusech_auth_key
    OTX_API_KEY         = var.otx_api_key
  })
}

###############################################################################
# ECR Repository
###############################################################################
resource "aws_ecr_repository" "triage" {
  name                 = "triage-agent"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
}

###############################################################################
# CloudWatch Log Group
###############################################################################
resource "aws_cloudwatch_log_group" "triage" {
  name              = "/ecs/triage-agent"
  retention_in_days = 14
}

###############################################################################
# IAM Roles
###############################################################################

# Execution role (ECS agent uses this to pull image + read secrets)
data "aws_iam_policy_document" "ecs_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "execution" {
  name               = "soc-triage-ecs-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
}

resource "aws_iam_role_policy_attachment" "execution_basic" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "execution_secrets" {
  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.agent_secrets.arn]
  }
}

resource "aws_iam_role_policy" "execution_secrets" {
  name   = "read-secrets"
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.execution_secrets.json
}

# Task role (the container itself uses this)
resource "aws_iam_role" "task" {
  name               = "soc-triage-ecs-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
}

data "aws_iam_policy_document" "task_logs" {
  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["${aws_cloudwatch_log_group.triage.arn}:*"]
  }
}

resource "aws_iam_role_policy" "task_logs" {
  name   = "write-logs"
  role   = aws_iam_role.task.id
  policy = data.aws_iam_policy_document.task_logs.json
}

###############################################################################
# ECS Cluster + Task Definition + Service
###############################################################################
resource "aws_ecs_cluster" "soc" {
  name = "soc-agents"
}

resource "aws_ecs_task_definition" "triage" {
  family                   = "triage-agent"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([
    {
      name      = "triage-agent"
      image     = "${aws_ecr_repository.triage.repository_url}:latest"
      essential = true

      secrets = [
        {
          name      = "ANTHROPIC_API_KEY"
          valueFrom = "${aws_secretsmanager_secret.agent_secrets.arn}:ANTHROPIC_API_KEY::"
        },
        {
          name      = "SCANNER_MCP_API_KEY"
          valueFrom = "${aws_secretsmanager_secret.agent_secrets.arn}:SCANNER_MCP_API_KEY::"
        },
        {
          name      = "SLACK_BOT_TOKEN"
          valueFrom = "${aws_secretsmanager_secret.agent_secrets.arn}:SLACK_BOT_TOKEN::"
        },
        {
          name      = "ABUSECH_AUTH_KEY"
          valueFrom = "${aws_secretsmanager_secret.agent_secrets.arn}:ABUSECH_AUTH_KEY::"
        },
        {
          name      = "OTX_API_KEY"
          valueFrom = "${aws_secretsmanager_secret.agent_secrets.arn}:OTX_API_KEY::"
        },
      ]

      environment = [
        { name = "SCANNER_MCP_URL", value = var.scanner_mcp_url },
        { name = "MODEL", value = var.model },
        { name = "HOME", value = "/home/agent" },
        { name = "SLACK_TEAM_ID", value = var.slack_team_id },
        { name = "SLACK_CHANNEL_NAME", value = var.slack_channel_name },
        { name = "SLACK_CHANNEL_ID", value = var.slack_channel_id },
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.triage.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "triage"
        }
      }
    }
  ])
}

###############################################################################
# EventBridge — schedule the agent to run periodically
###############################################################################
data "aws_iam_policy_document" "eventbridge_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eventbridge" {
  name               = "soc-triage-eventbridge"
  assume_role_policy = data.aws_iam_policy_document.eventbridge_assume.json
}

data "aws_iam_policy_document" "eventbridge_run_task" {
  statement {
    actions   = ["ecs:RunTask"]
    resources = [aws_ecs_task_definition.triage.arn]
  }

  statement {
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.execution.arn, aws_iam_role.task.arn]
  }
}

resource "aws_iam_role_policy" "eventbridge_run_task" {
  name   = "run-ecs-task"
  role   = aws_iam_role.eventbridge.id
  policy = data.aws_iam_policy_document.eventbridge_run_task.json
}

resource "aws_cloudwatch_event_rule" "threat_hunt" {
  name                = "soc-threat-hunt-schedule"
  schedule_expression = "rate(6 hours)"
}

resource "aws_cloudwatch_event_target" "threat_hunt" {
  rule     = aws_cloudwatch_event_rule.threat_hunt.name
  arn      = aws_ecs_cluster.soc.arn
  role_arn = aws_iam_role.eventbridge.arn

  ecs_target {
    task_definition_arn = aws_ecs_task_definition.triage.arn
    task_count          = 1
    launch_type         = "FARGATE"

    network_configuration {
      subnets         = aws_subnet.private[*].id
      security_groups = [aws_security_group.agent.id]
    }
  }
}
