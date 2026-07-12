locals {
  lambda_zip_path = "${path.module}/../../.lambda-zips"
}

resource "aws_lambda_function" "ws_handler" {
  function_name    = "${var.project_name}-ws-handler"
  role             = aws_iam_role.ws_handler.arn
  handler          = "index.handler"
  runtime          = "nodejs24.x"
  filename         = "${local.lambda_zip_path}/ws-handler.zip"
  source_code_hash = filebase64sha256("${local.lambda_zip_path}/ws-handler.zip")
  tags             = local.tags

  environment {
    variables = {
      WS_CONNECTIONS_TABLE = aws_dynamodb_table.ws_connections.name
    }
  }
}

resource "aws_lambda_function" "gcp_forwarder" {
  function_name    = "${var.project_name}-gcp-forwarder"
  role             = aws_iam_role.gcp_forwarder.arn
  handler          = "index.handler"
  runtime          = "nodejs24.x"
  filename         = "${local.lambda_zip_path}/gcp-forwarder.zip"
  source_code_hash = filebase64sha256("${local.lambda_zip_path}/gcp-forwarder.zip")
  tags             = local.tags

  environment {
    variables = {
      GCP_PUBSUB_URL = var.gcp_forwarder_url
    }
  }
}

resource "aws_lambda_function" "data_processor" {
  function_name    = "${var.project_name}-data-processor"
  role             = aws_iam_role.data_processor.arn
  handler          = "index.handler"
  runtime          = "nodejs24.x"
  filename         = "${local.lambda_zip_path}/data-processor.zip"
  source_code_hash = filebase64sha256("${local.lambda_zip_path}/data-processor.zip")
  tags             = local.tags

  environment {
    variables = {
      TELEMETRY_TABLE      = aws_dynamodb_table.telemetry.name
      WS_CONNECTIONS_TABLE = aws_dynamodb_table.ws_connections.name
      WS_ENDPOINT          = replace(aws_apigatewayv2_stage.main.invoke_url, "wss://", "https://")
      GCP_FORWARDER_ARN    = aws_lambda_function.gcp_forwarder.arn
    }
  }
}

resource "aws_lambda_event_source_mapping" "kinesis" {
  event_source_arn  = aws_kinesis_stream.main.arn
  function_name     = aws_lambda_function.data_processor.arn
  starting_position = "LATEST"
  batch_size        = 10
}

resource "aws_apigatewayv2_api" "ws" {
  name                       = "${var.project_name}-ws"
  protocol_type              = "WEBSOCKET"
  route_selection_expression = "$request.body.action"
  tags                       = local.tags
}

resource "aws_apigatewayv2_integration" "ws_handler" {
  api_id             = aws_apigatewayv2_api.ws.id
  integration_type   = "AWS_PROXY"
  integration_uri    = aws_lambda_function.ws_handler.invoke_arn
  integration_method = "POST"
}

resource "aws_apigatewayv2_route" "connect" {
  api_id    = aws_apigatewayv2_api.ws.id
  route_key = "$connect"
  target    = "integrations/${aws_apigatewayv2_integration.ws_handler.id}"
}

resource "aws_apigatewayv2_route" "disconnect" {
  api_id    = aws_apigatewayv2_api.ws.id
  route_key = "$disconnect"
  target    = "integrations/${aws_apigatewayv2_integration.ws_handler.id}"
}

resource "aws_apigatewayv2_route" "default" {
  api_id    = aws_apigatewayv2_api.ws.id
  route_key = "$default"
  target    = "integrations/${aws_apigatewayv2_integration.ws_handler.id}"
}

resource "aws_apigatewayv2_stage" "main" {
  api_id      = aws_apigatewayv2_api.ws.id
  name        = var.environment
  auto_deploy = true
  tags        = local.tags
}

resource "aws_lambda_permission" "ws_handler" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ws_handler.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.ws.execution_arn}/*/*"
}
