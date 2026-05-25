output "invoke_url" {
  description = "Base URL of the deployed API Gateway endpoint"
  value       = aws_apigatewayv2_stage.default.invoke_url
}

output "health_endpoint" {
  description = "Full URL of the /health endpoint"
  value       = "${trimsuffix(aws_apigatewayv2_stage.default.invoke_url, "/")}/health"
}
