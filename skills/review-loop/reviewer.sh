#!/usr/bin/env bash
# Runs the other coding agent as a reviewer and writes its reply to a file.
#
#   reviewer.sh <codex|claude> <prompt-file> <output-file> [image ...]
#
# Pass `codex` if you are Claude Code and `claude` if you are Codex. The
# reviewer may run commands but is told not to change the work. Its log goes
# next to the output file, with a .log extension.
set -euo pipefail

if [ $# -lt 3 ]; then
  echo "usage: $0 <codex|claude> <prompt-file> <output-file> [image ...]" >&2
  exit 2
fi
agent="$1"; prompt_file="$2"; out="$3"; shift 3

cd "$(git rev-parse --show-toplevel)"

# Keep the working files under .local/ out of git in repos that don't ignore it themselves.
if ! git check-ignore -q .local 2>/dev/null; then
  exclude="$(git rev-parse --git-path info/exclude)"
  mkdir -p "$(dirname "$exclude")"
  echo "/.local/" >> "$exclude"
fi
mkdir -p "$(dirname "$out")"
prompt="$(cat "$prompt_file")"
log="${out%.*}.log"

# Stop the reviewer from reporting itself to Superset as this workspace's agent.
unset SUPERSET_TERMINAL_ID SUPERSET_TAB_ID SUPERSET_PANE_ID

# stdin is closed on purpose: both CLIs can wait forever on an open one.
case "$agent" in
  codex)
    images=()
    for image in "$@"; do images+=("--image=$image"); done
    codex exec -s workspace-write -c model_reasoning_effort=high \
      ${images[@]+"${images[@]}"} -o "$out" "$prompt" < /dev/null > "$log" 2>&1
    ;;
  claude)
    if [ $# -gt 0 ]; then
      prompt="$prompt"$'\n\nRead each of these screenshots with your file-reading tool:\n'"$(printf -- '- %s\n' "$@")"
    fi
    claude -p "$prompt" --allowedTools "Bash,Read,Grep,Glob" \
      --disallowedTools "Edit,Write,NotebookEdit" < /dev/null > "$out" 2> "$log"
    ;;
  *)
    echo "unknown reviewer '$agent': use codex or claude" >&2
    exit 2
    ;;
esac

if [ ! -s "$out" ]; then
  echo "the reviewer wrote nothing; see $log" >&2
  exit 1
fi
