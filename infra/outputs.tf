# ---------------------------------------------------------------------------
# Outputs
#
# Outputs are the interface between this configuration and everything else:
# the deployment pipeline, the runbook, and the engineer who needs to know
# which account they just changed.
# ---------------------------------------------------------------------------

output "aws_account_id" {
  description = "Account these resources were created in."
  value       = data.aws_caller_identity.current.account_id
}

output "aws_region" {
  description = "Region the regional resources were created in."
  value       = data.aws_region.current.region
}
