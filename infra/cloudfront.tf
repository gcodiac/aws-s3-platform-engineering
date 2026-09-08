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

# ---------------------------------------------------------------------------
# Origin Access Control
#
# OAC is how CloudFront proves to S3 that a request really came from this
# distribution. CloudFront signs every origin request with SigV4 using
# credentials AWS manages on its behalf; S3 validates the signature against a
# bucket policy that names the CloudFront service principal.
#
# The result is that the bucket can stay completely private while still being
# readable by the CDN. Nobody holds a key, nothing needs rotating, and there
# is no URL anywhere that serves the objects directly.
#
# OAC replaces Origin Access Identity (OAI), the older mechanism. OAI still
# works but does not support SSE-KMS, newer regions, or anything other than
# GET, and AWS recommends OAC for new distributions. If you find OAI in a
# tutorial, the tutorial predates 2022.
# ---------------------------------------------------------------------------

resource "aws_cloudfront_origin_access_control" "site" {
  name        = "${local.name_prefix}-oac"
  description = "Signs CloudFront requests to the ${local.bucket_name} origin"

  origin_access_control_origin_type = "s3"

  # "always" signs every request. "never" disables signing, and
  # "no-override" only signs when the viewer did not already send an
  # Authorization header — neither is appropriate for a private origin.
  signing_behavior = "always"
  signing_protocol = "sigv4"
}

resource "aws_cloudfront_distribution" "site" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "${local.name_prefix} static site"
  default_root_object = var.default_root_object
  price_class         = var.price_class

  # The domains this distribution will answer to, in addition to its own
  # *.cloudfront.net name. Empty until a validated certificate exists —
  # CloudFront rejects an alias it has no certificate for.
  aliases = local.domain_aliases

  origin {
    origin_id = local.s3_origin_id

    # The REST endpoint (bucket.s3.region.amazonaws.com), NOT the website
    # endpoint (bucket.s3-website-region.amazonaws.com). The website endpoint
    # only serves public objects over plain HTTP and cannot authenticate a
    # signed request, so it cannot be used with a private bucket.
    domain_name = aws_s3_bucket.site.bucket_regional_domain_name

    # Without this, CloudFront sends anonymous requests to the origin and a
    # private bucket answers every one of them with 403.
    origin_access_control_id = aws_cloudfront_origin_access_control.site.id
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

  # -------------------------------------------------------------------------
  # TLS
  #
  # Either the free *.cloudfront.net certificate, or the ACM certificate for
  # the custom domain. Exactly one set of attributes applies; the rest are
  # null and the provider leaves them alone.
  # -------------------------------------------------------------------------
  viewer_certificate {
    cloudfront_default_certificate = local.attach_custom_domain ? null : true

    acm_certificate_arn = local.attach_custom_domain ? local.certificate_arn : null

    # SNI is free and supported by every browser released this decade. The
    # alternative, a dedicated IP address, costs hundreds of dollars a month
    # and exists for clients that predate 2013.
    ssl_support_method = local.attach_custom_domain ? "sni-only" : null

    minimum_protocol_version = local.attach_custom_domain ? var.minimum_protocol_version : null
  }

  # Fail during plan with a sentence a human can act on, rather than during
  # apply with an AWS API error.
  lifecycle {
    precondition {
      condition     = !var.attach_custom_domain || var.domain_name != ""
      error_message = "attach_custom_domain is true but domain_name is empty. Set domain_name, or leave both unset to use the *.cloudfront.net domain."
    }
  }

  tags = {
    Name = "${local.name_prefix}-cdn"
  }
}
