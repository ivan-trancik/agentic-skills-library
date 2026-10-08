#!/usr/bin/env bash
# Runs the two skill validators on every skill: Codex's quick_validate.py and
# the Agent Skills reference validator. Both come through uv at pinned
# versions, so the first run downloads them and the checks in tests/check.sh
# stay offline. Both reject keys that only Claude Code reads, so those are
# removed from a copy of each skill first.
#
#   tests/validate.sh
set -euo pipefail

cd "$(dirname "$0")/.."
quick_validate="$HOME/.codex/skills/.system/skill-creator/scripts/quick_validate.py"
if [ ! -f "$quick_validate" ]; then
  echo "Codex's quick_validate.py is not at $quick_validate; is Codex installed?" >&2
  exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
status=0
for src in skills/*/; do
  name="$(basename "$src")"
  cp -RL "$src" "$tmp/$name"
  awk '/^---$/ { fence++; print; next } fence == 1 && /^disable-model-invocation:/ { next } { print }' \
    "$src/SKILL.md" > "$tmp/$name/SKILL.md"
  if ! uv run --quiet --no-project --with pyyaml==6.0.3 python -I "$quick_validate" "$tmp/$name" > "$tmp/out" 2>&1; then
    echo "FAIL - quick_validate.py $name: $(cat "$tmp/out")"; status=1
  fi
  if ! uvx --quiet --from skills-ref==0.1.1 agentskills validate "$tmp/$name" > "$tmp/out" 2>&1; then
    echo "FAIL - agentskills validate $name: $(cat "$tmp/out")"; status=1
  fi
done
if [ "$status" = 0 ]; then echo "ok - both validators accept every skill"; fi
exit "$status"
