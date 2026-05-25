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

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 30
}

variable "log_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
}

variable "api_throttle_rate" {
  description = "API Gateway steady-state request rate limit (requests per second)"
  type        = number
}

variable "api_throttle_burst" {
  description = "API Gateway burst request limit"
  type        = number
}
