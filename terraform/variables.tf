variable "environment" {
  description = "Deployment environment (staging or prod)"
  type        = string

  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment must be 'staging' or 'prod'."
  }
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
  type        = number
}

variable "github_repo" {
  description = "GitHub repository in owner/repo format (used to scope the OIDC trust policy)"
  type        = string
}

variable "create_oidc_provider" {
  description = "Create the GitHub Actions OIDC provider (account-level, true for staging only)"
  type        = bool
  default     = false
}

variable "lambda_concurrent_executions" {
  description = "Reserved concurrent executions for the Lambda function (controls max parallelism)"
  type        = number
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

variable "lambda_s3_bucket" {
  description = "S3 bucket containing the Lambda deployment package"
  type        = string
}

variable "lambda_s3_key" {
  description = "S3 object key of the Lambda deployment package; set by CI on each deploy"
  type        = string
}

variable "lambda_version" {
  description = "Human-readable version label (run<N>-<sha>) recorded as the Lambda function description"
  type        = string
  default     = "local"
}
