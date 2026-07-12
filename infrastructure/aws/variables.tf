variable "project_name" {
  type    = string
  default = "angroandina-monitor"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "kdg_username" {
  type = string
}

variable "kdg_password" {
  type      = string
  sensitive = true
}

variable "gcp_project_id" {
  type        = string
  description = "GCP project ID"
}

variable "gcp_pubsub_topic" {
  type        = string
  description = "Nombre del topic de Pub/Sub (output from GCP deploy)"
}
