##############################################################################
# CloudWatch Log Group — API Access Logs
##############################################################################

resource "aws_cloudwatch_log_group" "api" {
  name              = "/aws/api/${local.suffix}"
  retention_in_days = 7

  tags = merge(local.common_tags, {
    Name = "/aws/api/${local.suffix}"
  })
}

##############################################################################
# API Gateway v2 — HTTP API
##############################################################################

resource "aws_apigatewayv2_api" "http" {
  name          = "${local.suffix}-api"
  protocol_type = "HTTP"
  description   = "Backend API for the electrify App"

  cors_configuration {
    allow_origins = ["https://*"]
    allow_headers = ["*"]
    allow_methods = ["GET", "POST", "OPTIONS"]
    max_age       = 600
  }

  tags = merge(local.common_tags, {
    Name = "${local.suffix}-api"
  })
}

##############################################################################
# API Gateway v2 — JWT Authorizer
##############################################################################

resource "aws_apigatewayv2_authorizer" "jwt" {
  api_id           = aws_apigatewayv2_api.http.id
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]
  name             = "${local.suffix}-api-jwt"

  jwt_configuration {
    audience = [aws_cognito_user_pool_client.customers.id]
    issuer   = "https://cognito-idp.${local.region}.amazonaws.com/${aws_cognito_user_pool.customers.id}"
  }
}

##############################################################################
# API Gateway v2 — Stage
##############################################################################

resource "aws_apigatewayv2_stage" "api" {
  api_id      = aws_apigatewayv2_api.http.id
  name        = "api"
  auto_deploy = true
  description = "Backend API Stage for the Electrify! app"

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api.arn
    format          = "$context.identity.sourceIp,$context.requestTime,$context.httpMethod,$context.path,$context.protocol,$context.status,$context.responseLength,$context.requestId,$context.integrationErrorMessage"
  }

  default_route_settings {
    throttling_burst_limit = 20
    throttling_rate_limit  = 100
  }

  tags = merge(local.common_tags, {
    Name = "${local.suffix}-api-stage"
  })
}

##############################################################################
# API Gateway v2 — Lambda Integration (Monolith)
##############################################################################

resource "aws_apigatewayv2_integration" "monolith" {
  api_id                 = aws_apigatewayv2_api.http.id
  integration_type       = "AWS_PROXY"
  integration_method     = "POST"
  integration_uri        = aws_lambda_function.api_monolith.arn
  connection_type        = "INTERNET"
  credentials_arn        = aws_iam_role.api_invoke_lambda.arn
  description            = "Retrieve the settings requested"
  payload_format_version = "2.0"
  timeout_milliseconds   = 30000
}

##############################################################################
# API Gateway v2 — Routes (all pointing to monolith integration)
##############################################################################

locals {
  api_routes = [
    "GET /providers",
    "GET /customers",
    "POST /customers",
    "GET /devices",
    "GET /metrics",
    "GET /billing",
    "GET /payments",
    "GET /invoice",
  ]
}

resource "aws_apigatewayv2_route" "monolith" {
  for_each = toset(local.api_routes)

  api_id             = aws_apigatewayv2_api.http.id
  route_key          = each.value
  api_key_required   = false
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.jwt.id
  target             = "integrations/${aws_apigatewayv2_integration.monolith.id}"
}
