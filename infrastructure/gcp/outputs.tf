output "pubsub_topic" {
  description = "Pub/Sub topic name para publicar telemetría desde AWS"
  value       = google_pubsub_topic.telemetry.name
}

output "bigquery_dataset" {
  value = google_bigquery_dataset.main.dataset_id
}

output "bigquery_table" {
  value = google_bigquery_table.telemetry.table_id
}

output "function_url" {
  description = "URL de telemetry-ingest (solo para referencia — la invoca Pub/Sub)"
  value       = google_cloudfunctions2_function.telemetry_ingest.service_config[0].uri
}
