data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

# Resolve latest Amazon Linux 2023 AMI via SSM Parameter Store
data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

locals {
  # Unique suffix derived from a random_id (simulates CloudFormation StackId-based suffix)
  suffix     = random_id.stack_suffix.hex
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name
  partition  = data.aws_partition.current.partition

  # Regional settings map
  regional_settings = {
    "us-east-1" = { ide_type = "m5.large", node_type = "db.serverless", az1 = "us-east-1a", az2 = "us-east-1b", az3 = "us-east-1c", prefix_list = "pl-3b927c52" }
    "us-east-2" = { ide_type = "m5.large", node_type = "db.serverless", az1 = "us-east-2c", az2 = "us-east-2a", az3 = "us-east-2b", prefix_list = "pl-b6a144df" }
    "us-west-2" = { ide_type = "m5.large", node_type = "db.serverless", az1 = "us-west-2b", az2 = "us-west-2c", az3 = "us-west-2d", prefix_list = "pl-82a045eb" }
    "ca-central-1" = { ide_type = "m5.large", node_type = "db.serverless", az1 = "ca-central-1c", az2 = "ca-central-1a", az3 = "ca-central-1b", prefix_list = "pl-38a64351" }
    "eu-central-1" = { ide_type = "m5.large", node_type = "db.serverless", az1 = "eu-central-1b", az2 = "eu-central-1a", az3 = "eu-central-1c", prefix_list = "pl-a3a144ca" }
    "eu-west-1"    = { ide_type = "m5.large", node_type = "db.serverless", az1 = "eu-west-1a",    az2 = "eu-west-1b",    az3 = "eu-west-1c",    prefix_list = "pl-4fa04526" }
    "eu-west-2"    = { ide_type = "m5.large", node_type = "db.serverless", az1 = "eu-west-2b",    az2 = "eu-west-2a",    az3 = "eu-west-2c",    prefix_list = "pl-93a247fa" }
    "ap-southeast-1" = { ide_type = "m5.large", node_type = "db.serverless", az1 = "ap-southeast-1c", az2 = "ap-southeast-1b", az3 = "ap-southeast-1a", prefix_list = "pl-31a34658" }
    "ap-southeast-2" = { ide_type = "m5.large", node_type = "db.serverless", az1 = "ap-southeast-2a", az2 = "ap-southeast-2b", az3 = "ap-southeast-2c", prefix_list = "pl-b8a742d1" }
    "ap-south-1"     = { ide_type = "m5.large", node_type = "db.serverless", az1 = "ap-south-1a",     az2 = "ap-south-1b",     az3 = "ap-south-1c",     prefix_list = "pl-9aa247f3" }
    "ap-northeast-1" = { ide_type = "m5.large", node_type = "db.serverless", az1 = "ap-northeast-1d", az2 = "ap-northeast-1a", az3 = "ap-northeast-1c", prefix_list = "pl-58a04531" }
    "ap-northeast-2" = { ide_type = "m5.large", node_type = "db.serverless", az1 = "ap-northeast-2a", az2 = "ap-northeast-2b", az3 = "ap-northeast-2c", prefix_list = "pl-22a6434b" }
  }

  # Resolved settings for current region
  ide_type    = local.regional_settings[local.region].ide_type
  node_type   = local.regional_settings[local.region].node_type
  az1         = local.regional_settings[local.region].az1
  az2         = local.regional_settings[local.region].az2
  az3         = local.regional_settings[local.region].az3
  prefix_list = local.regional_settings[local.region].prefix_list

  # Network CIDR settings
  vpc_cidr      = "172.30.0.0/16"
  sub_pub1_cidr = "172.30.0.0/24"
  sub_pub2_cidr = "172.30.1.0/24"
  sub_pub3_cidr = "172.30.2.0/24"
  sub_prv1_cidr = "172.30.10.0/24"
  sub_prv2_cidr = "172.30.11.0/24"
  sub_prv3_cidr = "172.30.12.0/24"

  # Aurora cluster settings
  db_schema  = "electrify"
  db_version = "17.5"
  db_engine  = "aurora-postgresql"
  db_family  = "aurora-postgresql17"
  db_port    = 5432

  # Common tags applied to all resources
  common_tags = {
    Project = "electrify"
    Region  = local.region
    Suffix  = local.suffix
  }
}

# Random suffix simulating CloudFormation StackId-based unique ID
resource "random_id" "stack_suffix" {
  byte_length = 4
}
