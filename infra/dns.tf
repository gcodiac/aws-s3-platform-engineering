# ---------------------------------------------------------------------------
# DNS (optional)
#
# Route 53 is not required. A CloudFront distribution is reachable at its own
# domain name from the moment it deploys, and a custom domain is just a DNS
# record somewhere pointing at it. That "somewhere" is frequently not AWS —
# plenty of organisations keep DNS at Cloudflare, at the registrar, or in a
# corporate zone nobody lets Terraform near.
#
# So this file does nothing unless route53_zone_id is set. When it is not,
# create the record yourself:
#
#   subdomain    CNAME  <cloudfront_domain_name>
#   zone apex    ALIAS / ANAME  <cloudfront_domain_name>
#
# A CNAME cannot exist at a zone apex (example.com rather than
# www.example.com) because the DNS specification forbids a CNAME alongside the
# SOA and NS records that must live there. Route 53 alias records and the
# ALIAS/ANAME/CNAME-flattening features other providers offer are all
# workarounds for exactly this.
# ---------------------------------------------------------------------------

resource "aws_route53_record" "site" {
  for_each = local.dns_alias_records

  zone_id = var.route53_zone_id
  name    = each.value.name
  type    = each.value.type

  alias {
    name    = aws_cloudfront_distribution.site.domain_name
    zone_id = aws_cloudfront_distribution.site.hosted_zone_id

    # Health checks on a CloudFront alias are not useful: the distribution is
    # already globally distributed and does not fail over to anything.
    evaluate_target_health = false
  }
}
