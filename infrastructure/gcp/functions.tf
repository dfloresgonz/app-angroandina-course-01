resource "google_storage_bucket" "function_source" {
  name                        = "${var.project_name}-function-source-${var.project_id}"
  location                    = "US"
  force_destroy               = true
  uniform_bucket_level_access = true
  labels                      = local.labels
}

resource "google_storage_bucket_object" "telemetry_ingest_source" {
  name   = "telemetry-ingest-${filemd5("${path.module}/../../gcp-functions/telemetry-ingest/index.js")}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.telemetry_ingest_zip.output_path
}

data "archive_file" "telemetry_ingest_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../../gcp-functions/telemetry-ingest"
  output_path = "/tmp/telemetry-ingest.zip"
}

resource "google_cloudfunctions_function" "telemetry_ingest" {
  name        = "${var.project_name}-telemetry-ingest"
  description = "Receives telemetry from AWS and writes to BigQuery"
  runtime     = "nodejs22"
  region      = var.region
  labels      = local.labels

  available_memory_mb   = 256
  source_archive_bucket = google_storage_bucket.function_source.name
  source_archive_object = google_storage_bucket_object.telemetry_ingest_source.name
  entry_point           = "ingestTelemetry"
  trigger_http          = true

  environment_variables = {
    BIGQUERY_DATASET = google_bigquery_dataset.main.dataset_id
    BIGQUERY_TABLE   = google_bigquery_table.telemetry.table_id
    PROJECT_ID       = var.project_id
  }
}

# Permite invocaciones sin autenticación desde AWS Lambda
resource "google_cloudfunctions_function_iam_member" "public_invoker" {
  project        = var.project_id
  region         = var.region
  cloud_function = google_cloudfunctions_function.telemetry_ingest.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
}
