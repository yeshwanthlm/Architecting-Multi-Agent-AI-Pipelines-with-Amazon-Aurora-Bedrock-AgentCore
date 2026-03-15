##############################################################################
# Secrets Manager — Aurora Cluster Admin Credentials
##############################################################################

resource "aws_secretsmanager_secret" "cluster_admin" {
  name        = "electrify-cluster-secret-${local.region}-${local.suffix}"
  description = "Administrator user credentials for DB cluster 'electrify-postgres-cluster'"

  tags = merge(local.common_tags, {
    Name = "electrify-cluster-secret-${local.region}-${local.suffix}"
  })
}

resource "aws_secretsmanager_secret_version" "cluster_admin" {
  secret_id = aws_secretsmanager_secret.cluster_admin.id

  secret_string = jsonencode({
    username = "administrator"
    password = random_password.cluster_admin.result
  })
}

resource "random_password" "cluster_admin" {
  length           = 10
  special          = true
  override_special = "!#%^*_-+[]{}|"
}

##############################################################################
# Secrets Manager — VSCode Server Password
##############################################################################

resource "aws_secretsmanager_secret" "vscode" {
  name        = "electrify-VSCode-secret-${local.region}-${local.suffix}"
  description = "VS code-server user details"

  tags = merge(local.common_tags, {
    Name = "electrify-VSCode-secret-${local.region}-${local.suffix}"
  })
}

resource "aws_secretsmanager_secret_version" "vscode" {
  secret_id = aws_secretsmanager_secret.vscode.id

  secret_string = jsonencode({
    username = var.vscode_user
    password = random_password.vscode.result
  })
}

resource "random_password" "vscode" {
  length      = 16
  special     = false
}

##############################################################################
# Secrets Manager — Cognito Test User Password
##############################################################################

resource "aws_secretsmanager_secret" "cognito_test_user_password" {
  name        = "${local.suffix}-test-user-password"
  description = "Password for test user rroe@example.com"

  tags = merge(local.common_tags, {
    Name = "${local.suffix}-test-user-password"
  })
}

resource "aws_secretsmanager_secret_version" "cognito_test_user_password" {
  secret_id     = aws_secretsmanager_secret.cognito_test_user_password.id
  secret_string = random_password.cognito_test_user.result
}

resource "random_password" "cognito_test_user" {
  length           = 12
  special          = true
  override_special = "!#%^*_-+[]{}|"
  min_upper        = 1
  min_lower        = 1
  min_numeric      = 1
  min_special      = 1
}
