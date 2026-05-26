resource "aws_apigatewayv2_api" "health_check" {
  name          = "${var.environment}-health-check-api"
  protocol_type = "HTTP"

  tags = local.common_tags
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.health_check.id
  name        = "$default"
  auto_deploy = true

  default_route_settings {
    throttling_rate_limit  = var.api_throttle_rate
    throttling_burst_limit = var.api_throttle_burst
  }

  tags = local.common_tags
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.health_check.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.health_check.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "get_health" {
  api_id             = aws_apigatewayv2_api.health_check.id
  route_key          = "GET /health"
  target             = "integrations/${aws_apigatewayv2_integration.lambda.id}"
  authorization_type = "NONE"
}

resource "aws_apigatewayv2_route" "post_health" {
  api_id             = aws_apigatewayv2_api.health_check.id
  route_key          = "POST /health"
  target             = "integrations/${aws_apigatewayv2_integration.lambda.id}"
  authorization_type = "NONE"
}

resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.health_check.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.health_check.execution_arn}/*/*/health"
}
