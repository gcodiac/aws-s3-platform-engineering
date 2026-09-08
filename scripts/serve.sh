#!/usr/bin/env bash
#
# Serve the static site locally on http://localhost:8080
#
# The site is plain HTML, CSS and JavaScript, so a static file server is all
# that is required. This mirrors how the files will eventually be served from
# S3 through CloudFront: no application server, no build step.
#
set -euo pipefail

PORT="${PORT:-8080}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$ROOT"

printf '\n  Cloud Launchpad\n'
printf '  serving %s\n' "$ROOT"
printf '  http://localhost:%s\n\n  Press Ctrl+C to stop.\n\n' "$PORT"

exec python3 -m http.server "$PORT" --bind 127.0.0.1
