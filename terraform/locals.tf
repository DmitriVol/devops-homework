locals {
  common_tags = {
    Environment = var.environment
    Project     = "devops-homework"
    ManagedBy   = "terraform"
  }
}
