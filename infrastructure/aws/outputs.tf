output "cloudfront_url" {
  value = "https://${aws_cloudfront_distribution.frontend.domain_name}"
}

output "ws_endpoint" {
  value = aws_apigatewayv2_stage.main.invoke_url
}

output "kdg_url" {
  value = aws_cloudformation_stack.kdg_cognito.outputs["KinesisDataGeneratorUrl"]
}

output "kinesis_stream_name" {
  value = aws_kinesis_stream.main.name
}

output "frontend_bucket_name" {
  value = aws_s3_bucket.frontend.bucket
}

output "distribution_id" {
  value = aws_cloudfront_distribution.frontend.id
}

output "deploy_bucket_name" {
  value = aws_s3_bucket.deploy.bucket
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.dashboard.id
}

output "cognito_client_id" {
  value = aws_cognito_user_pool_client.dashboard.id
}

output "appconfig_app_id" {
  description = "AppConfig application ID — usar en consola para editar sensor-filter"
  value       = aws_appconfig_application.main.id
}

output "appconfig_env_id" {
  description = "AppConfig environment ID"
  value       = aws_appconfig_environment.main.environment_id
}
