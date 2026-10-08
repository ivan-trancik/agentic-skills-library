#!/usr/bin/env bash
# Takes a screenshot of a page with headless Chrome.
#
#   screenshot.sh <url> <output.png> [width] [height]
#
# Defaults to 1440 x 900. Use a tall height, such as 4000, for the whole page.
# It can't click, so use your own browser tools for states that need a click.
set -euo pipefail

if [ $# -lt 2 ]; then
  echo "usage: $0 <url> <output.png> [width] [height]" >&2
  exit 2
fi
url="$1"; out="$2"; width="${3:-1440}"; height="${4:-900}"

# Keep the working files under .local/ out of git in repos that don't ignore it themselves.
if git rev-parse --show-toplevel >/dev/null 2>&1 && ! git check-ignore -q .local 2>/dev/null; then
  exclude="$(git rev-parse --git-path info/exclude)"
  mkdir -p "$(dirname "$exclude")"
  echo "/.local/" >> "$exclude"
fi

chrome=""
for candidate in \
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
  "/Applications/Chromium.app/Contents/MacOS/Chromium" \
  "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge"; do
  if [ -x "$candidate" ]; then chrome="$candidate"; break; fi
done
if [ -z "$chrome" ]; then
  echo "no Chrome, Chromium or Edge found; take the screenshot with your own browser tools" >&2
  exit 1
fi

mkdir -p "$(dirname "$out")"
out="$(cd "$(dirname "$out")" && pwd)/$(basename "$out")"

# The time budget lets the page fetch its data and render before the capture.
"$chrome" --headless=new --disable-gpu --hide-scrollbars \
  --window-size="$width,$height" --virtual-time-budget=8000 \
  --screenshot="$out" "$url" > /dev/null 2>&1

if [ ! -s "$out" ]; then
  echo "screenshot failed for $url" >&2
  exit 1
fi
echo "$out"
