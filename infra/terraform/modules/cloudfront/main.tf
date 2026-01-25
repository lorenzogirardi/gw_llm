# CloudFront Distribution Module
#
# Provides HTTPS termination for Kong Gateway and Grafana
# Uses default CloudFront certificate (*.cloudfront.net)

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# -----------------------------------------------------------------------------
# CloudFront Function to block admin endpoints
# -----------------------------------------------------------------------------

resource "aws_cloudfront_function" "block_admin" {
  count = var.block_admin_endpoints ? 1 : 0

  name    = "${var.project_name}-${var.environment}-block-admin"
  runtime = "cloudfront-js-2.0"
  comment = "Block admin endpoints unless X-Admin-Secret header is present"

  code = <<-EOF
function handler(event) {
  var request = event.request;
  var headers = request.headers;

  // Check for admin secret header
  var adminSecret = headers['x-admin-secret'];
  var expectedSecret = '${var.admin_secret_header}';

  // If secret header matches, allow the request
  if (adminSecret && adminSecret.value === expectedSecret && expectedSecret !== '') {
    // Remove the secret header before forwarding to origin
    delete request.headers['x-admin-secret'];
    return request;
  }

  // Block request
  return {
    statusCode: 403,
    statusDescription: 'Forbidden',
    headers: {
      'content-type': { value: 'application/json' }
    },
    body: JSON.stringify({
      error: {
        message: 'Admin endpoints require X-Admin-Secret header',
        code: 'FORBIDDEN'
      }
    })
  };
}
EOF
}

# -----------------------------------------------------------------------------
# CloudFront Function to strip /langfuse prefix
# -----------------------------------------------------------------------------

resource "aws_cloudfront_function" "langfuse_rewrite" {
  count = var.enable_langfuse ? 1 : 0

  name    = "${var.project_name}-${var.environment}-langfuse-rewrite"
  runtime = "cloudfront-js-2.0"
  comment = "Strip /langfuse prefix for Langfuse origin"

  code = <<-EOF
function handler(event) {
  var request = event.request;
  var uri = request.uri;

  // Strip /langfuse prefix
  if (uri.startsWith('/langfuse')) {
    request.uri = uri.replace(/^\/langfuse/, '') || '/';
  }

  return request;
}
EOF
}

# -----------------------------------------------------------------------------
# CloudFront Distribution
# -----------------------------------------------------------------------------

