resource "aws_cloudwatch_event_bus" "telemetry" {
  name = "${var.project_name}-telemetry"
  tags = local.tags
}

resource "aws_cloudwatch_event_rule" "forward_to_gcp" {
  name           = "${var.project_name}-forward-to-gcp"
  description    = "Envia lecturas de sensores a SQS para reenvío a GCP"
  event_bus_name = aws_cloudwatch_event_bus.telemetry.name
  event_pattern  = jsonencode({
    source      = ["angroandina.telemetry"]
    detail-type = ["SensorReading"]
  })
  tags = local.tags
}

# Target: SQS (no Lambda directamente — el retry lo maneja SQS+DLQ)
resource "aws_cloudwatch_event_target" "gcp_forwarder" {
  rule           = aws_cloudwatch_event_rule.forward_to_gcp.name
  event_bus_name = aws_cloudwatch_event_bus.telemetry.name
  target_id      = "gcp-forwarder-queue"
  arn            = aws_sqs_queue.gcp_forwarder.arn
}
