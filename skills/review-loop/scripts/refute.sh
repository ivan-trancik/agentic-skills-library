#!/usr/bin/env bash
# Sends a round's findings that weren't confirmed by running to a fresh,
# read-only reviewer that tries to disprove them, and splits the round's
# findings into those that survive and those it disproved.
#
#   refute.sh <codex|claude> <round-file>
#
# Writes <round>.kept.json, the round with only the surviving findings, and
# <round>.refuted.json, each disproved finding with the reviewer's evidence.
# A finding confirmed by running is kept without asking, and if the refute run
# fails, every finding is kept. Relative paths are taken from the repository root.
set -euo pipefail

if [ $# -ne 2 ]; then
  echo "usage: $0 <codex|claude> <round-file>" >&2
  exit 2
fi
agent="$1"; round="$2"
skill="$(cd "$(dirname "$0")/.." && pwd)"
cd "$(git rev-parse --show-toplevel)"
base="${round%.json}"
input=.local/refute-input.json

keep_all() {
  cp "$round" "$base.kept.json"
  echo '[]' > "$base.refuted.json"
}

mkdir -p .local
jq '[.findings[] | select(.confidence != "confirmed-by-running")]' "$round" > "$input"
if [ "$(jq length "$input")" -eq 0 ]; then keep_all; exit 0; fi

if ! "$skill/scripts/reviewer.sh" --schema "$skill/verdicts.schema.json" "$agent" \
  "$skill/refute-prompt.md" "$base.verdicts.json"; then
  echo "the refute run failed, so every finding is kept" >&2
  keep_all
  exit 0
fi

# The verdicts number the findings in the input from 1.
jq --slurpfile input "$input" '[.verdicts[] | select(.verdict == "refuted")
  | {finding: $input[0][.finding - 1], evidence} | select(.finding != null)]' \
  "$base.verdicts.json" > "$base.refuted.json"
jq --slurpfile refuted "$base.refuted.json" \
  '.findings |= map(. as $f | select(all($refuted[0][]; .finding != $f)))' "$round" > "$base.kept.json"
echo "refuted $(jq length "$base.refuted.json") of the $(jq length "$input") findings it checked"
