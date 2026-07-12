resource "google_pubsub_topic" "telemetry" {
  name   = "${var.project_name}-telemetry"
  labels = local.labels
}
