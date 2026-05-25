variable "environment" {
  description = "Deployment environment (staging or prod)"
  type        = string
}

variable "aws_region" {
  description = "AWS region to deploy resources into"
  type        = string
  default     = "us-east-1"
}

variable "alert_email" {
  description = "Email address to receive billing spend alerts"
  type        = string
}

variable "budget_limit_usd" {
  description = "Monthly spend limit in USD (~EUR equivalent) that triggers alerts"
  type        = string
}

variable "ci_iam_username" {
  description = "IAM username that CI uses to deploy (used to scope the deployment role trust policy)"
  type        = string
}
