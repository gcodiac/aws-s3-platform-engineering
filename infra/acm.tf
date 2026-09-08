# ---------------------------------------------------------------------------
# TLS certificate
#
# Why us-east-1?
#
# CloudFront is a global service, but its control plane lives in us-east-1 and
# it will only attach a certificate stored there. This has nothing to do with
# where your bucket, your users or your company are — it is simply where
# CloudFront looks. A certificate requested in eu-west-1 is perfectly valid and
# completely invisible to CloudFront, which is why this file uses the
# aws.us_east_1 provider alias for every resource in it.
#
# (Certificates for an Application Load Balancer are the opposite: they must
# live in the same region as the load balancer.)
#
# ACM public certificates are free and renew themselves, as long as the
# validation records stay in place. That last clause is where outages come
# from: delete the CNAME after issuance and renewal silently fails months
# later.
# ---------------------------------------------------------------------------

resource "aws_acm_certificate" "site" {
  count    = local.create_certificate ? 1 : 0
  provider = aws.us_east_1

  domain_name               = var.domain_name
  subject_alternative_names = var.subject_alternative_names

  # DNS validation renews automatically and needs no inbound mail. Email
  # validation requires a human to click a link in an inbox that may no longer
  # exist by renewal time.
  validation_method = "DNS"

  # A certificate cannot be deleted while a distribution is using it, so when
  # the domain list changes the replacement must exist before the old one is
  # removed.
  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${local.name_prefix}-cert"
  }
}

# ---------------------------------------------------------------------------
# Validation
#
# ACM proves you control the domain by asking you to publish a CNAME record.
# There are two paths, and which one you take depends on where DNS lives.
#
#   Route 53 in this account   Terraform writes the records and waits for the
#                              certificate to be issued. One apply, no manual
#                              steps. Set route53_zone_id.
#
#   DNS anywhere else          Terraform requests the certificate and stops.
#                              The records you need are in the
#                              acm_validation_records output; add them at your
#                              provider, wait for ACM to report ISSUED, then
#                              set attach_custom_domain = true and apply again.
#
# The second path is deliberately not automated. Terraform cannot create
# records in a zone it has no access to, and blocking an apply for an hour
# while somebody logs into a registrar is worse than telling you what to do.
# ---------------------------------------------------------------------------

resource "aws_route53_record" "certificate_validation" {
  # for_each over the domain validation options handles a certificate covering
  # several names without duplicating this block. The dvo objects are only
  # known after the certificate is requested.
  for_each = {
    for dvo in try(aws_acm_certificate.site[0].domain_validation_options, []) :
    dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    } if local.manage_dns
  }

  zone_id = var.route53_zone_id
  name    = each.value.name
  type    = each.value.type
  records = [each.value.record]
  ttl     = 60

  # If the record already exists — a previous certificate for the same name —
  # overwrite it rather than failing the apply.
  allow_overwrite = true
}

# This resource creates nothing. It blocks until ACM reports the certificate
# as ISSUED, which gives every resource downstream of it a dependency on a
# usable certificate rather than a pending one.
resource "aws_acm_certificate_validation" "site" {
  count    = local.create_certificate && local.manage_dns ? 1 : 0
  provider = aws.us_east_1

  certificate_arn         = aws_acm_certificate.site[0].arn
  validation_record_fqdns = [for record in aws_route53_record.certificate_validation : record.fqdn]
}
