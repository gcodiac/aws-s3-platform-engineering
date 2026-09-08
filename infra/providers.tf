# ---------------------------------------------------------------------------
# Providers
#
# Two AWS providers are configured against the same account.
#
#   default    — the region the bucket lives in
#   us_east_1  — an alias used only for AWS Certificate Manager
#
# CloudFront is a global service whose control plane lives in us-east-1, and it
# will only attach a certificate issued in that region. The bucket, by
# contrast, should be near whoever writes to it. Provider aliases let one
# configuration span both without splitting it into two root modules.
# ---------------------------------------------------------------------------

provider "aws" {
  region = var.aws_region

  # Applied to every taggable resource this provider creates, so no individual
  # resource can forget them. Tags are how you find and delete your lab
  # resources later, and how finance works out who spent what.
  default_tags {
    tags = local.tags
  }
}

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = local.tags
  }
}
