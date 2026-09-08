# ---------------------------------------------------------------------------
# Version constraints
#
# Pinning matters more than it looks. Terraform and the AWS provider both
# introduce behavioural changes between releases, and an unpinned provider
# means the plan an engineer reviewed on Monday is not necessarily the plan CI
# applies on Friday. The lock file (.terraform.lock.hcl) records the exact
# versions and their checksums and is committed for the same reason.
# ---------------------------------------------------------------------------

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}
