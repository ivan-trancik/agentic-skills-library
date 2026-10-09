#!/usr/bin/env bash
# Runs Lighthouse's accessibility audit on a page, through npx (the first run
# downloads Lighthouse), and writes the failing checks, with the elements
# each one found, as text a reviewer can read.
#
#   a11y.sh <url> <output-file>
set -euo pipefail

if [ $# -ne 2 ]; then
  echo "usage: $0 <url> <output-file>" >&2
  exit 2
fi
url="$1"; out="$2"
mkdir -p "$(dirname "$out")"
json="$(mktemp)"
trap 'rm -f "$json"' EXIT

npx -y lighthouse@13.5.0 "$url" --only-categories=accessibility --output=json --output-path="$json" \
  --quiet --chrome-flags="--headless=new" > /dev/null
jq -r '"Lighthouse accessibility score: \(.categories.accessibility.score * 100 | round) of 100",
  ([.audits[] | select(.score == 0)] | if length == 0 then "No check failed." else .[] |
    "\n\(.title)", (.details.items[:10][]? | "  - \(.node.selector // "") \(.node.snippet // "" | .[0:160])") end)' \
  "$json" > "$out"
echo "$out"
