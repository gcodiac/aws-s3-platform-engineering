#!/usr/bin/env bash
#
# Verify a deployment against the live site.
#
#   SITE_URL=https://d111111abcdef8.cloudfront.net ./scripts/verify-deployment.sh
#
# Environment:
#   SITE_URL          (required) Public base URL of the deployment.
#   EXPECTED_COMMIT   Commit SHA that should be live. Defaults to HEAD.
#   S3_BUCKET         Bucket name. When set, the script also proves the
#                     bucket cannot be read directly.
#   AWS_REGION        Region of the bucket, for the direct-access check.
#   RETRIES           Attempts while waiting for propagation. Default 10.
#
# A deployment that reports success because `aws s3 sync` exited zero has
# proved that the upload worked. It has not proved that the site is up, that
# the right build is live, that TLS works, or that the origin is still
# private. This checks all four, from outside AWS, over the public internet.
#
set -uo pipefail

: "${SITE_URL:?SITE_URL is required — run 'terraform output site_url' in infra/}"

BASE="${SITE_URL%/}"
EXPECTED_COMMIT="${EXPECTED_COMMIT:-$(git rev-parse HEAD 2>/dev/null || echo unknown)}"
RETRIES="${RETRIES:-10}"

if [[ -t 1 ]]; then
  RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; DIM=$'\033[2m'; BOLD=$'\033[1m'; OFF=$'\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; DIM=''; BOLD=''; OFF=''
fi

