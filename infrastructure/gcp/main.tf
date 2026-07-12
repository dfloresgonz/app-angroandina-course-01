terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }

  backend "gcs" {
    bucket = "angroandina-monitor-tfstate"
    prefix = "gcp"
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
  }
}
