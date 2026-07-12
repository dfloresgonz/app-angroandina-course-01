data "aws_secretsmanager_secret" "gcp_sa_key" {
  name = "${var.project_name}/gcp-sa-key"
}
