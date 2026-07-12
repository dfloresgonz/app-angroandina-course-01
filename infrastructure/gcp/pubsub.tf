resource "google_pubsub_topic" "telemetry" {
  name   = "${var.project_name}-telemetry"
  labels = local.labels
}

resource "google_pubsub_subscription" "telemetry_push" {
  name  = "${var.project_name}-telemetry-push"
  topic = google_pubsub_topic.telemetry.name

  push_config {
    push_endpoint = google_cloudfunctions2_function.telemetry_ingest.service_config[0].uri

    oidc_token {
      service_account_email = google_service_account.pubsub_invoker.email
    }
  }

  ack_deadline_seconds       = 60
  message_retention_duration = "600s"

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "60s"
  }

  labels = local.labels
}
