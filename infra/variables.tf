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

# --- Origin bucket ---------------------------------------------------------

variable "enable_versioning" {
  description = <<-EOT
    Keep previous versions of every object.

    This is the rollback mechanism for a static site: a bad deploy can be
    undone by restoring the previous version rather than rebuilding it.
  EOT
  type        = bool
  default     = true
}

variable "noncurrent_version_retention_days" {
  description = "How long to keep superseded object versions before expiring them."
  type        = number
  default     = 30

  validation {
    condition     = var.noncurrent_version_retention_days >= 1
    error_message = "Retention must be at least one day."
  }
}

variable "force_destroy_bucket" {
  description = <<-EOT
    Allow `terraform destroy` to delete a bucket that still contains objects.

    Convenient for a disposable lab, dangerous anywhere else: it is the
    difference between destroy failing safely and destroy succeeding
    permanently.
  EOT
  type        = bool
  default     = false
}

# --- CloudFront ------------------------------------------------------------

variable "default_root_object" {
  description = "Object returned for a request to the distribution root."
  type        = string
  default     = "index.html"
}

variable "price_class" {
  description = <<-EOT
    Which edge locations serve the site.

    PriceClass_100 uses North America and Europe only and is the cheapest.
    PriceClass_200 adds Asia, the Middle East and Africa.
    PriceClass_All uses every location, including South America and Oceania.

    This is a cost/latency trade-off, not an availability one: visitors
    outside the selected classes are still served, just from further away.
  EOT
  type        = string
  default     = "PriceClass_100"

  validation {
    condition     = contains(["PriceClass_100", "PriceClass_200", "PriceClass_All"], var.price_class)
    error_message = "price_class must be PriceClass_100, PriceClass_200 or PriceClass_All."
  }
}

# --- Custom domain and TLS -------------------------------------------------

variable "domain_name" {
  description = <<-EOT
    Custom domain for the site, e.g. launchpad.example.com.

    Leave empty to use the distribution's own *.cloudfront.net domain, which
    is free, already has a valid certificate, and is perfectly adequate for a
    lab. Setting this requests an ACM certificate; it does not, on its own,
    put the domain in front of the distribution — see attach_custom_domain.
  EOT
  type        = string
  default     = ""
}

variable "subject_alternative_names" {
  description = "Additional names on the certificate, e.g. [\"www.example.com\"]."
  type        = list(string)
  default     = []
}

variable "route53_zone_id" {
  description = <<-EOT
    Route 53 hosted zone ID for domain_name, if the zone is in this account.

    When set, Terraform writes the ACM validation records and waits for the
    certificate to be issued. Leave empty when DNS is managed anywhere else;
    the records you need are then published in the acm_validation_records
    output.
  EOT
  type        = string
  default     = ""
}
