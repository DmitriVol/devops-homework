# The GitHub Actions OIDC provider is an account-level resource — it only needs
# to exist once. We create it when applying staging (create_oidc_provider = true)
# and skip creation for prod (the provider already exists by then).
# In both cases the ARN is available via the local below.

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 1 : 0

  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]

  # AWS validates GitHub tokens against GitHub's root CA (since Oct 2023),
  # so the thumbprint is no longer used for cryptographic verification —
  # but Terraform still requires a non-empty list.
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]

  tags = local.common_tags
}

locals {
  # Resolve the provider ARN regardless of which environment is being applied.
  github_oidc_provider_arn = var.create_oidc_provider ? (
    aws_iam_openid_connect_provider.github[0].arn
  ) : "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com"

  # The `sub` claim GitHub includes in the OIDC token differs by workflow trigger
  # and whether the job uses a GitHub Environment.
  #   staging plan job  — no environment, push to main → branch-scoped sub
  #   staging apply job — uses `environment: staging`  → environment-scoped sub
  #   prod    apply job — uses `environment: prod`      → environment-scoped sub
  # IAM StringLike accepts a list; any matching element grants access.
  github_oidc_sub = var.environment == "staging" ? tolist([
    "repo:${var.github_repo}:ref:refs/heads/main",
    "repo:${var.github_repo}:environment:staging"
  ]) : tolist([
    "repo:${var.github_repo}:environment:prod"
  ])
}
