# ─── WAF: CloudFront (scope global) ──────────────────────────────────────────

resource "aws_wafv2_web_acl" "frontend" {
  name  = "${var.project_name}-frontend-waf"
  scope = "CLOUDFRONT"
  tags  = local.tags

  default_action {
    allow {}
  }

  rule {
    name     = "AWSCommonRules"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-common-rules"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.project_name}-frontend-waf"
    sampled_requests_enabled   = true
  }
}

# ─── WAF: API Gateway WebSocket (scope regional) ─────────────────────────────

resource "aws_wafv2_web_acl" "apigw" {
  name  = "${var.project_name}-apigw-waf"
  scope = "REGIONAL"
  tags  = local.tags

  default_action {
    allow {}
  }

  rule {
    name     = "AWSCommonRules"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-apigw-common-rules"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.project_name}-apigw-waf"
    sampled_requests_enabled   = true
  }
}

resource "aws_wafv2_web_acl_association" "apigw" {
  resource_arn = "arn:aws:apigateway:us-east-1::/restapis/${aws_apigatewayv2_api.ws.id}/stages/${aws_apigatewayv2_stage.main.name}"
  web_acl_arn  = aws_wafv2_web_acl.apigw.arn
}
