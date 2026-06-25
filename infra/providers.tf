terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }


  # backend "s3" {
  #   bucket = "SEU-BUCKET-tfstate"
  #   key    = "crypto-pipeline/terraform.tfstate"
  #   region = "us-east-1"
  # }
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile # usa o profile SSO configurado via `aws configure sso`

  default_tags {
    tags = {
      Project     = "crypto-pipeline"
      ManagedBy   = "terraform"
      Environment = var.environment
    }
  }
}
