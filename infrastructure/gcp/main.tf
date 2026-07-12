terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }

  backend "gcs" {
    bucket = "angroandina-monitor-tfstate-dev"
    prefix = "dev"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

locals {
  labels = {
    project_name = var.project_name
    environment  = var.environment
    managed_by   = "terraform"
    owner        = "grupo1-prog-multinube"
  }
}
