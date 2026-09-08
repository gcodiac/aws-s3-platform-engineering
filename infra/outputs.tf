# ---------------------------------------------------------------------------
# Outputs
#
# Outputs are the interface between this configuration and everything else:
# the deployment pipeline, the runbook, and the engineer who needs to know
# which account they just changed.
# ---------------------------------------------------------------------------

output "aws_account_id" {
  description = "Account these resources were created in."
  value       = data.aws_caller_identity.current.account_id
}

output "aws_region" {
  description = "Region the regional resources were created in."
  value       = data.aws_region.current.region
}

# --- Origin bucket ---------------------------------------------------------

output "bucket_name" {
  description = "Name of the S3 bucket holding the site. The deployment pipeline syncs into this."
  value       = aws_s3_bucket.site.id
}

output "bucket_arn" {
  description = "ARN of the origin bucket."
  value       = aws_s3_bucket.site.arn
}

output "bucket_regional_domain_name" {
  description = "REST endpoint of the bucket. This is the CloudFront origin — note it is not a website endpoint."
  value       = aws_s3_bucket.site.bucket_regional_domain_name
}

# --- CloudFront ------------------------------------------------------------

output "cloudfront_distribution_id" {
  description = "Distribution ID. The deployment pipeline needs this to create invalidations."
  value       = aws_cloudfront_distribution.site.id
}

output "cloudfront_domain_name" {
  description = "The distribution's own domain name, e.g. d111111abcdef8.cloudfront.net."
  value       = aws_cloudfront_distribution.site.domain_name
}

output "site_url" {
  description = "Public URL of the deployed site."
  value       = "https://${aws_cloudfront_distribution.site.domain_name}"
}
