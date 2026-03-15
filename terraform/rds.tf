##############################################################################
# RDS — DB Subnet Group
##############################################################################

resource "aws_db_subnet_group" "main" {
  name        = "electrify-db-subnet-group-${local.region}-${local.suffix}"
  description = "Aurora Lab subnets allowed for deploying DB instances"
  subnet_ids  = [aws_subnet.private_1.id, aws_subnet.private_2.id, aws_subnet.private_3.id]

  tags = merge(local.common_tags, {
    Name = "electrify-db-subnet-group-${local.region}-${local.suffix}"
  })
}

##############################################################################
# RDS — Cluster Parameter Group
##############################################################################

resource "aws_rds_cluster_parameter_group" "main" {
  name        = "electrify-postgres-cluster-params-${local.region}-${local.suffix}"
  family      = local.db_family
  description = "electrify-postgres-cluster-params-${local.region}-${local.suffix}"

  parameter {
    name  = "rds.force_ssl"
    value = "0"
  }

  tags = merge(local.common_tags, {
    Name = "electrify-postgres-cluster-params-${local.region}-${local.suffix}"
  })
}

##############################################################################
# RDS — Aurora PostgreSQL Serverless v2 Cluster
##############################################################################

resource "aws_rds_cluster" "main" {
  cluster_identifier              = "electrify-postgres-cluster-${local.region}-${local.suffix}"
  engine                          = local.db_engine
  engine_version                  = local.db_version
  port                            = local.db_port
  db_subnet_group_name            = aws_db_subnet_group.main.name
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.main.name
  vpc_security_group_ids          = [aws_security_group.db_cluster.id]
  backup_retention_period         = 1
  master_username                 = jsondecode(aws_secretsmanager_secret_version.cluster_admin.secret_string)["username"]
  master_password                 = jsondecode(aws_secretsmanager_secret_version.cluster_admin.secret_string)["password"]
  storage_encrypted               = true
  enable_http_endpoint            = true
  iam_database_authentication_enabled = true
  skip_final_snapshot             = true
  deletion_protection             = false

  serverlessv2_scaling_configuration {
    min_capacity = 0.5
    max_capacity = 128
  }

  tags = merge(local.common_tags, {
    Name = "electrify-postgres-cluster-${local.region}-${local.suffix}"
  })

  depends_on = [aws_secretsmanager_secret_version.cluster_admin]
}

# Associate S3 import role with the cluster
resource "aws_rds_cluster_role_association" "s3_import" {
  db_cluster_identifier = aws_rds_cluster.main.id
  feature_name          = "s3Import"
  role_arn              = aws_iam_role.service_integration.arn
}

##############################################################################
# RDS — Cluster Instance (Node 1 — Serverless v2)
##############################################################################

resource "aws_rds_cluster_instance" "node_1" {
  identifier              = "electrify-postgres-node-1-${local.region}-${local.suffix}"
  cluster_identifier      = aws_rds_cluster.main.id
  engine                  = local.db_engine
  instance_class          = local.node_type
  copy_tags_to_snapshot   = true
  publicly_accessible     = false
  monitoring_interval     = 1
  monitoring_role_arn     = aws_iam_role.enhanced_monitoring.arn
  performance_insights_enabled          = true
  performance_insights_retention_period = 7

  tags = merge(local.common_tags, {
    Name = "electrify-postgres-node-1-${local.region}-${local.suffix}"
  })
}
