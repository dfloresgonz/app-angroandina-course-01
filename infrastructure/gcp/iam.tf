# SA que Pub/Sub usa para invocar la Cloud Function vía OIDC
resource "google_service_account" "pubsub_invoker" {
  account_id   = "${var.project_name}-pubsub-inv"
  display_name = "Pub/Sub Push Invoker SA"
}
