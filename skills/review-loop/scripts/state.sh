#!/usr/bin/env bash
# Prints the size and a fingerprint of the uncommitted work: tracked changes
# against HEAD, plus untracked files that git doesn't ignore.
#
#   lines        added + removed lines in tracked files, plus lines in untracked files
#   fingerprint  the id of a git tree that holds the whole work, untracked files
#                included, so `git diff <one> <another>` shows what changed between two
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

# The tree is written through a copy of the index, so the real index and the
# history stay as they are; the copy keeps git from rereading unchanged files.
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
index="$(git rev-parse --git-path index)"
if [ -f "$index" ]; then cp "$index" "$scratch/index"; fi
GIT_INDEX_FILE="$scratch/index" git add -A
# A tree records a submodule only by its commit. So each submodule's own work
# is written as a tree the same way, and the list of those trees goes into
# this one as a file, at a path the work must not use itself.
# A submodule that can't be snapshotted stops the script: a fingerprint that
# missed its changes would read as unchanged.
# shellcheck disable=SC2016 # git submodule foreach expands these itself
if ! submodules="$(git submodule foreach --recursive --quiet '
  set -e
  scratch="$(mktemp -d)"
  trap "rm -rf \"$scratch\"" EXIT
  index="$(git rev-parse --git-path index)"
  if [ -f "$index" ]; then cp "$index" "$scratch/index"; fi
  GIT_INDEX_FILE="$scratch/index" git add -A
  tree="$(GIT_INDEX_FILE="$scratch/index" git write-tree)"
  echo "$displaypath $tree"')"; then
  echo "state.sh couldn't snapshot a submodule; see the error above" >&2
  exit 1
fi
if [ -n "$submodules" ]; then
  if [ -n "$(GIT_INDEX_FILE="$scratch/index" git ls-files -- .agentic-skills-library)" ]; then
    echo "state.sh needs the path .agentic-skills-library for submodule trees, but the work uses it" >&2
    exit 1
  fi
  blob="$(printf '%s\n' "$submodules" | git hash-object -w --stdin)"
  GIT_INDEX_FILE="$scratch/index" git update-index --add --cacheinfo "100644,$blob,.agentic-skills-library/submodules"
fi
fingerprint="$(GIT_INDEX_FILE="$scratch/index" git write-tree)"

echo "lines=$(( tracked + untracked )) fingerprint=$fingerprint"
