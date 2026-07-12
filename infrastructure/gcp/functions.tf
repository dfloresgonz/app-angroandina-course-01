resource "google_storage_bucket" "function_source" {
  name                        = "${var.project_name}-function-source-${var.project_id}"
  location                    = "US"
  force_destroy               = true
  uniform_bucket_level_access = true
  labels                      = local.labels
}

data "archive_file" "telemetry_ingest_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../../gcp-functions/telemetry-ingest"
  output_path = "/tmp/telemetry-ingest.zip"
}

resource "google_storage_bucket_object" "telemetry_ingest_source" {
  name   = "telemetry-ingest-${filemd5("${path.module}/../../gcp-functions/telemetry-ingest/index.js")}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.telemetry_ingest_zip.output_path
}

resource "google_cloudfunctions2_function" "telemetry_ingest" {
  name        = "${var.project_name}-telemetry-ingest"
  description = "Receives Pub/Sub push and writes to BigQuery"
  location    = var.region
  labels      = local.labels

  build_config {
    runtime     = "nodejs22"
    entry_point = "ingestTelemetry"

    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.telemetry_ingest_source.name
      }
    }
  }

  service_config {
    available_memory   = "256M"
    timeout_seconds    = 60
    min_instance_count = 0
    max_instance_count = 5

    environment_variables = {
      PROJECT_ID       = var.project_id
      BIGQUERY_DATASET = google_bigquery_dataset.main.dataset_id
      BIGQUERY_TABLE   = google_bigquery_table.telemetry.table_id
    }
  }
}

# Solo el SA de Pub/Sub puede invocar la función
resource "google_cloud_run_service_iam_member" "pubsub_invoker" {
  project  = var.project_id
  location = var.region
  service  = google_cloudfunctions2_function.telemetry_ingest.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.pubsub_invoker.email}"
}
