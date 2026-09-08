# ---------------------------------------------------------------------------
# Origin bucket
#
# This bucket is the origin, not the website. It has no static website
# endpoint, no public read policy and no public ACLs. Visitors never talk to
# it; CloudFront does, and only CloudFront is allowed to.
#
# The distinction matters. S3's static website hosting feature serves objects
# over plain HTTP from a public bucket, which means no TLS, no CDN, and a
# bucket policy that grants s3:GetObject to the entire internet. Keeping the
# bucket private and putting CloudFront in front of it costs nothing extra and
# removes an entire class of incident.
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "site" {
  bucket = local.bucket_name

  # force_destroy deletes every object when the bucket is destroyed. That is
  # right for a disposable lab and wrong for anything holding data you would
  # miss, which is why it is a variable and defaults to false.
  force_destroy = var.force_destroy_bucket
}

# ---------------------------------------------------------------------------
# Block public access
#
# Four independent switches, all on. This is an account-level safety net that
# overrides bucket policies and ACLs: even if somebody later writes a policy
# granting s3:GetObject to "*", S3 refuses to honour it.
#
# This is the single most important resource in the file.
# ---------------------------------------------------------------------------

resource "aws_s3_bucket_public_access_block" "site" {
  bucket = aws_s3_bucket.site.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---------------------------------------------------------------------------
# Ownership
#
# BucketOwnerEnforced disables ACLs entirely. Object ACLs are a pre-IAM
# mechanism that has caused a long line of accidental exposures; with them
# disabled, access is decided by bucket policy and IAM alone, which is one
# model to reason about instead of two overlapping ones.
# ---------------------------------------------------------------------------

resource "aws_s3_bucket_ownership_controls" "site" {
  bucket = aws_s3_bucket.site.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# ---------------------------------------------------------------------------
# Encryption at rest
#
# SSE-S3 (AES-256) is applied to every object, managed by S3 at no cost.
#
# SSE-KMS with a customer managed key gives you an audit trail and key policy
# control, at the price of KMS request charges and a key policy that must also
# grant the CloudFront service principal decrypt permission. For a public
# website that is complexity without benefit — the content is public by
# definition. Encrypt with KMS when the objects are not.
# ---------------------------------------------------------------------------

resource "aws_s3_bucket_server_side_encryption_configuration" "site" {
  bucket = aws_s3_bucket.site.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# ---------------------------------------------------------------------------
# Versioning
#
# Every deployment overwrites objects in place. With versioning enabled a bad
# deploy is recoverable: the previous object is still there under an older
# version ID. This is the cheapest rollback mechanism available for a static
# site, and it costs storage for the versions you keep.
# ---------------------------------------------------------------------------

resource "aws_s3_bucket_versioning" "site" {
  bucket = aws_s3_bucket.site.id

  versioning_configuration {
    status = var.enable_versioning ? "Enabled" : "Suspended"
  }
}

# ---------------------------------------------------------------------------
# Lifecycle
#
# Versioning without expiry is a bill that grows forever. Old versions are
# useful for rollback for days, not years, so they are expired. Incomplete
# multipart uploads are invisible in the console and billed as storage, so
# they are aborted too.
# ---------------------------------------------------------------------------

resource "aws_s3_bucket_lifecycle_configuration" "site" {
  bucket = aws_s3_bucket.site.id

  # The lifecycle configuration depends on versioning being settled first,
  # otherwise the noncurrent version rule can be applied to a bucket that is
  # not yet versioned.
  depends_on = [aws_s3_bucket_versioning.site]

  rule {
    id     = "expire-noncurrent-versions"
    status = var.enable_versioning ? "Enabled" : "Disabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_retention_days
    }
  }

  rule {
    id     = "abort-incomplete-multipart-uploads"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}
