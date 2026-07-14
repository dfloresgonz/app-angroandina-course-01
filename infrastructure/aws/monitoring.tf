resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-alerts"
  tags = local.tags
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = "dfloresgonz@gmail.com"
}

resource "aws_cloudwatch_metric_alarm" "gcp_forwarder_errors" {
  alarm_name          = "${var.project_name}-gcp-forwarder-errors"
  alarm_description   = "gcp-forwarder tiene errores — revisar publicacion a Pub/Sub"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions = {
    FunctionName = aws_lambda_function.gcp_forwarder.function_name
  }

  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "gcp_forwarder_dlq" {
  alarm_name          = "${var.project_name}-gcp-forwarder-dlq"
  alarm_description   = "Mensajes en DLQ — revisar reintentos fallidos hacia Pub/Sub"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  dimensions = {
    QueueName = aws_sqs_queue.gcp_forwarder_dlq.name
  }

  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.alerts.arn]

  tags = local.tags
}
