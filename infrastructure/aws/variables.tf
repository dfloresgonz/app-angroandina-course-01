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

variable "gcp_forwarder_url" {
  type        = string
  description = "GCP Pub/Sub HTTP endpoint (output from GCP deploy)"
}
