#!/usr/bin/env bash
# Appends one line about a review round to a log that outlives the workspace:
# what the round found and what became of it, its time and cost, and how many
# of its findings lie in lines that the previous fixes changed.
#
#   log-round.sh --round N --reported N --refuted N --accepted N --rejected N --disputed N
#                [--before <fingerprint> --after <fingerprint>] [--exit <name>]
#
# --before and --after take the snapshots from before and after the previous
# round's fixes, the two that "Fixes to check" names. --exit names how the loop
# ended, when it ended in this round. The time and cost add up the record of
# the round's review, .local/review-round-N.run.json, and the records of the
# runs that followed it in this round, .local/review-round-N.*.run.json; a
# record that finished before the review is left from an earlier loop. The log
# is ${XDG_STATE_HOME:-~/.local/state}/agentic-skills-library/review-loop.jsonl.
set -euo pipefail

usage="usage: $0 --round N --reported N --refuted N --accepted N --rejected N --disputed N [--before <fingerprint> --after <fingerprint>] [--exit <name>]"
round="" reported="" refuted="" accepted="" rejected="" disputed="" before="" after="" exit_name=""
while [ $# -gt 0 ]; do
  if [ $# -lt 2 ]; then echo "$usage" >&2; exit 2; fi
  case "$1" in
    --round) round="$2" ;;
    --reported) reported="$2" ;;
    --refuted) refuted="$2" ;;
    --accepted) accepted="$2" ;;
    --rejected) rejected="$2" ;;
    --disputed) disputed="$2" ;;
    --before) before="$2" ;;
    --after) after="$2" ;;
    --exit) exit_name="$2" ;;
    *) echo "$usage" >&2; exit 2 ;;
  esac
  shift 2
done
for count in "$round" "$reported" "$refuted" "$accepted" "$rejected" "$disputed"; do
  case "$count" in ''|*[!0-9]*) echo "$usage" >&2; exit 2 ;; esac
done
if { [ -n "$before" ] && [ -z "$after" ]; } || { [ -z "$before" ] && [ -n "$after" ]; }; then
  echo "--before and --after go together" >&2
  exit 2
fi

here="$(cd "$(dirname "$0")" && pwd)"
cd "$(git rev-parse --show-toplevel)"
# The size of the work, or null when state.sh can't take it, so that a round
# that ended for that reason can still be logged.
lines=null
if state="$("$here/state.sh" 2> /dev/null)"; then lines="${state#lines=}"; lines="${lines%% *}"; fi

shopt -s nullglob
review=".local/review-round-$round.run.json"
followers=(.local/review-round-"$round".*.run.json)
totals='{"reviewer": null, "seconds": 0, "cost_usd": null, "tokens": null}'
if [ -f "$review" ]; then
  totals="$(jq -cs '.[0].finished as $start | [.[0]] + (.[1:] | map(select(.finished >= $start)))
    | {reviewer: .[0].harness, seconds: (map(.seconds) | add),
       cost_usd: (map(.cost_usd | numbers) | if length == 0 then null else add end),
       tokens: (map(.tokens | objects) | if length == 0 then null
         else {input: (map(.input) | add), cached: (map(.cached) | add), output: (map(.output) | add)} end)}' \
    "$review" ${followers[@]+"${followers[@]}"})"
fi

# A finding lies in a line the previous fixes changed when its line falls in a
# hunk of the diff between the snapshots from before and after those fixes.
in_previous_fix=null
findings=".local/review-round-$round.json"
if [ -n "$before" ] && [ -f "$findings" ]; then
  in_previous_fix=0
  while IFS=$'\t' read -r file line; do
    if git diff -U0 "$before" "$after" -- "$file" | awk -v n="$line" '
      /^@@/ { split($3, range, ","); start = substr(range[1], 2) + 0
              count = (range[2] == "" ? 1 : range[2] + 0); if (count == 0) count = 1
              if (n >= start && n < start + count) hit = 1 }
      END { exit !hit }'; then
      in_previous_fix=$((in_previous_fix + 1))
    fi
  done < <(jq -r '.findings[] | "\(.file)\t\(.line)"' "$findings")
fi

origin="$(git config --get remote.origin.url || true)"
repo="$(basename "${origin:-$PWD}" .git)"
log_dir="${XDG_STATE_HOME:-$HOME/.local/state}/agentic-skills-library"
mkdir -p "$log_dir"
jq -cn --arg time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg repo "$repo" \
  --arg branch "$(git branch --show-current)" --argjson round "$round" \
  --argjson reported "$reported" --argjson refuted "$refuted" --argjson accepted "$accepted" \
  --argjson rejected "$rejected" --argjson disputed "$disputed" \
  --argjson in_previous_fix "$in_previous_fix" --argjson lines "$lines" \
  --arg exit "$exit_name" --argjson totals "$totals" \
  '{time: $time, repo: $repo, branch: $branch, round: $round, reported: $reported, refuted: $refuted,
    accepted: $accepted, rejected: $rejected, disputed: $disputed, in_previous_fix: $in_previous_fix,
    lines: $lines, exit: (if $exit == "" then null else $exit end)} + $totals' \
  >> "$log_dir/review-loop.jsonl"
echo "logged round $round in $log_dir/review-loop.jsonl"
