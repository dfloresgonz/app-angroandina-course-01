resource "aws_dynamodb_table" "telemetry" {
  name         = "${var.project_name}-telemetry"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "sensor_id"
  range_key    = "timestamp"
  tags         = local.tags

  attribute {
    name = "sensor_id"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "S"
  }

  ttl {
    attribute_name = "expiresAt"
    enabled        = true
  }
}

resource "aws_dynamodb_table" "ws_connections" {
  name         = "${var.project_name}-ws-connections"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "connectionId"
  tags         = local.tags

  attribute {
    name = "connectionId"
    type = "S"
  }
}
