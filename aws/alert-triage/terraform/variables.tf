variable "aws_region" {
  default = "us-west-2"
}

variable "aws_profile" {
  type = string
}

variable "anthropic_api_key" {
  type      = string
  sensitive = true
}

variable "scanner_mcp_url" {
  type    = string
  default = ""
}

variable "scanner_mcp_api_key" {
  type      = string
  sensitive = true
  default   = ""
}

variable "model" {
  type    = string
  default = "claude-opus-4-6"
}

variable "slack_bot_token" {
  type      = string
  sensitive = true
  default   = ""
}

variable "slack_team_id" {
  type    = string
  default = ""
}

variable "slack_channel_id" {
  type    = string
  default = ""
}

variable "slack_channel_name" {
  type    = string
  default = ""
}

variable "webhook_api_key" {
  description = "API key for webhook authentication. If empty, AWS generates one automatically."
  type        = string
  sensitive   = true
  default     = ""
}