PASS=0; FAIL=0; SKIP=0
pass() { PASS=$((PASS+1)); printf '  %s✓%s %s\n' "$GREEN" "$OFF" "$1"; }
fail() { FAIL=$((FAIL+1)); printf '  %s✗%s %s\n' "$RED" "$OFF" "$1"; [[ $# -gt 1 ]] && printf '      %s%s%s\n' "$DIM" "$2" "$OFF"; }
skip() { SKIP=$((SKIP+1)); printf '  %s–%s %s %s(skipped)%s\n' "$YELLOW" "$OFF" "$1" "$DIM" "$OFF"; }

printf '\n%sVerifying %s%s\n' "$BOLD" "$BASE" "$OFF"
printf '%sexpecting build %s%s\n\n' "$DIM" "${EXPECTED_COMMIT:0:7}" "$OFF"

# ---------------------------------------------------------------------------
# Wait for the deployment to be reachable.
#
# CloudFront is eventually consistent: an invalidation that reports Completed
# has propagated to every edge, but DNS for a brand new distribution may still
# be settling. Retry with a backoff instead of failing on the first attempt.
# ---------------------------------------------------------------------------
attempt=1
while :; do
  code=$(curl -fsS -o /dev/null -w '%{http_code}' --max-time 20 "$BASE/" 2>/dev/null || echo 000)
  [[ "$code" == "200" ]] && break
  if (( attempt >= RETRIES )); then
    fail "the site did not become reachable" "last status: $code after $attempt attempts"
    printf '\n%s%d passed, %d failed, %d skipped%s\n\n' "$BOLD" "$PASS" "$FAIL" "$SKIP" "$OFF"
    exit 1
  fi
  printf '  %swaiting for %s (attempt %d, status %s)%s\n' "$DIM" "$BASE" "$attempt" "$code" "$OFF"
  sleep $(( attempt < 5 ? 5 : 15 ))
  attempt=$(( attempt + 1 ))
done
pass "homepage responds with 200"

# Response headers are read from a GET with the body discarded, not from a
# HEAD. CloudFront answers HEAD requests without compressing, so a HEAD would
# report every content negotiation header incorrectly.
HEADERS=$(curl -sS -D - -o /dev/null --max-time 20 -H 'Accept-Encoding: gzip, br' "$BASE/")
BODY=$(curl -sS --max-time 20 "$BASE/")

# ---------------------------------------------------------------------------
# The right build is live
# ---------------------------------------------------------------------------
BUILD_JSON=$(curl -sS --max-time 20 "$BASE/assets/build-info.json" || echo '{}')
LIVE_COMMIT=$(printf '%s' "$BUILD_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("commit",""))' 2>/dev/null || echo '')

if [[ -z "$LIVE_COMMIT" ]]; then
  fail "build-info.json was not readable" "$(printf '%s' "$BUILD_JSON" | head -c 120)"
elif [[ "$LIVE_COMMIT" == "$EXPECTED_COMMIT" ]]; then
  pass "live build is ${LIVE_COMMIT:0:7}, matching the deployed commit"
else
  fail "live build is ${LIVE_COMMIT:0:7}, expected ${EXPECTED_COMMIT:0:7}" \
       "The edge may still be serving a cached copy, or the deployment did not complete."
fi

# ---------------------------------------------------------------------------
# The site is actually the site
# ---------------------------------------------------------------------------
grep -q 'Cloud Launchpad' <<<"$BODY" \
  && pass "homepage contains the expected content" \
  || fail "homepage did not contain the expected content"

# ---------------------------------------------------------------------------
# Transport security
# ---------------------------------------------------------------------------
if [[ "$BASE" == https://* ]]; then
  pass "site is served over HTTPS"

  http_url="http://${BASE#https://}"
  redirect=$(curl -sS -o /dev/null -w '%{http_code} %{redirect_url}' --max-time 20 "$http_url" 2>/dev/null || echo "000 ")
  redirect_code="${redirect%% *}"
  redirect_target="${redirect#* }"
  if [[ "$redirect_code" =~ ^30[128]$ && "$redirect_target" == https://* ]]; then
    pass "plain HTTP redirects to HTTPS ($redirect_code)"
  else
    fail "plain HTTP did not redirect to HTTPS" "got: $redirect"
  fi
else
  skip "HTTPS checks (SITE_URL is not https)"
fi

# ---------------------------------------------------------------------------
# Security headers, set by the CloudFront response headers policy
# ---------------------------------------------------------------------------
check_header() {
  local name="$1"
  if grep -qi "^$name:" <<<"$HEADERS"; then
    pass "$name is present"
  else
    fail "$name is missing" "Check the CloudFront response headers policy."
  fi
}
check_header "strict-transport-security"
check_header "x-content-type-options"
check_header "content-security-policy"
check_header "x-frame-options"

# ---------------------------------------------------------------------------
# Compression
# ---------------------------------------------------------------------------
encoding=$(curl -sS -D - -o /dev/null --max-time 20 -H 'Accept-Encoding: gzip, br' "$BASE/css/styles.css" \
  | grep -i '^content-encoding:' | tr -d '\r' | awk '{print $2}')
if [[ -n "$encoding" ]]; then
  pass "text assets are compressed ($encoding)"
else
  fail "CSS was served uncompressed" "Check that 'compress = true' is set on the cache behaviour."
fi

# ---------------------------------------------------------------------------
# Error handling
# ---------------------------------------------------------------------------
missing=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 20 "$BASE/this-page-does-not-exist")
if [[ "$missing" == "404" ]]; then
  pass "a missing page returns 404"
else
  fail "a missing page returned $missing, expected 404" \
       "A private origin answers with 403; the custom error response should translate it."
fi

# ---------------------------------------------------------------------------
# The origin is still private
#
# The most important check here. Everything above would also pass on a public
# bucket with a CDN in front of it.
# ---------------------------------------------------------------------------
if [[ -n "${S3_BUCKET:-}" ]]; then
  region="${AWS_REGION:-${AWS_DEFAULT_REGION:-}}"
  if [[ -z "$region" ]]; then
    skip "direct S3 access check (AWS_REGION not set)"
  else
    direct=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 20 \
      "https://${S3_BUCKET}.s3.${region}.amazonaws.com/index.html")
    if [[ "$direct" == "403" ]]; then
      pass "direct S3 access is denied (403)"
    elif [[ "$direct" == "200" ]]; then
      fail "THE BUCKET IS PUBLIC — direct S3 access returned 200" \
           "Check aws_s3_bucket_public_access_block and the bucket policy."
    else
      fail "direct S3 access returned $direct, expected 403" "Unexpected, worth investigating."
    fi
  fi
else
  skip "direct S3 access check (S3_BUCKET not set)"
fi

printf '\n%s%d passed, %d failed, %d skipped%s\n\n' "$BOLD" "$PASS" "$FAIL" "$SKIP" "$OFF"
[[ "$FAIL" -eq 0 ]] || exit 1
