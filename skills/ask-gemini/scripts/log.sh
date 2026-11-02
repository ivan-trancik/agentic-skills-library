#!/usr/bin/env bash
# Appends one line about a Gemini job to a log that outlives the workspace:
# the time, the repository and branch, the job, whether Argon ran headless
# ("cli") or in Google's app ("app"), whether it found something the builder
# had missed, and how many of its claims had to be corrected. Pass the answer
# file of a headless run, and the line also takes the model, seconds and
# tokens from the run's record next to it. A month of these lines shows
# whether Argon earns its place. The log is
# ${XDG_STATE_HOME:-~/.local/state}/agentic-skills-library/ask-gemini.jsonl.
#
#   log.sh --job <media|second-opinion|gmail-drive|notebook> --added <yes|no> --corrections N [--answer <file>]
set -euo pipefail

usage="usage: $0 --job <media|second-opinion|gmail-drive|notebook> --added <yes|no> --corrections N [--answer <file>]"
job="" added="" corrections="" answer=""
while [ $# -gt 0 ]; do
  if [ $# -lt 2 ]; then echo "$usage" >&2; exit 2; fi
  case "$1" in
    --job) job="$2" ;;
    --added) added="$2" ;;
    --corrections) corrections="$2" ;;
    --answer) answer="$2" ;;
    *) echo "$usage" >&2; exit 2 ;;
  esac
  shift 2
done
case "$job" in media|second-opinion|gmail-drive|notebook) ;; *) echo "$usage" >&2; exit 2 ;; esac
case "$added" in yes) added=true ;; no) added=false ;; *) echo "$usage" >&2; exit 2 ;; esac
case "$corrections" in ''|*[!0-9]*) echo "$usage" >&2; exit 2 ;; esac
corrections=$((10#$corrections))

route=app run='{"model": null, "seconds": null, "tokens": null}'
if [ -n "$answer" ]; then
  name="$(basename "$answer")"
  record="$(dirname "$answer")/${name%.*}.run.json"
  if [ -f "$record" ]; then
    route=cli
    run="$(jq -c '{model, seconds, tokens}' "$record")"
  fi
fi

repo="" branch=""
if root="$(git rev-parse --show-toplevel 2> /dev/null)"; then
  origin="$(git -C "$root" config --get remote.origin.url || true)"
  repo="$(basename "${origin:-$root}" .git)"
  branch="$(git -C "$root" branch --show-current)"
fi
log_dir="${XDG_STATE_HOME:-$HOME/.local/state}/agentic-skills-library"
mkdir -p "$log_dir"
jq -cn --arg time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg repo "$repo" --arg branch "$branch" \
  --arg job "$job" --arg route "$route" --argjson added "$added" --argjson corrections "$corrections" \
  --argjson run "$run" \
  '{time: $time, repo: (if $repo == "" then null else $repo end), branch: (if $branch == "" then null else $branch end),
    job: $job, route: $route, added: $added, corrections: $corrections} + $run' \
  >> "$log_dir/ask-gemini.jsonl"
echo "logged the $job job in $log_dir/ask-gemini.jsonl"
