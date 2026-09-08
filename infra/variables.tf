# ---------------------------------------------------------------------------
# Input variables
#
# Nothing environment-specific is hard-coded. The same configuration provisions
# a throwaway lab and a production site; only the values change.
# ---------------------------------------------------------------------------

variable "project" {
  description = "Short project identifier. Used as a name prefix and as a tag."
  type        = string
  default     = "cloud-launchpad"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,30}[a-z0-9]$", var.project))
    error_message = "The project name must be lowercase alphanumeric with hyphens, 3-32 characters, and must not start or end with a hyphen."
  }
}

variable "environment" {
  description = "Environment this stack represents, e.g. course, dev, staging, prod."
  type        = string
  default     = "course"

  validation {
    condition     = can(regex("^[a-z0-9-]{2,20}$", var.environment))
    error_message = "The environment must be lowercase alphanumeric with hyphens, 2-20 characters."
  }
}

variable "aws_region" {
  description = "Region for the S3 bucket. CloudFront is global and ACM is always us-east-1."
  type        = string
  default     = "eu-west-1"
}

variable "bucket_name" {
  description = <<-EOT
    Name of the S3 bucket holding the site.

    S3 bucket names share one global namespace across every AWS account on
    earth, so "my-website" was taken years ago. Leave this empty to derive a
    unique name from the project, environment and account ID.
  EOT
  type        = string
  default     = ""
}

variable "tags" {
  description = "Additional tags merged into the defaults applied to every resource."
  type        = map(string)
  default     = {}
}
