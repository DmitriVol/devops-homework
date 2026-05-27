# Manage the log group explicitly so we can set retention.
# Without this, Lambda auto-creates it and logs accumulate indefinitely.
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${var.environment}-health-check-function"
  retention_in_days = var.log_retention_days

  tags = local.common_tags
}

resource "aws_lambda_function" "health_check" {
  function_name = "${var.environment}-health-check-function"
  role          = aws_iam_role.lambda_execution.arn

  s3_bucket    = var.lambda_s3_bucket
  s3_key       = var.lambda_s3_key
  description  = var.lambda_version
  publish      = true

  runtime                        = "python3.12"
  handler                        = "handler.lambda_handler"
  timeout                        = var.lambda_timeout
  reserved_concurrent_executions = var.lambda_concurrent_executions

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.requests.name
    }
  }

  depends_on = [aws_cloudwatch_log_group.lambda]

  tags = local.common_tags
}
