# ---------------------------------------------------------------------------
# CloudFront distribution
#
# CloudFront is doing four jobs here, and it is worth being able to name them:
#
#   1. Terminating TLS, so the site is reachable over HTTPS at all.
#   2. Caching at hundreds of edge locations, so most requests never reach S3.
#   3. Compressing responses, so HTML, CSS and JS travel as gzip or Brotli.
#   4. Being the only principal allowed to read the origin bucket.
#
# Only the fourth is unusual, and it is the one that lets the bucket stay
# private. That part arrives in the next commit — until then this distribution
# has no permission to read the bucket and every request returns 403.
# ---------------------------------------------------------------------------

# AWS maintains a set of cache policies so you do not have to invent TTLs.
# CachingOptimized caches on the URL path only (no cookies, no query strings,
# no headers), which is exactly right for a static site, and it honours the
# Cache-Control headers the deployment sets on each object.
data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

resource "aws_cloudfront_distribution" "site" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "${local.name_prefix} static site"
  default_root_object = var.default_root_object
  price_class         = var.price_class

  origin {
    origin_id = local.s3_origin_id

    # The REST endpoint (bucket.s3.region.amazonaws.com), NOT the website
    # endpoint (bucket.s3-website-region.amazonaws.com). The website endpoint
    # only serves public objects over plain HTTP and cannot authenticate a
    # signed request, so it cannot be used with a private bucket.
    domain_name = aws_s3_bucket.site.bucket_regional_domain_name
  }

  default_cache_behavior {
    target_origin_id = local.s3_origin_id

    # A static site answers reads. Anything else is a bug or an attack.
    allowed_methods = ["GET", "HEAD", "OPTIONS"]
    cached_methods  = ["GET", "HEAD"]

    # Plain HTTP is answered with a 301 to the HTTPS URL rather than being
    # refused, so old links and typed URLs still work.
    viewer_protocol_policy = "redirect-to-https"

    # Compress at the edge. Text assets shrink by roughly 70%, and the origin
    # does not have to store two copies.
    compress = true

    cache_policy_id = data.aws_cloudfront_cache_policy.caching_optimized.id
  }

  # -------------------------------------------------------------------------
  # Error handling
  #
  # A missing object produces 403 from a private bucket, not 404: S3 will not
  # confirm whether an object exists to a caller that cannot read it. Both are
  # mapped to the custom error page, and both are returned to the visitor as
  # 404 so that search engines and monitoring see the truth.
  #
  # error_caching_min_ttl keeps a mistyped URL from hammering the origin,
  # while staying short enough that a genuinely missing file appears quickly
  # once it is deployed.
  # -------------------------------------------------------------------------
  custom_error_response {
    error_code            = 403
    response_code         = 404
    response_page_path    = "/404.html"
    error_caching_min_ttl = 10
  }

  custom_error_response {
    error_code            = 404
    response_code         = 404
    response_page_path    = "/404.html"
    error_caching_min_ttl = 10
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    # The free *.cloudfront.net certificate. Replaced by an ACM certificate
    # once a custom domain is configured.
    cloudfront_default_certificate = true
  }

  tags = {
    Name = "${local.name_prefix}-cdn"
  }
}
