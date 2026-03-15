variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "demo"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "db_name" {
  type    = string
  default = "sentineliq"
}

variable "db_master_username" {
  type      = string
  default   = "sentinel_admin"
  sensitive = true
}

variable "db_master_password" {
  description = "Leave null to auto-generate"
  type        = string
  sensitive   = true
  default     = null
}

variable "bedrock_model_id" {
  type    = string
  default = "anthropic.claude-3-5-sonnet-20241022-v2:0"
}
