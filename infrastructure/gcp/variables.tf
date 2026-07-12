variable "project_id" {
  type        = string
  description = "GCP project ID"
}

variable "project_name" {
  type    = string
  default = "angroandina-monitor"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "region" {
  type    = string
  default = "us-central1"
}
