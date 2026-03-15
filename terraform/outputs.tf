##############################################################################
# Outputs
##############################################################################

output "vpc_id" {
  description = "Aurora Lab VPC"
  value       = aws_vpc.main.id
}

output "cluster_name" {
  description = "Aurora Cluster Name"
  value       = aws_rds_cluster.main.cluster_identifier
}

output "cluster_endpoint" {
  description = "Aurora Cluster Endpoint"
  value       = aws_rds_cluster.main.endpoint
}

output "reader_endpoint" {
  description = "Aurora Reader Endpoint"
  value       = aws_rds_cluster.main.reader_endpoint
}

output "db_subnet_group" {
  description = "Database Subnet Group"
  value       = aws_db_subnet_group.main.name
}

output "db_security_group" {
  description = "Database Security Group"
  value       = aws_security_group.db_cluster.id
}

output "secret_arn" {
  description = "Database Credentials Secret ARN"
  value       = aws_secretsmanager_secret.cluster_admin.arn
}

output "s3_bucket_name" {
  description = "S3 Bucket Name for lab data"
  value       = aws_s3_bucket.lab_data.bucket
}

output "vscode_url" {
  description = "VSCode Server URL"
  value       = "https://${aws_cloudfront_distribution.vscode_ide.domain_name}/?folder=/home/${var.vscode_user}${var.home_folder}"
}

output "vscode_password" {
  description = "VSCode Server Password"
  value       = jsondecode(aws_secretsmanager_secret_version.vscode.secret_string)["password"]
  sensitive   = true
}

output "api_endpoint" {
  description = "Endpoint for the application API"
  value       = "${aws_apigatewayv2_api.http.id}.execute-api.${local.region}.amazonaws.com"
}

output "content_bucket" {
  description = "S3 bucket storing the website asset files, delivered through CloudFront"
  value       = aws_s3_bucket.website.bucket
}

output "application_url" {
  description = "Use this URL to access the web application"
  value       = "https://${aws_cloudfront_distribution.website.domain_name}/"
}

output "cognito_pool" {
  description = "Cognito user pool for end user authentication"
  value       = aws_cognito_user_pool.customers.id
}

output "cognito_client" {
  description = "Client application interacting with the Cognito user pool"
  value       = aws_cognito_user_pool_client.customers.id
}

output "cognito_domain" {
  description = "Domain for the Cognito user pool"
  value       = aws_cognito_user_pool_domain.customers.domain
}

output "cognito_identity_pool" {
  description = "Cognito identity provider to provide end user access to AWS services"
  value       = aws_cognito_identity_pool.main.id
}

output "data_bucket" {
  description = "S3 bucket for workshop data"
  value       = aws_s3_bucket.data.bucket
}

output "application_user_email" {
  description = "Pre-created test user email"
  value       = "rroe@example.com"
}

output "application_user_password" {
  description = "Pre-created test user password"
  value       = aws_secretsmanager_secret_version.cognito_test_user_password.secret_string
  sensitive   = true
}

output "agentcore_sdk_runtime_role_arn" {
  description = "Pre-created AgentCore SDK Runtime role ARN for use with agentcore deploy"
  value       = aws_iam_role.agentcore_sdk_runtime.arn
}
