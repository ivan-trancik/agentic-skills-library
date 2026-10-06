#!/usr/bin/env bash
# Prints the size and a fingerprint of the uncommitted work: tracked changes
# against HEAD, plus untracked files that git doesn't ignore.
#
#   lines        added + removed lines in tracked files, plus lines in untracked files
#   fingerprint  changes whenever any of that content changes
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

# Keep the working files under .local/ out of git in repos that don't ignore it themselves.
if ! git check-ignore -q .local 2>/dev/null; then
  exclude="$(git rev-parse --git-path info/exclude)"
  mkdir -p "$(dirname "$exclude")"
  echo "/.local/" >> "$exclude"
fi

tracked="$(git diff HEAD --numstat | awk '{ n += $1 + $2 } END { print n + 0 }')"

untracked=0
while IFS= read -r -d '' file; do
  [ -f "$file" ] && untracked=$(( untracked + $(wc -l < "$file") ))
done < <(git ls-files --others --exclude-standard -z)

fingerprint="$(
  {
    git diff HEAD
    git ls-files --others --exclude-standard -z | xargs -0 shasum 2>/dev/null || true
  } | shasum | cut -d' ' -f1
)"

echo "lines=$(( tracked + untracked )) fingerprint=$fingerprint"
