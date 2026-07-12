output "pubsub_topic" {
  value = google_pubsub_topic.telemetry.name
}

output "bigquery_dataset" {
  value = google_bigquery_dataset.main.dataset_id
}

output "bigquery_table" {
  value = google_bigquery_table.telemetry.table_id
}

output "function_url" {
  value = google_cloudfunctions_function.telemetry_ingest.https_trigger_url
}

