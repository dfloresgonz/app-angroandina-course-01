resource "google_pubsub_topic" "telemetry" {
  name   = "${var.project_name}-telemetry"
  labels = local.labels
}

resource "google_pubsub_subscription" "telemetry_sub" {
  name   = "${var.project_name}-telemetry-sub"
  topic  = google_pubsub_topic.telemetry.name
  labels = local.labels

  push_config {
    push_endpoint = google_cloudfunctions_function.telemetry_ingest.https_trigger_url

    oidc_token {
      service_account_email = google_service_account.function_invoker.email
    }
  }

  ack_deadline_seconds = 20

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }
}

resource "google_service_account" "function_invoker" {
  account_id   = "${var.project_name}-invoker"
  display_name = "Pub/Sub → Cloud Function invoker"
}

resource "google_cloudfunctions_function_iam_member" "invoker" {
  project        = var.project_id
  region         = var.region
  cloud_function = google_cloudfunctions_function.telemetry_ingest.name
  role           = "roles/cloudfunctions.invoker"
  member         = "serviceAccount:${google_service_account.function_invoker.email}"
}
