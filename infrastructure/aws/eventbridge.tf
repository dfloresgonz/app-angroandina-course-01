resource "aws_cloudwatch_event_bus" "telemetry" {
  name = "${var.project_name}-telemetry"
  tags = local.tags
}

resource "aws_cloudwatch_event_rule" "forward_to_gcp" {
  name           = "${var.project_name}-forward-to-gcp"
  description    = "Envia lecturas de sensores al forwarder GCP"
  event_bus_name = aws_cloudwatch_event_bus.telemetry.name
  event_pattern  = jsonencode({
    source      = ["angroandina.telemetry"]
    detail-type = ["SensorReading"]
  })
  tags = local.tags
}

resource "aws_cloudwatch_event_target" "gcp_forwarder" {
  rule           = aws_cloudwatch_event_rule.forward_to_gcp.name
  event_bus_name = aws_cloudwatch_event_bus.telemetry.name
  target_id      = "gcp-forwarder"
  arn            = aws_lambda_function.gcp_forwarder.arn
}

resource "aws_lambda_permission" "eventbridge_gcp_forwarder" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.gcp_forwarder.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.forward_to_gcp.arn
}
