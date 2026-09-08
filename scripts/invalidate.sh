#!/usr/bin/env bash
#
# Invalidate the CloudFront cache after a deployment.
#
#   CLOUDFRONT_DISTRIBUTION_ID=E123ABC ./scripts/invalidate.sh
#
# Environment:
#   CLOUDFRONT_DISTRIBUTION_ID  (required) The distribution to invalidate.
#   INVALIDATION_PATHS          Space-separated paths. Defaults to /*
#   WAIT                        Set to any value to block until the
#                               invalidation reports Completed.
#
# Why this is needed at all
# -------------------------
# CloudFront caches objects at edge locations for as long as their
# Cache-Control headers allow. Uploading a new index.html to S3 does not tell
# the 600-odd edge locations anything; they keep serving what they have until
# it expires. An invalidation is the explicit instruction to drop it.
#
# Cost
# ----
# The first 1,000 invalidation *paths* each month are free, then a few cents
# each. "/*" counts as a single path no matter how many objects it matches,
# which is why it is the default here: one deployment, one path, and the
# monthly allowance covers roughly thirty deployments a day.
#
# Invalidating only what changed is the alternative, and it becomes the right
# answer once assets are fingerprinted: their URLs change when their content
# does, so only the documents that reference them ever need invalidating.
#
set -euo pipefail

: "${CLOUDFRONT_DISTRIBUTION_ID:?CLOUDFRONT_DISTRIBUTION_ID is required — run 'terraform output cloudfront_distribution_id' in infra/}"

read -r -a PATHS <<<"${INVALIDATION_PATHS:-/*}"

printf 'Invalidating %s on distribution %s\n' "${PATHS[*]}" "$CLOUDFRONT_DISTRIBUTION_ID"

INVALIDATION_ID=$(
  aws cloudfront create-invalidation \
    --distribution-id "$CLOUDFRONT_DISTRIBUTION_ID" \
    --paths "${PATHS[@]}" \
    --query 'Invalidation.Id' \
    --output text
)

printf '  invalidation %s created\n' "$INVALIDATION_ID"

# Export for any later step that wants to report it.
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "invalidation_id=$INVALIDATION_ID" >> "$GITHUB_OUTPUT"
fi

if [[ -n "${WAIT:-}" ]]; then
  # Invalidations usually complete in well under a minute, but the edge
  # network is eventually consistent and it can occasionally take several.
  printf '  waiting for propagation…\n'
  aws cloudfront wait invalidation-completed \
    --distribution-id "$CLOUDFRONT_DISTRIBUTION_ID" \
    --id "$INVALIDATION_ID"
  printf '  invalidation %s completed\n' "$INVALIDATION_ID"
fi
