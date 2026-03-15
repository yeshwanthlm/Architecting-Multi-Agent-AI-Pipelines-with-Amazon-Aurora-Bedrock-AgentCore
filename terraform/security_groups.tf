##############################################################################
# Client / Workstation Security Group
##############################################################################

resource "aws_security_group" "client" {
  name        = "electrify-workstation-sg-${local.region}-${local.suffix}"
  description = "Aurora lab workstation security group (firewall)"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Allow HTTP from CloudFront origin-facing prefix list"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    prefix_list_ids = [local.prefix_list]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "electrify-workstation-sg-${local.region}-${local.suffix}"
  })
}

##############################################################################
# DB Cluster Security Group
##############################################################################

resource "aws_security_group" "db_cluster" {
  name        = "electrify-database-sg-${local.region}-${local.suffix}"
  description = "Aurora lab database security group (firewall)"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Allows postgres access from the workstation security group"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.client.id]
  }

  tags = merge(local.common_tags, {
    Name = "electrify-database-sg-${local.region}-${local.suffix}"
  })
}

# Self-referencing ingress rule (allows all inbound from same SG)
resource "aws_security_group_rule" "db_cluster_self_ingress" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  description              = "Allows all inbound access from sources with the same security group"
  security_group_id        = aws_security_group.db_cluster.id
  source_security_group_id = aws_security_group.db_cluster.id
}
