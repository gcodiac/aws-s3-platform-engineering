#!/usr/bin/env bash
#
# Upload the built site to S3.
#
# Run scripts/build.sh first: this script deploys dist/ and nothing else, so
# whatever is in the repository root cannot leak into the bucket.
#
#   S3_BUCKET=my-bucket ./scripts/deploy.sh
#
# Environment:
#   S3_BUCKET   (required) Destination bucket name.
#   DRY_RUN     Set to any value to print what would change without doing it.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$ROOT/dist"
cd "$ROOT"

: "${S3_BUCKET:?S3_BUCKET is required — run 'terraform output bucket_name' in infra/}"

if [[ ! -d "$DIST" ]]; then
  printf 'error: %s does not exist. Run ./scripts/build.sh first.\n' "$DIST" >&2
  exit 1
fi

DRY=()
[[ -n "${DRY_RUN:-}" ]] && DRY=(--dryrun)

# ---------------------------------------------------------------------------
# Cache-Control
#
# Two tiers, because this site does not fingerprint its filenames.
#
#   Long-lived   css/, js/ and assets/ — files that change rarely. A day of
#                browser caching, and the deployment invalidates the edge so
#                CloudFront picks up changes immediately.
#
#   Documents    HTML, JSON, robots.txt, sitemap.xml — the entry points.
#                max-age=0, must-revalidate means a browser may keep a copy
#                but must ask before using it, so a deploy is visible on the
#                next request rather than whenever a cache decides.
#
# If the build renamed assets to styles.a1b2c3d4.css, the long-lived tier
# could be "max-age=31536000, immutable": the URL changes when the content
# does, so a stale copy is impossible and revalidation is never needed. That
# is the single biggest performance win available to a static site, and it is
# a build-tooling problem rather than an infrastructure one.
# ---------------------------------------------------------------------------
CACHE_LONG="public, max-age=86400"
CACHE_DOCS="public, max-age=0, must-revalidate"

# The two filter sets are exact complements: every object matches one and only
# one of them. That matters because --delete only removes destination objects
# the filters allow it to see, so between the two passes every object in the
# bucket is accounted for — including files removed from the repository.
DOC_PATTERNS=(--include "*.html" --include "*.json" --include "robots.txt" --include "sitemap.xml")
DOC_EXCLUDES=(--exclude "*.html" --exclude "*.json" --exclude "robots.txt" --exclude "sitemap.xml")

printf 'Deploying %s to s3://%s\n' "$DIST" "$S3_BUCKET"
[[ -n "${DRY_RUN:-}" ]] && printf '  (dry run — nothing will be changed)\n'

printf '\n  → long-lived assets (%s)\n' "$CACHE_LONG"
aws s3 sync "$DIST/" "s3://$S3_BUCKET/" \
  --delete \
  --no-progress \
  "${DRY[@]}" \
  "${DOC_EXCLUDES[@]}" \
  --cache-control "$CACHE_LONG"

printf '\n  → documents (%s)\n' "$CACHE_DOCS"
aws s3 sync "$DIST/" "s3://$S3_BUCKET/" \
  --delete \
  --no-progress \
  "${DRY[@]}" \
  --exclude "*" \
  "${DOC_PATTERNS[@]}" \
  --cache-control "$CACHE_DOCS"

printf '\nUpload complete.\n'
