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
