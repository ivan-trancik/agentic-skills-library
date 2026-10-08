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

# On Windows, a Chrome installed for one user lives under %LOCALAPPDATA%.
user_chrome=""
if [ -n "${LOCALAPPDATA:-}" ] && command -v cygpath > /dev/null 2>&1; then
  user_chrome="$(cygpath -u "$LOCALAPPDATA")/Google/Chrome/Application/chrome.exe"
fi

chrome=""
for candidate in \
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
  "/Applications/Chromium.app/Contents/MacOS/Chromium" \
  "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge" \
  "/c/Program Files/Google/Chrome/Application/chrome.exe" \
  "/c/Program Files (x86)/Google/Chrome/Application/chrome.exe" \
  "$user_chrome" \
  "/c/Program Files (x86)/Microsoft/Edge/Application/msedge.exe" \
  "/c/Program Files/Microsoft/Edge/Application/msedge.exe"; do
  if [ -x "$candidate" ]; then chrome="$candidate"; break; fi
done
if [ -z "$chrome" ]; then
  echo "no Chrome, Chromium or Edge found; take the screenshot with your own browser tools" >&2
  exit 1
fi

mkdir -p "$(dirname "$out")"
out="$(cd "$(dirname "$out")" && pwd)/$(basename "$out")"

# On Windows the browser gets a throwaway profile, so it never shares the user's
# own profile with a browser they have open. Its paths go in Windows form, which
# works whatever MSYS path conversion is set to.
windows=0; shot="$out"; profile=()
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)
    windows=1
    profile_dir="$(mktemp -d)"
    # The browser can still be closing when the script ends, so try a few times.
    trap 'for _ in 1 2 3 4 5; do rm -rf "$profile_dir" 2> /dev/null && break; sleep 1; done' EXIT
    profile=("--user-data-dir=$(cygpath -w "$profile_dir")")
    shot="$(cygpath -w "$out")"
    # A file left by an earlier run would satisfy the wait below.
    rm -f "$out"
    ;;
esac

# The time budget lets the page fetch its data and render before the capture.
"$chrome" --headless=new --disable-gpu --hide-scrollbars \
  ${profile[@]+"${profile[@]}"} \
  --window-size="$width,$height" --virtual-time-budget=8000 \
  --screenshot="$shot" "$url" > /dev/null 2>&1

# On Windows, Edge returns before it has written the file, so wait up to 20
# seconds for the file to appear and stop growing.
if [ "$windows" = 1 ]; then
  last=""
  for _ in $(seq 80); do
    if [ -s "$out" ]; then
      size="$(wc -c < "$out")"
      [ "$size" = "$last" ] && break
      last="$size"
    fi
    sleep 0.25
  done
fi

if [ ! -s "$out" ]; then
  echo "screenshot failed for $url" >&2
  exit 1
fi
if [ "$windows" = 1 ] && [ "$width" -lt 500 ] 2> /dev/null; then
  echo "note: on Windows the browser won't lay a page out narrower than about 500 px, so this image is the left $width px of a wider layout; take narrower shots with your own browser tools if you can" >&2
fi
echo "$out"
