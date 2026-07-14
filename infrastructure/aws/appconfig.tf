resource "aws_appconfig_application" "main" {
  name        = var.project_name
  description = "Feature flags para AgroAndina Monitor"
  tags        = local.tags
}

resource "aws_appconfig_environment" "main" {
  name           = var.environment
  application_id = aws_appconfig_application.main.id
  tags           = local.tags
}

resource "aws_appconfig_configuration_profile" "sensor_filter" {
  name           = "sensor-filter"
  application_id = aws_appconfig_application.main.id
  location_uri   = "hosted"
  type           = "AWS.Freeform"
  tags           = local.tags
}

resource "aws_appconfig_hosted_configuration_version" "sensor_filter" {
  application_id           = aws_appconfig_application.main.id
  configuration_profile_id = aws_appconfig_configuration_profile.sensor_filter.configuration_profile_id
  content_type             = "application/json"

  # Por defecto ningún sensor deshabilitado
  content = jsonencode({
    disabled_sensors = []
  })
}

resource "aws_appconfig_deployment_strategy" "instant" {
  name                           = "${var.project_name}-instant"
  description                    = "Despliegue inmediato sin bake time"
  deployment_duration_in_minutes = 0
  final_bake_time_in_minutes     = 0
  growth_factor                  = 100
  replicate_to                   = "NONE"
  tags                           = local.tags
}

resource "aws_appconfig_deployment" "sensor_filter" {
  application_id           = aws_appconfig_application.main.id
  environment_id           = aws_appconfig_environment.main.environment_id
  configuration_profile_id = aws_appconfig_configuration_profile.sensor_filter.configuration_profile_id
  configuration_version    = aws_appconfig_hosted_configuration_version.sensor_filter.version_number
  deployment_strategy_id   = aws_appconfig_deployment_strategy.instant.id
  tags                     = local.tags
}
