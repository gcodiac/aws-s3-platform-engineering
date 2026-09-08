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

  # --- GitHub Actions federation -------------------------------------------

  create_deploy_role         = var.github_repository != ""
  create_oidc_provider       = local.create_deploy_role && var.create_github_oidc_provider
  use_existing_oidc_provider = local.create_deploy_role && !var.create_github_oidc_provider

  oidc_provider_arn = local.create_oidc_provider ? try(aws_iam_openid_connect_provider.github[0].arn, null) : try(data.aws_iam_openid_connect_provider.github[0].arn, null)

  # Exactly which workflow runs may assume the role. A token from any other
  # repository, branch or environment is rejected by the trust policy.
  #
  # GitHub issues the subject claim in two shapes, and a trust policy that
  # only knows about the older one fails with an unexplained
  # "Not authorized to perform sts:AssumeRoleWithWebIdentity".
  #
  #   classic     repo:owner/name:ref:refs/heads/main
  #   immutable   repo:owner@1234567/name@89012345:ref:refs/heads/main
  #
  # The immutable form embeds the numeric owner and repository IDs, which
  # cannot be reused. It closes a real hole: delete a repository, and someone
  # else can register the same owner/name and mint tokens your trust policy
  # accepts. GitHub is rolling this out, so both forms are matched here.
  #
  # Note where the wildcards sit. "owner@*" is anchored on the literal login
  # followed by "@", so it cannot match a different account whose name merely
  # starts the same way. A pattern like "repo:owner*" would.
  gh_repo_parts = split("/", var.github_repository)
  gh_owner      = length(local.gh_repo_parts) == 2 ? local.gh_repo_parts[0] : ""
  gh_repo_name  = length(local.gh_repo_parts) == 2 ? local.gh_repo_parts[1] : ""

  github_subject_prefixes = [
    "repo:${var.github_repository}",
    "repo:${local.gh_owner}@*/${local.gh_repo_name}@*",
  ]

  github_subjects = flatten([
    for prefix in local.github_subject_prefixes : concat(
      [for ref in var.github_deploy_refs : "${prefix}:ref:${ref}"],
      var.github_environment != "" ? ["${prefix}:environment:${var.github_environment}"] : []
    )
  ])

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
