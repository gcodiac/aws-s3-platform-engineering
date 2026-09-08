# ---------------------------------------------------------------------------
# Data sources and computed values
# ---------------------------------------------------------------------------

# Who is Terraform actually acting as? The account ID is used to build a
# globally unique bucket name; the ARN is worth outputting so that an engineer
# can confirm which account they just changed.
data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

locals {
  name_prefix = "${var.project}-${var.environment}"

  # S3 bucket names are global. Suffixing with the account ID makes the name
  # deterministic — no random suffix, so a destroy and re-apply reuses it —
  # while staying unique to this account.
  bucket_name = coalesce(
    var.bucket_name != "" ? var.bucket_name : null,
    "${local.name_prefix}-${data.aws_caller_identity.current.account_id}"
  )

  # A stable identifier for the origin inside the distribution. Changing it
  # forces CloudFront to replace the behaviour that references it.
  s3_origin_id = "s3-${local.bucket_name}"

  # --- Custom domain -------------------------------------------------------

  # A certificate is only requested when a domain has been supplied.
  create_certificate = var.domain_name != ""

  # Terraform manages the DNS records only when the hosted zone is in this
  # account and its ID has been provided.
  manage_dns = var.route53_zone_id != ""

  # When Terraform manages DNS it can wait for issuance, so downstream
  # resources depend on the validation. Otherwise they use the certificate
  # directly and it is the operator's job to have validated it.
  # Attaching the domain is a separate switch from requesting the
  # certificate, because the certificate has to be ISSUED first. Pointing a
  # distribution at a PENDING_VALIDATION certificate fails the apply.
  attach_custom_domain = var.attach_custom_domain && local.create_certificate

  domain_aliases = local.attach_custom_domain ? concat([var.domain_name], var.subject_alternative_names) : []

  # One A record and one AAAA record per name, but only when Terraform owns
  # the zone. IPv6 is enabled on the distribution, so an A record alone would
  # leave IPv6-only clients unable to resolve the site.
  dns_alias_records = local.manage_dns ? {
    for pair in setproduct(local.domain_aliases, ["A", "AAAA"]) :
    "${pair[0]}-${pair[1]}" => { name = pair[0], type = pair[1] }
  } : {}

  certificate_arn = local.manage_dns ? try(aws_acm_certificate_validation.site[0].certificate_arn, null) : try(aws_acm_certificate.site[0].arn, null)

  tags = merge(
    {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "Terraform"
      Repository  = "aws-s3-platform-engineering"
    },
    var.tags
  )
}
