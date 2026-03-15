##############################################################################
# Cognito — Customer User Pool
##############################################################################

resource "aws_cognito_user_pool" "customers" {
  name = "${local.suffix}-customers"

  username_configuration {
    case_sensitive = false
  }

  admin_create_user_config {
    allow_admin_create_user_only = false
  }

  auto_verified_attributes = ["email"]
  username_attributes      = ["email"]
  mfa_configuration        = "OFF"

  password_policy {
    minimum_length                   = 8
    require_uppercase                = true
    require_lowercase                = true
    require_numbers                  = true
    require_symbols                  = true
    temporary_password_validity_days = 1
  }

  schema {
    name     = "email"
    required = true
    mutable  = true
    attribute_data_type = "String"
  }

  schema {
    name     = "given_name"
    required = false
    mutable  = true
    attribute_data_type = "String"
  }

  schema {
    name     = "family_name"
    required = false
    mutable  = true
    attribute_data_type = "String"
  }

  tags = {
    Name = "${local.suffix}-customers"
  }
}

##############################################################################
# Cognito — Test User
##############################################################################

resource "aws_cognito_user" "test_user" {
  user_pool_id = aws_cognito_user_pool.customers.id
  username     = "rroe@example.com"

  attributes = {
    email          = "rroe@example.com"
    email_verified = "true"
  }

  force_alias_creation     = false
  message_action           = "SUPPRESS"
  desired_delivery_mediums = ["EMAIL"]
}

##############################################################################
# Cognito — User Pool Domain
##############################################################################

resource "aws_cognito_user_pool_domain" "customers" {
  domain       = "${local.suffix}-customers-domain-${local.account_id}"
  user_pool_id = aws_cognito_user_pool.customers.id
}

##############################################################################
# Cognito — Resource Servers (AgentCore)
##############################################################################

resource "aws_cognito_resource_server" "agentcore_gateway" {
  user_pool_id = aws_cognito_user_pool.customers.id
  identifier   = "gateway"
  name         = "AgentCore Gateway"

  scope {
    scope_name        = "invoke"
    scope_description = "Invoke AgentCore Gateway"
  }
}

resource "aws_cognito_resource_server" "agentcore_mcp_runtime" {
  user_pool_id = aws_cognito_user_pool.customers.id
  identifier   = "MCP_Runtime"
  name         = "AgentCore Runtime MCP"

  scope {
    scope_name        = "invoke"
    scope_description = "Invoke MCP Runtime"
  }
}

resource "aws_cognito_resource_server" "agentcore_agent_runtime" {
  user_pool_id = aws_cognito_user_pool.customers.id
  identifier   = "Agent_Runtime"
  name         = "AgentCore Runtime Agent"

  scope {
    scope_name        = "invoke"
    scope_description = "Invoke Agent Runtime"
  }
}

##############################################################################
# Cognito — User Pool Client
##############################################################################

resource "aws_cognito_user_pool_client" "customers" {
  name         = "${local.suffix}-customers-client"
  user_pool_id = aws_cognito_user_pool.customers.id

  generate_secret                      = false
  refresh_token_validity               = 30
  access_token_validity                = 60
  id_token_validity                    = 60
  prevent_user_existence_errors        = "ENABLED"
  allowed_oauth_flows_user_pool_client = true

  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }

  explicit_auth_flows = [
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_USER_PASSWORD_AUTH",
  ]

  callback_urls = ["https://${aws_cloudfront_distribution.website.domain_name}/"]
  logout_urls   = ["https://${aws_cloudfront_distribution.website.domain_name}/"]

  allowed_oauth_flows  = ["code"]
  allowed_oauth_scopes = [
    "email", "openid", "profile",
    "gateway/invoke", "MCP_Runtime/invoke", "Agent_Runtime/invoke"
  ]

  supported_identity_providers = ["COGNITO"]

  depends_on = [
    aws_cloudfront_distribution.website,
    aws_cognito_resource_server.agentcore_gateway,
    aws_cognito_resource_server.agentcore_mcp_runtime,
    aws_cognito_resource_server.agentcore_agent_runtime,
  ]
}

##############################################################################
# Cognito — Identity Pool
##############################################################################

resource "aws_cognito_identity_pool" "main" {
  identity_pool_name               = "${local.suffix}-idp"
  allow_unauthenticated_identities = false

  cognito_identity_providers {
    client_id     = aws_cognito_user_pool_client.customers.id
    provider_name = aws_cognito_user_pool.customers.endpoint
  }
}

##############################################################################
# Cognito — Identity Pool Role Attachments
##############################################################################

resource "aws_cognito_identity_pool_roles_attachment" "main" {
  identity_pool_id = aws_cognito_identity_pool.main.id

  roles = {
    authenticated   = aws_iam_role.idp_authenticated.arn
    unauthenticated = aws_iam_role.idp_unauthenticated.arn
  }
}
