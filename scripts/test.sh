#!/usr/bin/env bash
#
# Static site checks.
#
# These are deliberately cheap and dependency-free: they run in under a second
# on a laptop and inside a GitHub Actions runner without installing anything.
# The goal is not exhaustive coverage, it is to catch the mistakes that would
# otherwise be discovered by a visitor after the site is already live.
#
#   ./scripts/test.sh
#
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Colours only when attached to a terminal, so CI logs stay clean.
if [[ -t 1 ]]; then
  RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; DIM=$'\033[2m'; BOLD=$'\033[1m'; OFF=$'\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; DIM=''; BOLD=''; OFF=''
fi

PASS=0; FAIL=0; SKIP=0

pass() { PASS=$((PASS+1)); printf '  %s✓%s %s\n' "$GREEN" "$OFF" "$1"; }
fail() { FAIL=$((FAIL+1)); printf '  %s✗%s %s\n' "$RED" "$OFF" "$1"; [[ $# -gt 1 ]] && printf '      %s%s%s\n' "$DIM" "$2" "$OFF"; }
skip() { SKIP=$((SKIP+1)); printf '  %s–%s %s %s(skipped)%s\n' "$YELLOW" "$OFF" "$1" "$DIM" "$OFF"; }
group() { printf '\n%s%s%s\n' "$BOLD" "$1" "$OFF"; }

# ---------------------------------------------------------------------------
group "Required files"
# ---------------------------------------------------------------------------
for f in index.html 404.html css/styles.css js/app.js assets/icons/favicon.svg .gitignore README.md; do
  if [[ -f "$f" ]]; then pass "$f exists"; else fail "$f is missing"; fi
done

# ---------------------------------------------------------------------------
group "HTML structure"
# ---------------------------------------------------------------------------
for page in index.html 404.html; do
  [[ -f "$page" ]] || continue
  html="$(cat "$page")"

  grep -qi '^<!DOCTYPE html>' "$page" \
    && pass "$page declares the HTML5 doctype" \
    || fail "$page is missing <!DOCTYPE html>"

  grep -q '<html lang="' "$page" \
    && pass "$page declares a language" \
    || fail "$page is missing a lang attribute" "Screen readers need it to choose a voice."

  grep -q '<meta name="viewport"' "$page" \
    && pass "$page sets a viewport" \
    || fail "$page has no viewport meta tag" "The layout will not adapt on mobile."

  grep -q '<title>' "$page" \
    && pass "$page has a title" \
    || fail "$page has no <title>"

  h1_count=$(grep -c '<h1' "$page")
  if [[ "$h1_count" -eq 1 ]]; then
    pass "$page has exactly one <h1>"
  else
    fail "$page has $h1_count <h1> elements" "Exactly one top-level heading is expected."
  fi
done

grep -q '<meta name="description"' index.html \
  && pass "index.html has a meta description" \
  || fail "index.html has no meta description"

# Duplicate element ids break both CSS and querySelector lookups.
dupes=$(grep -o 'id="[^"]*"' index.html | sort | uniq -d)
if [[ -z "$dupes" ]]; then
  pass "index.html has no duplicate element ids"
else
  fail "index.html has duplicate ids" "$(echo "$dupes" | tr '\n' ' ')"
fi

# ---------------------------------------------------------------------------
group "Internal references resolve"
# ---------------------------------------------------------------------------
missing=$(python3 - <<'PY'
import re, pathlib, sys

root = pathlib.Path('.')
missing = []

for page in ('index.html', '404.html'):
    p = root / page
    if not p.exists():
        continue
    html = p.read_text(encoding='utf-8')
    # href/src values that point at files we ship (skip anchors, mail, http, data)
    for attr in ('href', 'src'):
        for value in re.findall(rf'{attr}="([^"]+)"', html):
            if value.startswith(('#', 'http://', 'https://', 'mailto:', 'data:', '//')):
                continue
            target = root / value.lstrip('/')
            if not target.exists():
                missing.append(f'{page}: {value}')

# Also check url(...) references inside the stylesheet.
css = root / 'css/styles.css'
if css.exists():
    for value in re.findall(r'url\(["\']?([^"\')]+)["\']?\)', css.read_text(encoding='utf-8')):
        if value.startswith(('http', 'data:', '#')):
            continue
        target = (css.parent / value).resolve()
        if not target.exists():
            missing.append(f'css/styles.css: {value}')

print('\n'.join(missing))
PY
)
if [[ -z "$missing" ]]; then
  pass "every local href/src points at a file that exists"
else
  fail "broken internal references" "$(echo "$missing" | tr '\n' '; ')"
fi

# Every <use href="#id"> must have a matching <symbol id="id">.
orphans=$(python3 - <<'PY'
import re, pathlib
html = pathlib.Path('index.html').read_text(encoding='utf-8')
defined = set(re.findall(r'<symbol id="([^"]+)"', html))
used = set(re.findall(r'<use href="#([^"]+)"', html))
print(' '.join(sorted(used - defined)))
PY
)
if [[ -z "$orphans" ]]; then
  pass "every icon reference has a matching <symbol>"
else
  fail "icons referenced but never defined" "$orphans"
fi

# ---------------------------------------------------------------------------
group "JavaScript"
# ---------------------------------------------------------------------------
if command -v node >/dev/null 2>&1; then
  if node --check js/app.js 2>/dev/null; then
    pass "js/app.js parses (node --check)"
  else
    fail "js/app.js has a syntax error" "$(node --check js/app.js 2>&1 | head -3)"
  fi
else
  skip "node --check js/app.js"
fi

grep -q "'use strict'" js/app.js \
  && pass "js/app.js runs in strict mode" \
  || fail "js/app.js is not in strict mode"

grep -q 'prefers-reduced-motion' js/app.js \
  && pass "js/app.js honours prefers-reduced-motion" \
  || fail "js/app.js ignores prefers-reduced-motion" "Animation must be opt-out for motion-sensitive visitors."

# ---------------------------------------------------------------------------
group "Secrets"
# ---------------------------------------------------------------------------
# A cheap tripwire, not a replacement for real secret scanning.
leaks=$(grep -rInE \
  -e 'AKIA[0-9A-Z]{16}' \
  -e 'aws_secret_access_key[[:space:]]*=' \
  -e 'BEGIN [A-Z ]*PRIVATE KEY' \
  --include='*.html' --include='*.css' --include='*.js' --include='*.tf' \
  --include='*.yml' --include='*.yaml' --include='*.sh' --include='*.md' \
  . 2>/dev/null | grep -v 'scripts/test.sh' || true)
if [[ -z "$leaks" ]]; then
  pass "no obvious credentials in tracked file types"
else
  fail "possible credential material found" "$(echo "$leaks" | head -3)"
fi

# ---------------------------------------------------------------------------
group "Served over HTTP"
# ---------------------------------------------------------------------------
PORT="${TEST_PORT:-8099}"
if command -v curl >/dev/null 2>&1; then
  python3 -m http.server "$PORT" --bind 127.0.0.1 >/dev/null 2>&1 &
  SERVER_PID=$!
  trap 'kill "$SERVER_PID" 2>/dev/null || true' EXIT

  # Wait for the socket rather than sleeping a fixed amount.
  for _ in $(seq 1 40); do
    curl -fsS -o /dev/null "http://127.0.0.1:$PORT/" 2>/dev/null && break
    sleep 0.1
  done

  base="http://127.0.0.1:$PORT"
  for path in / /css/styles.css /js/app.js /404.html /assets/icons/favicon.svg; do
    code=$(curl -s -o /dev/null -w '%{http_code}' "$base$path")
    [[ "$code" == "200" ]] && pass "GET $path → 200" || fail "GET $path → $code"
  done

  body=$(curl -s "$base/")
  grep -q 'Cloud Launchpad' <<<"$body" \
    && pass "homepage contains the expected brand name" \
    || fail "homepage did not render the expected content"
  grep -q 'CloudFront' <<<"$body" \
    && pass "homepage explains the architecture" \
    || fail "homepage is missing its architecture copy"

  kill "$SERVER_PID" 2>/dev/null || true
  trap - EXIT
else
  skip "HTTP smoke test (curl not installed)"
fi

# ---------------------------------------------------------------------------
printf '\n%s%d passed, %d failed, %d skipped%s\n\n' "$BOLD" "$PASS" "$FAIL" "$SKIP" "$OFF"
[[ "$FAIL" -eq 0 ]] || exit 1
