##############################################################################
# CloudFront — Origin Access Control (OAC) for S3 Website
##############################################################################

resource "aws_cloudfront_origin_access_control" "website" {
  name                              = "${local.suffix}-site-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

##############################################################################
# CloudFront — Website Distribution (S3 + API Gateway origins)
##############################################################################

resource "aws_cloudfront_distribution" "website" {
  comment             = "${local.suffix}-cdn-${local.region}"
  default_root_object = "index.html"
  enabled             = true
  is_ipv6_enabled     = true
  price_class         = "PriceClass_All"

  # Geo restriction — blacklist (matches original template)
  restrictions {
    geo_restriction {
      restriction_type = "blacklist"
      locations        = ["AF", "IR", "IQ", "LY", "SY"]
    }
  }

  # S3 website origin
  origin {
    domain_name              = aws_s3_bucket.website.bucket_regional_domain_name
    origin_id                = "website"
    origin_path              = "/website"
    origin_access_control_id = aws_cloudfront_origin_access_control.website.id

    s3_origin_config {
      origin_access_identity = ""
    }
  }

  # API Gateway origin
  origin {
    domain_name = "${aws_apigatewayv2_api.http.id}.execute-api.${local.region}.amazonaws.com"
    origin_id   = "api"

    custom_header {
      name  = "X-Origin-Key"
      value = local.suffix
    }

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # Default behavior — S3 website
  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "website"
    viewer_protocol_policy = "redirect-to-https"
    compress               = true
    min_ttl                = 0
    default_ttl            = 0
    max_ttl                = 0

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }

  # API behavior — forwards to API Gateway
  ordered_cache_behavior {
    path_pattern           = "/api/*"
    allowed_methods        = ["GET", "HEAD", "OPTIONS", "PUT", "PATCH", "POST", "DELETE"]
    cached_methods         = ["GET", "HEAD", "OPTIONS"]
    target_origin_id       = "api"
    viewer_protocol_policy = "redirect-to-https"
    compress               = true
    min_ttl                = 0
    default_ttl            = 0
    max_ttl                = 0

    forwarded_values {
      query_string = true
      headers      = ["Authorization", "User-Agent"]
      cookies {
        forward = "none"
      }
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = merge(local.common_tags, {
    Name = "${local.suffix}-cdn-${local.region}"
  })
}
