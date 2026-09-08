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

# --- Certificate -----------------------------------------------------------

output "acm_certificate_arn" {
  description = "ARN of the ACM certificate, or null when no custom domain is configured."
  value       = try(aws_acm_certificate.site[0].arn, null)
}

output "acm_certificate_status" {
  description = "Certificate status. PENDING_VALIDATION until the DNS records are in place."
  value       = try(aws_acm_certificate.site[0].status, null)
}

output "acm_validation_records" {
  description = <<-EOT
    DNS records that prove domain ownership.

    When route53_zone_id is set these are created for you. Otherwise, create
    them at whichever DNS provider hosts the domain and leave them in place —
    ACM re-checks them at renewal, and deleting them causes a silent renewal
    failure months later.
  EOT
  value = [
    for dvo in try(aws_acm_certificate.site[0].domain_validation_options, []) : {
      name  = dvo.resource_record_name
      type  = dvo.resource_record_type
      value = dvo.resource_record_value
    }
  ]
}

# --- DNS -------------------------------------------------------------------

output "custom_domain_url" {
  description = "URL of the site on its custom domain, or null when none is attached."
  value       = local.attach_custom_domain ? "https://${var.domain_name}" : null
}

output "dns_target" {
  description = <<-EOT
    Value to point your domain at when DNS is managed outside this account.

    Create a CNAME for a subdomain, or an ALIAS/ANAME record at a zone apex.
  EOT
  value       = aws_cloudfront_distribution.site.domain_name
}
