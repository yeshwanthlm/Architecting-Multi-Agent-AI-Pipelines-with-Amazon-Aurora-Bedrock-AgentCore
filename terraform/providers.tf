terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.40.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.6.0"
    }
  }

  # Uncomment and configure this block to use a remote backend (recommended for production)
  # backend "s3" {
  #   bucket         = "<your-tfstate-bucket>"
  #   key            = "electrify/terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "<your-lock-table>"
  #   encrypt        = true
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "electrify"
      ManagedBy   = "Terraform"
    }
  }
}
