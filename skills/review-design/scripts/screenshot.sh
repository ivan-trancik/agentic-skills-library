#!/usr/bin/env bash
# Takes the screenshots a design review needs, in one Chrome session, with
# Playwright through npx; the first run downloads Playwright.
#
#   screenshot.sh <url> <folder>                  take the screenshots into the folder
#   screenshot.sh --check <folder> <review-file>  check that the review names the canary word
#
# The images: canary.png, a random word the reviewer must read back; desktop.png
# at 1440 x 900; full-1.png onwards, the whole page at 1440 wide in tiles 900
# px tall, at most twelve; tablet.png at 768 x 1024; phone.png as a Pixel 7;
# dark.png at 1440 x 900 with dark mode asked for; and focus.png at 1440 x 900
# after one Tab press. shots.txt lists them in order with what each shows, and
# the script prints their paths in that order. Only a hash of the canary word
# is kept, so the reviewer can learn the word from the image alone.
set -euo pipefail

usage="usage: $0 <url> <folder> | $0 --check <folder> <review-file>"
playwright=playwright@1.63.0
tile=900
max_tiles=12

if [ "${1:-}" = --check ]; then
  if [ $# -ne 3 ]; then echo "$usage" >&2; exit 2; fi
  word="$(grep -o -m 1 'CANARY: *[A-Za-z]*' "$3" | sed 's/CANARY: *//' | tr '[:lower:]' '[:upper:]' || true)"
  if [ -n "$word" ] && [ "$(printf '%s' "$word" | shasum | cut -d' ' -f1)" = "$(cat "$2/canary.sha" 2> /dev/null)" ]; then
    echo "the reviewer read the canary word, so it saw the images"
    exit 0
  fi
  echo "the review doesn't name the canary word, so the reviewer may not have seen the images" >&2
  exit 1
fi
if [ $# -ne 2 ]; then echo "$usage" >&2; exit 2; fi
url="$1"; folder="$2"

# Keep the working files under .local/ out of git in repos that don't ignore it themselves.
if git rev-parse --show-toplevel >/dev/null 2>&1 && ! git check-ignore -q .local 2>/dev/null; then
  exclude="$(git rev-parse --git-path info/exclude)"
  mkdir -p "$(dirname "$exclude")"
  echo "/.local/" >> "$exclude"
fi

if [ ! -x "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" ]; then
  echo "Google Chrome isn't installed; take the screenshots with your own browser tools" >&2
  exit 1
fi
mkdir -p "$folder"
folder="$(cd "$folder" && pwd)"
rm -f "$folder"/*.png "$folder/shots.txt" "$folder/canary.sha"

word="$(awk 'length($0) >= 6 && length($0) <= 9 && $0 ~ /^[a-z]+$/' /usr/share/dict/words 2> /dev/null \
  | awk -v seed="$RANDOM$RANDOM" 'BEGIN { srand(seed) } { words[n++] = $0 } END { if (n) print words[int(rand() * n)] }' \
  | tr '[:lower:]' '[:upper:]')"
if [ -z "$word" ]; then word="$(LC_ALL=C tr -dc '[:upper:]' < /dev/urandom | head -c 8 || true)"; fi
printf '%s' "$word" | shasum | cut -d' ' -f1 > "$folder/canary.sha"

# npx puts Playwright's bin folder on PATH; the module sits one level up.
script="$(cd "$(dirname "$0")" && pwd)/capture.cjs"
# shellcheck disable=SC2016 # the inner shell expands these
report="$(CANARY_WORD="$word" npx -y -p "$playwright" -- sh -c \
  'NODE_PATH="$(dirname "$(command -v playwright)")/.." node "$0" "$1" "$2"' "$script" "$url" "$folder")"
focused="$(printf '%s\n' "$report" | tail -n 1 | jq -r '.focused')"

{
  echo "canary.png: a test word; write it on the first line of your reply"
  echo "desktop.png: the page at 1440 x 900"
} > "$folder/shots.txt"
height="$(sips -g pixelHeight "$folder/full.png" | awk '/pixelHeight/ { print $2 }')"
n=0
while [ "$n" -lt "$max_tiles" ] && [ $(( n * tile )) -lt "$height" ]; do
  top=$(( n * tile )); rows=$(( height - top < tile ? height - top : tile ))
  n=$(( n + 1 ))
  sips -c "$rows" 1440 --cropOffset "$top" 0 "$folder/full.png" --out "$folder/full-$n.png" > /dev/null
  echo "full-$n.png: the whole page at 1440 wide, from $top to $(( top + rows )) px" >> "$folder/shots.txt"
done
rm -f "$folder/full.png"
{
  echo "tablet.png: the page at 768 x 1024"
  echo "phone.png: the page on a Pixel 7"
  echo "dark.png: the page at 1440 x 900 with dark mode asked for; it matches desktop.png if the page has no dark mode"
  echo "focus.png: the page at 1440 x 900 after one Tab press, which focused $focused"
} >> "$folder/shots.txt"
if [ $(( n * tile )) -lt "$height" ]; then
  echo "The page is $height px tall, and no tile covers $(( n * tile )) to $height px." >> "$folder/shots.txt"
  echo "the page is $height px tall; no tile covers $(( n * tile )) to $height px" >&2
fi
sed 's/:.*//' "$folder/shots.txt" | grep '\.png$' | sed "s|^|$folder/|"
