resource "google_bigquery_dataset" "main" {
  dataset_id  = replace("${var.project_name}_monitor", "-", "_")
  location    = "US"
  description = "Telemetry data from IoT sensors - AgroAndina Fresh"
  labels      = local.labels
}

resource "google_bigquery_table" "telemetry" {
  dataset_id          = google_bigquery_dataset.main.dataset_id
  table_id            = "telemetry"
  deletion_protection = false
  labels              = local.labels

  time_partitioning {
    type  = "DAY"
    field = "timestamp"
  }

  schema = jsonencode([
    { name = "sensor_id",      type = "STRING",    mode = "REQUIRED" },
    { name = "timestamp",      type = "TIMESTAMP", mode = "REQUIRED" },
    { name = "temperature",    type = "FLOAT",     mode = "NULLABLE" },
    { name = "humidity",       type = "FLOAT",     mode = "NULLABLE" },
    { name = "soil_moisture",  type = "FLOAT",     mode = "NULLABLE" },
    { name = "light_intensity",type = "FLOAT",     mode = "NULLABLE" },
    { name = "wind_speed",     type = "FLOAT",     mode = "NULLABLE" },
    { name = "battery_level",  type = "FLOAT",     mode = "NULLABLE" },
    { name = "received_at",    type = "TIMESTAMP", mode = "REQUIRED" }
  ])
}
