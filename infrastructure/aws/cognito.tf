resource "aws_cloudformation_stack" "kdg_cognito" {
  name         = "${var.project_name}-kdg-cognito"
  template_url = "https://aws-kdg-tools.s3.us-west-2.amazonaws.com/cognito-setup.yaml"
  capabilities = ["CAPABILITY_IAM", "CAPABILITY_NAMED_IAM", "CAPABILITY_AUTO_EXPAND"]
  tags         = local.tags

  parameters = {
    Username = var.kdg_username
    Password = var.kdg_password
  }
}

# ─── Cognito: Dashboard users ─────────────────────────────────────────────────

resource "aws_cognito_user_pool" "dashboard" {
  name = "${var.project_name}-dashboard-users"

  password_policy {
    minimum_length                   = 8
    require_lowercase                = true
    require_uppercase                = true
    require_numbers                  = true
    require_symbols                  = false
    temporary_password_validity_days = 7
  }

  auto_verified_attributes = ["email"]

  schema {
    name                = "email"
    attribute_data_type = "String"
    required            = true
    mutable             = true
  }

  tags = local.tags
}

resource "aws_cognito_user_pool_client" "dashboard" {
  name         = "${var.project_name}-dashboard-client"
  user_pool_id = aws_cognito_user_pool.dashboard.id

  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH"
  ]

  # tokens nunca se guardan en cookies → evitar CSRF
  prevent_user_existence_errors = "ENABLED"
}
