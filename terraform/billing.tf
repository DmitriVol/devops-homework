# Monthly cost budget — alerts at 80 % (early warning) and 100 % (limit reached).
# AWS Budgets bills in USD; $11 ≈ €10 at typical exchange rates.
# This resource is account-scoped, not per-service, so it catches any unexpected spend.
resource "aws_budgets_budget" "spend_alert" {
  name         = "${var.environment}-spend-alert"
  budget_type  = "COST"
  limit_amount = var.budget_limit_usd
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
  }
}
