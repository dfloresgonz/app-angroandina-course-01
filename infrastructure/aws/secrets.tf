resource "aws_secretsmanager_secret" "gcp_sa_key" {
  name                    = "${var.project_name}/gcp-sa-key"
  description             = "GCP Service Account JSON key para publicar en Pub/Sub"
  recovery_window_in_days = 0
  tags                    = local.tags
}