resource "aws_cloudfront_distribution" "main" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "${var.project_name}-${var.environment}"
  default_root_object = ""
  price_class         = var.price_class

  # Origin: ALB (port 80 - LiteLLM, Grafana)
  origin {
    domain_name = var.alb_dns_name
    origin_id   = "alb"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only" # ALB is HTTP for now
      origin_ssl_protocols   = ["TLSv1.2"]
    }

    # Add secret header to verify requests come from CloudFront
    dynamic "custom_header" {
      for_each = var.origin_verify_secret != "" ? [1] : []
      content {
        name  = "X-Origin-Verify"
        value = var.origin_verify_secret
      }
    }
  }

  # Origin: ALB (port 8080 - Langfuse)
  dynamic "origin" {
    for_each = var.enable_langfuse ? [1] : []
    content {
      domain_name = var.alb_dns_name
      origin_id   = "langfuse"

      custom_origin_config {
        http_port              = 8080
        https_port             = 443
        origin_protocol_policy = "http-only"
        origin_ssl_protocols   = ["TLSv1.2"]
      }

      # Add secret header to verify requests come from CloudFront
      dynamic "custom_header" {
        for_each = var.origin_verify_secret != "" ? [1] : []
        content {
          name  = "X-Origin-Verify"
          value = var.origin_verify_secret
        }
      }
    }
  }

  # Default behavior (Kong API)
  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD", "OPTIONS"]
    target_origin_id = "alb"

    forwarded_values {
      query_string = true
      headers      = ["Host", "Origin", "Authorization", "apikey", "X-Bedrock-Model", "Content-Type"]

      cookies {
        forward = "all"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 0
    max_ttl                = 0
    compress               = true
  }

  # Block /user/* admin endpoints (if enabled) - allow with secret header
  dynamic "ordered_cache_behavior" {
    for_each = var.block_admin_endpoints ? [1] : []
    content {
      path_pattern     = "/user/*"
      allowed_methods  = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
      cached_methods   = ["GET", "HEAD"]
      target_origin_id = "alb"

      forwarded_values {
        query_string = true
        headers      = ["Host", "Origin", "Authorization", "Content-Type", "X-Admin-Secret"]
        cookies {
          forward = "all"
        }
      }

      function_association {
        event_type   = "viewer-request"
        function_arn = aws_cloudfront_function.block_admin[0].arn
      }

      viewer_protocol_policy = "redirect-to-https"
      min_ttl                = 0
      default_ttl            = 0
      max_ttl                = 0
    }
  }

  # Block /key/* admin endpoints (if enabled) - allow with secret header
  dynamic "ordered_cache_behavior" {
    for_each = var.block_admin_endpoints ? [1] : []
    content {
      path_pattern     = "/key/*"
      allowed_methods  = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
      cached_methods   = ["GET", "HEAD"]
      target_origin_id = "alb"

      forwarded_values {
        query_string = true
        headers      = ["Host", "Origin", "Authorization", "Content-Type", "X-Admin-Secret"]
        cookies {
          forward = "all"
        }
      }

      function_association {
        event_type   = "viewer-request"
        function_arn = aws_cloudfront_function.block_admin[0].arn
      }

      viewer_protocol_policy = "redirect-to-https"
      min_ttl                = 0
      default_ttl            = 0
      max_ttl                = 0
    }
  }

  # Block /spend/* admin endpoints (if enabled) - allow with secret header
  dynamic "ordered_cache_behavior" {
    for_each = var.block_admin_endpoints ? [1] : []
    content {
      path_pattern     = "/spend/*"
      allowed_methods  = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
      cached_methods   = ["GET", "HEAD"]
      target_origin_id = "alb"

      forwarded_values {
        query_string = true
        headers      = ["Host", "Origin", "Authorization", "Content-Type", "X-Admin-Secret"]
        cookies {
          forward = "all"
        }
      }

      function_association {
        event_type   = "viewer-request"
        function_arn = aws_cloudfront_function.block_admin[0].arn
      }

      viewer_protocol_policy = "redirect-to-https"
      min_ttl                = 0
      default_ttl            = 0
      max_ttl                = 0
    }
  }

  # Block /model/* admin endpoints (if enabled) - allow with secret header
  dynamic "ordered_cache_behavior" {
    for_each = var.block_admin_endpoints ? [1] : []
    content {
      path_pattern     = "/model/*"
      allowed_methods  = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
      cached_methods   = ["GET", "HEAD"]
      target_origin_id = "alb"

      forwarded_values {
        query_string = true
        headers      = ["Host", "Origin", "Authorization", "Content-Type", "X-Admin-Secret"]
        cookies {
          forward = "all"
        }
      }

      function_association {
        event_type   = "viewer-request"
        function_arn = aws_cloudfront_function.block_admin[0].arn
      }

      viewer_protocol_policy = "redirect-to-https"
      min_ttl                = 0
      default_ttl            = 0
      max_ttl                = 0
    }
  }

  # Grafana behavior (longer cache for static assets)
  ordered_cache_behavior {
    path_pattern     = "/grafana/public/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD", "OPTIONS"]
    target_origin_id = "alb"

    forwarded_values {
      query_string = false
      headers      = ["Host", "Origin"]

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
    compress               = true
  }

  # Grafana API (no cache)
  ordered_cache_behavior {
    path_pattern     = "/grafana/*"
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD", "OPTIONS"]
    target_origin_id = "alb"

    forwarded_values {
      query_string = true
      headers      = ["Host", "Origin", "Authorization"]

      cookies {
        forward = "all"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 0
    max_ttl                = 0
    compress               = true
  }

  # Langfuse (no cache, with path rewrite)
  dynamic "ordered_cache_behavior" {
    for_each = var.enable_langfuse ? [1] : []
    content {
      path_pattern     = "/langfuse/*"
      allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
      cached_methods   = ["GET", "HEAD", "OPTIONS"]
      target_origin_id = "langfuse"

      forwarded_values {
        query_string = true
        headers      = ["Host", "Origin", "Authorization"]

        cookies {
          forward = "all"
        }
      }

      function_association {
        event_type   = "viewer-request"
        function_arn = aws_cloudfront_function.langfuse_rewrite[0].arn
      }

      viewer_protocol_policy = "redirect-to-https"
      min_ttl                = 0
      default_ttl            = 0
      max_ttl                = 0
      compress               = true
    }
  }

  # Langfuse Next.js static assets (cached)
  dynamic "ordered_cache_behavior" {
    for_each = var.enable_langfuse ? [1] : []
    content {
      path_pattern     = "/_next/*"
      allowed_methods  = ["GET", "HEAD", "OPTIONS"]
      cached_methods   = ["GET", "HEAD", "OPTIONS"]
      target_origin_id = "langfuse"

      forwarded_values {
        query_string = false
        headers      = ["Host", "Origin"]

        cookies {
          forward = "none"
        }
      }

      viewer_protocol_policy = "redirect-to-https"
      min_ttl                = 0
      default_ttl            = 86400
      max_ttl                = 604800
      compress               = true
    }
  }

  # Langfuse API routes (NextAuth and internal APIs)
  dynamic "ordered_cache_behavior" {
    for_each = var.enable_langfuse ? [1] : []
    content {
      path_pattern     = "/api/*"
      allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
      cached_methods   = ["GET", "HEAD", "OPTIONS"]
      target_origin_id = "langfuse"

      forwarded_values {
        query_string = true
        headers      = ["Host", "Origin", "Authorization"]

        cookies {
          forward = "all"
        }
      }

      viewer_protocol_policy = "redirect-to-https"
      min_ttl                = 0
      default_ttl            = 0
      max_ttl                = 0
      compress               = true
    }
  }

  # Restrictions
  restrictions {
    geo_restriction {
      restriction_type = var.geo_restriction_type
      locations        = var.geo_restriction_locations
    }
  }

  # Use default CloudFront certificate
  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = var.tags
}

# -----------------------------------------------------------------------------
# WAF (optional)
# -----------------------------------------------------------------------------

resource "aws_wafv2_web_acl" "cloudfront" {
  count = var.enable_waf ? 1 : 0

  name        = "${var.project_name}-${var.environment}-waf"
  description = "WAF for ${var.project_name}"
  scope       = "CLOUDFRONT"

  default_action {
    allow {}
  }

  # Priority 1: IP Reputation List (block known malicious IPs first)
  dynamic "rule" {
    for_each = var.enable_waf_ip_reputation ? [1] : []
    content {
      name     = "aws-ip-reputation"
      priority = 1

      override_action {
        none {}
      }

      statement {
        managed_rule_group_statement {
          name        = "AWSManagedRulesAmazonIpReputationList"
          vendor_name = "AWS"
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${var.project_name}-ip-reputation"
        sampled_requests_enabled   = true
      }
    }
  }

  # Priority 2: Common Rule Set (OWASP Top 10)
  dynamic "rule" {
    for_each = var.enable_waf_common_rules ? [1] : []
    content {
      name     = "aws-common-rules"
      priority = 2

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
  }

  # Priority 3: Known Bad Inputs (Log4j, Java deserialization)
  dynamic "rule" {
    for_each = var.enable_waf_known_bad_inputs ? [1] : []
    content {
      name     = "aws-known-bad-inputs"
      priority = 3

      override_action {
        none {}
      }

      statement {
        managed_rule_group_statement {
          name        = "AWSManagedRulesKnownBadInputsRuleSet"
          vendor_name = "AWS"
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${var.project_name}-known-bad-inputs"
        sampled_requests_enabled   = true
      }
    }
  }

  # Priority 4: Bot Control (additional cost ~$10/month)
  dynamic "rule" {
    for_each = var.enable_waf_bot_control ? [1] : []
    content {
      name     = "aws-bot-control"
      priority = 4

      override_action {
        none {}
      }

      statement {
        managed_rule_group_statement {
          name        = "AWSManagedRulesBotControlRuleSet"
          vendor_name = "AWS"

          managed_rule_group_configs {
            aws_managed_rules_bot_control_rule_set {
              inspection_level = "COMMON"
            }
          }
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${var.project_name}-bot-control"
        sampled_requests_enabled   = true
      }
    }
  }

  # Priority 5: Rate limiting
  rule {
    name     = "rate-limit"
    priority = 5

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = var.waf_rate_limit
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.project_name}-waf"
    sampled_requests_enabled   = true
  }

  tags = var.tags
}

resource "aws_wafv2_web_acl_association" "cloudfront" {
  count = var.enable_waf ? 1 : 0

  resource_arn = aws_cloudfront_distribution.main.arn
  web_acl_arn  = aws_wafv2_web_acl.cloudfront[0].arn
}
