#!/usr/bin/env bash
# Prints the size and a fingerprint of the uncommitted work: tracked changes
# against HEAD, plus untracked files that git doesn't ignore.
#
#   lines        added + removed lines in tracked files, plus lines in untracked files
#   fingerprint  changes whenever any of that content changes
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

# Keep the working files under .local/ out of git in repos that don't ignore it themselves.
# check-ignore can't match /.local/ until the folder exists, so look for the line too.
if ! git check-ignore -q .local 2>/dev/null; then
  exclude="$(git rev-parse --git-path info/exclude)"
  mkdir -p "$(dirname "$exclude")"
  grep -qxF "/.local/" "$exclude" 2>/dev/null || echo "/.local/" >> "$exclude"
fi

tracked="$(git diff HEAD --numstat | awk '{ n += $1 + $2 } END { print n + 0 }')"

untracked=0
while IFS= read -r -d '' file; do
  [ -f "$file" ] && untracked=$(( untracked + $(wc -l < "$file") ))
done < <(git ls-files --others --exclude-standard -z)

# Git Bash puts shasum, a Perl script, on PATH only in a login shell, so a plain
# `bash state.sh` from PowerShell can't find it. sha1sum prints the same lines.
sha=shasum
command -v shasum > /dev/null 2>&1 || sha=sha1sum

fingerprint="$(
  {
    git diff HEAD
    git ls-files --others --exclude-standard -z | xargs -0 "$sha" 2>/dev/null || true
  } | "$sha" | cut -d' ' -f1
)"

echo "lines=$(( tracked + untracked )) fingerprint=$fingerprint"
