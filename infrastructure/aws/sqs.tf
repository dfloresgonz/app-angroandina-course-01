resource "aws_sqs_queue" "gcp_forwarder_dlq" {
  name                      = "${var.project_name}-gcp-forwarder-dlq"
  message_retention_seconds = 1209600 # 14 días
  tags                      = local.tags
}

resource "aws_sqs_queue" "gcp_forwarder" {
  name = "${var.project_name}-gcp-forwarder-queue"

  # Debe ser >= timeout de la Lambda (15s) × 6 (recomendación AWS)
  visibility_timeout_seconds = 90
  message_retention_seconds  = 86400 # 1 día

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.gcp_forwarder_dlq.arn
    maxReceiveCount     = 3
  })

  tags = local.tags
}

# Permite que EventBridge publique en la queue
resource "aws_sqs_queue_policy" "gcp_forwarder" {
  queue_url = aws_sqs_queue.gcp_forwarder.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "events.amazonaws.com" }
        Action    = "sqs:SendMessage"
        Resource  = aws_sqs_queue.gcp_forwarder.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_cloudwatch_event_rule.forward_to_gcp.arn
          }
        }
      }
    ]
  })
}
