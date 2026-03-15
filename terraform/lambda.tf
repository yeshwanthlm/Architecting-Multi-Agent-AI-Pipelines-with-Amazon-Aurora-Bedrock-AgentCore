# ── IAM Role ─────────────────────────────────────────────
resource "aws_iam_role" "lambda_mcp" {
  name = "${local.name_prefix}-lambda-mcp-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "lambda_mcp" {
  name = "${local.name_prefix}-lambda-mcp-policy"
  role = aws_iam_role.lambda_mcp.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Secrets"
        Effect = "Allow"
        Action = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
        Resource = [aws_secretsmanager_secret.db_credentials.arn]
      },
      {
        Sid    = "VPC"
        Effect = "Allow"
        Action = [
          "ec2:CreateNetworkInterface", "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface", "ec2:AssignPrivateIpAddresses",
          "ec2:UnassignPrivateIpAddresses"
        ]
        Resource = ["*"]
      },
      {
        Sid    = "Logs"
        Effect = "Allow"
        Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = ["arn:aws:logs:*:*:*"]
      }
    ]
  })
}

# ── Package Lambda ────────────────────────────────────────
data "archive_file" "lambda_mcp" {
  type        = "zip"
  source_dir  = "${path.module}/../mcp_server"
  output_path = "${path.module}/../.build/mcp_server.zip"
  excludes    = ["requirements.txt", "__pycache__", "*.pyc", "*.dist-info"]
}

# ── Lambda Function ───────────────────────────────────────
resource "aws_lambda_function" "mcp_server" {
  function_name    = "${local.name_prefix}-mcp-server"
  description      = "MCP server - exposes Aurora tools to Strands agents"
  role             = aws_iam_role.lambda_mcp.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  timeout          = 300
  memory_size      = 1024
  filename         = data.archive_file.lambda_mcp.output_path
  source_code_hash = data.archive_file.lambda_mcp.output_base64sha256

  vpc_config {
    subnet_ids         = aws_subnet.private[*].id
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      DB_SECRET_ARN = aws_secretsmanager_secret.db_credentials.arn
      DB_NAME       = var.db_name
      REGION        = var.aws_region
      LOG_LEVEL     = "INFO"
    }
  }

  depends_on = [
    aws_iam_role_policy.lambda_mcp,
    aws_cloudwatch_log_group.lambda_mcp,
    aws_rds_cluster_instance.writer
  ]

  tags = { Name = "${local.name_prefix}-mcp-server" }
}

resource "aws_cloudwatch_log_group" "lambda_mcp" {
  name              = "/aws/lambda/${local.name_prefix}-mcp-server"
  retention_in_days = 7

  lifecycle {
    ignore_changes = [tags]
  }
}

# ── Function URL (for local Strands MCP client) ───────────
resource "aws_lambda_function_url" "mcp_server" {
  function_name      = aws_lambda_function.mcp_server.function_name
  authorization_type = "AWS_IAM"

  cors {
    allow_credentials = true
    allow_origins     = ["*"]
    allow_methods     = ["POST"]
    allow_headers     = ["content-type", "x-amz-security-token", "x-amz-date", "authorization"]
    max_age           = 86400
  }
}

# ── Lambda for Schema Bootstrap ──────────────────────────
data "archive_file" "lambda_bootstrap" {
  type        = "zip"
  source_dir  = "${path.module}/../scripts"
  output_path = "${path.module}/../.build/bootstrap.zip"
  excludes    = ["*.pyc", "__pycache__"]
}

resource "aws_lambda_function" "db_bootstrap" {
  function_name    = "${local.name_prefix}-db-bootstrap"
  description      = "One-time DB schema and seed data loader"
  role             = aws_iam_role.lambda_mcp.arn
  handler          = "bootstrap_handler.lambda_handler"
  runtime          = "python3.12"
  timeout          = 300
  memory_size      = 512
  filename         = data.archive_file.lambda_bootstrap.output_path
  source_code_hash = data.archive_file.lambda_bootstrap.output_base64sha256

  vpc_config {
    subnet_ids         = aws_subnet.private[*].id
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      DB_SECRET_ARN = aws_secretsmanager_secret.db_credentials.arn
      DB_NAME       = var.db_name
      REGION        = var.aws_region
    }
  }

  depends_on = [aws_rds_cluster_instance.writer]
}

# ── Invoke bootstrap after apply ─────────────────────────
resource "null_resource" "run_bootstrap" {
  triggers = {
    cluster_id = aws_rds_cluster.main.cluster_identifier
    lambda_arn = aws_lambda_function.db_bootstrap.arn
  }

  provisioner "local-exec" {
    command = <<-EOT
      aws lambda invoke \
        --function-name ${aws_lambda_function.db_bootstrap.function_name} \
        --region ${var.aws_region} \
        --payload '{}' \
        /tmp/bootstrap_response.json && \
      cat /tmp/bootstrap_response.json
    EOT
  }

  depends_on = [aws_lambda_function.db_bootstrap]
}
