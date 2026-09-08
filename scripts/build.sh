#!/usr/bin/env bash
#
# Assemble the deployable site into dist/
#
# The repository root holds more than the website: Terraform configuration,
# scripts, documentation, screenshots. None of that belongs in a public S3
# bucket. Rather than maintaining a list of things to *exclude* at deploy time
# — which silently ships anything added later — this script copies an explicit
# list of things to *include*.
#
# The output is a build artifact: derived, disposable, and never committed.
#
#   ./scripts/build.sh
#
# Environment:
#   SITE_URL    Public base URL, e.g. https://d111111abcdef8.cloudfront.net
#               When set, a sitemap is generated and referenced from robots.txt.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$ROOT/dist"
cd "$ROOT"

# Everything the browser is allowed to see. Add to this list deliberately.
FILES=(
  index.html
  404.html
  robots.txt
)
DIRS=(
  css
  js
  assets
)

printf 'Building into %s\n' "$DIST"
rm -rf "$DIST"
mkdir -p "$DIST"

for f in "${FILES[@]}"; do
  [[ -f "$f" ]] || { printf 'error: %s is missing\n' "$f" >&2; exit 1; }
  cp "$f" "$DIST/$f"
done

for d in "${DIRS[@]}"; do
  [[ -d "$d" ]] || { printf 'error: %s/ is missing\n' "$d" >&2; exit 1; }
  cp -R "$d" "$DIST/$d"
done

# ---------------------------------------------------------------------------
# Build metadata
#
# The site asks for this file at runtime and prints the result in the footer.
# It is what makes "is my change actually live?" answerable without guessing:
# the deployment verification step fetches it and compares the commit.
# ---------------------------------------------------------------------------
COMMIT="${GITHUB_SHA:-$(git rev-parse HEAD 2>/dev/null || echo unknown)}"
SHORT="${COMMIT:0:7}"
REF="${GITHUB_REF_NAME:-$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)}"
BUILT_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
RUN_URL=""
if [[ -n "${GITHUB_SERVER_URL:-}" && -n "${GITHUB_REPOSITORY:-}" && -n "${GITHUB_RUN_ID:-}" ]]; then
  RUN_URL="${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}"
fi

mkdir -p "$DIST/assets"
cat > "$DIST/assets/build-info.json" <<JSON
{
  "commit": "$COMMIT",
  "shortCommit": "$SHORT",
  "ref": "$REF",
  "builtAt": "$BUILT_AT",
  "runUrl": "$RUN_URL"
}
JSON

# ---------------------------------------------------------------------------
# Environment-specific files
#
# A sitemap has to contain absolute URLs, so it cannot be committed: the same
# commit is deployable to a CloudFront domain today and a custom domain
# tomorrow. Generating it at build time keeps one source of truth.
# ---------------------------------------------------------------------------
if [[ -n "${SITE_URL:-}" ]]; then
  base="${SITE_URL%/}"
  cat > "$DIST/sitemap.xml" <<XML
<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url>
    <loc>$base/</loc>
    <lastmod>${BUILT_AT%%T*}</lastmod>
    <changefreq>weekly</changefreq>
    <priority>1.0</priority>
  </url>
</urlset>
XML
  printf '\nSitemap: %s/sitemap.xml\n' "$base" >> "$DIST/robots.txt"
  printf '  sitemap generated for %s\n' "$base"
else
  printf '  SITE_URL not set — skipping sitemap\n'
fi

printf '  commit %s on %s\n' "$SHORT" "$REF"
printf '  %s files, %s\n' \
  "$(find "$DIST" -type f | wc -l | tr -d ' ')" \
  "$(du -sh "$DIST" | cut -f1)"
printf 'Build complete.\n'
