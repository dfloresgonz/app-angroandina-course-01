terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.97.0"
    }
  }

  backend "s3" {
    bucket         = "angroandina-monitor-tfstate"
    key            = "aws/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "angroandina-tfstate-lock"
    encrypt        = true
  }
}

provider "aws" {
  region = "us-east-1"
}

data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  tags = {
    ProjectName = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}
