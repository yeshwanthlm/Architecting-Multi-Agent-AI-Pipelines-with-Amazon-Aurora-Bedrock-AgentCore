# ── Password ──────────────────────────────────────────────
resource "random_password" "db_master" {
  length           = 24
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

locals {
  db_password = var.db_master_password != null ? var.db_master_password : random_password.db_master.result
}

# ── Secrets Manager ───────────────────────────────────────
# name_prefix ensures no collision on re-deploy after destroy
resource "aws_secretsmanager_secret" "db_credentials" {
  name                    = "${local.name_prefix}/aurora/credentials-${random_id.suffix.hex}"
  description             = "SentinelIQ Aurora credentials"
  recovery_window_in_days = 0
  tags                    = { Name = "${local.name_prefix}-db-secret" }
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username = var.db_master_username
    password = local.db_password
    engine   = "postgres"
    host     = aws_rds_cluster.main.endpoint
    port     = 5432
    dbname   = var.db_name
  })
}

# ── Subnet Group ─────────────────────────────────────────
resource "aws_db_subnet_group" "main" {
  name       = "${local.name_prefix}-db-subnet-group-${random_id.suffix.hex}"
  subnet_ids = aws_subnet.private[*].id
  tags       = { Name = "${local.name_prefix}-db-subnet-group" }

  lifecycle {
    create_before_destroy = true
  }
}

# ── Parameter Group ───────────────────────────────────────
resource "aws_rds_cluster_parameter_group" "main" {
  name   = "${local.name_prefix}-cluster-pg"
  family = "aurora-postgresql15"

  parameter {
    name  = "log_statement"
    value = "ddl"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "2000"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ── Aurora Serverless v2 Cluster ──────────────────────────
resource "aws_rds_cluster" "main" {
  cluster_identifier     = "${local.name_prefix}-cluster"
  engine                 = "aurora-postgresql"
  engine_mode            = "provisioned"
  engine_version         = "15.8"
  database_name          = var.db_name
  master_username        = var.db_master_username
  master_password        = local.db_password
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.aurora.id]

  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.main.name

  serverlessv2_scaling_configuration {
    min_capacity = 0.5
    max_capacity = 8.0
  }

  backup_retention_period         = 1
  skip_final_snapshot             = true
  deletion_protection             = false
  enabled_cloudwatch_logs_exports = ["postgresql"]

  tags = { Name = "${local.name_prefix}-aurora" }
}

# ── Writer Instance ───────────────────────────────────────
resource "aws_rds_cluster_instance" "writer" {
  cluster_identifier   = aws_rds_cluster.main.id
  identifier           = "${local.name_prefix}-writer"
  instance_class       = "db.serverless"
  engine               = aws_rds_cluster.main.engine
  engine_version       = aws_rds_cluster.main.engine_version
  db_subnet_group_name = aws_db_subnet_group.main.name
  monitoring_interval  = 60
  monitoring_role_arn  = aws_iam_role.rds_monitoring.arn
  tags                 = { Name = "${local.name_prefix}-writer" }
}

# ── RDS Enhanced Monitoring Role ──────────────────────────
resource "aws_iam_role" "rds_monitoring" {
  name = "${local.name_prefix}-rds-monitoring"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "monitoring.rds.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}
