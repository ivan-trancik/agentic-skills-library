#!/usr/bin/env bash
# Runs Gemini 4 Argon through agy, the Antigravity CLI, on a brief and the
# files it is about, and writes Argon's answer to a file.
#
#   ask.sh <--media|--second-opinion> <brief-file> <answer-file> [file ...]
#
# Argon runs in a throwaway folder under /tmp that holds copies of the files
# and nothing else. The session's settings deny every file write, command, URL
# fetch and MCP call, and every read under /Users, /Volumes and $HOME, and keep
# the request-review mode, in which headless agy refuses anything else it would
# have to ask about, such as a read outside its folder. So Argon can read the
# copies and search the web, and nothing of the repository, the builder's notes
# or the user's files. The fixed instructions for the job, from the skill
# folder, come before the brief.
#
# The answer is written only when Argon answered, the run succeeded or was cut
# off by agy's own time limit, and Argon opened every file. Next to the answer
# go a record of the run, with a .run.json extension: the job, the model, the
# seconds it took, when it finished, whether the deadline fired, agy's status,
# why the turn ended early if it did, the conversation, the tokens, and the
# files Argon didn't open; and a log, with a .log extension: agy's messages and
# its stream.
#
#   GEMINI_MODEL    the model; unset, gemini-4-argon-medium for --media and
#                   gemini-4-argon-high for --second-opinion
#   GEMINI_TIMEOUT  seconds before Argon is stopped; default 480
set -euo pipefail

usage="usage: $0 <--media|--second-opinion> <brief-file> <answer-file> [file ...]"
if [ $# -lt 3 ]; then
  echo "$usage" >&2
  exit 2
fi
case "$1" in
  --media) job=media model="${GEMINI_MODEL:-gemini-4-argon-medium}" ;;
  --second-opinion) job=second-opinion model="${GEMINI_MODEL:-gemini-4-argon-high}" ;;
  *) echo "$usage" >&2; exit 2 ;;
esac
brief="$2" out="$3"
shift 3
timeout="${GEMINI_TIMEOUT:-480}"
# Zero would switch the deadline off: alarm(0) cancels the alarm.
if ! [ "$timeout" -gt 0 ] 2>/dev/null; then
  echo "GEMINI_TIMEOUT must be a whole number of seconds, at least 1" >&2
  exit 2
fi
if [ ! -s "$brief" ]; then echo "no brief at $brief" >&2; exit 2; fi
for file in "$@"; do
  if [ ! -f "$file" ]; then echo "no file at $file" >&2; exit 2; fi
done

# The session pins request-review, but nothing shows that a session setting
# beats the global file, and always-proceed there would let Argon read outside
# its folder.
global="$HOME/.gemini/antigravity-cli/settings.json"
if [ -f "$global" ] && jq -e '.toolPermission == "always-proceed"' "$global" > /dev/null 2>&1; then
  echo "$global sets toolPermission to always-proceed, which would let Argon read files outside its folder; change that setting first" >&2
  exit 2
fi

# Keep the working files under .local/ out of git in repos that don't ignore it
# themselves. A sandbox may keep .git read-only, and that is no reason to stop.
root="$(git rev-parse --show-toplevel 2> /dev/null || true)"
if [ -n "$root" ] && ! git -C "$root" check-ignore -q .local 2>/dev/null; then
  exclude="$(git -C "$root" rev-parse --git-path info/exclude)"
  case "$exclude" in /*) ;; *) exclude="$root/$exclude" ;; esac
  { mkdir -p "$(dirname "$exclude")" && echo "/.local/" >> "$exclude"; } 2> /dev/null \
    || echo "warning: couldn't add /.local/ to $exclude, so git may list .local/" >&2
fi

absolute() { case "$1" in /*) echo "$1" ;; *) echo "$PWD/$1" ;; esac; }
out="$(absolute "$out")"
name="$(basename "$out")"
log="$(dirname "$out")/${name%.*}.log"
record="$(dirname "$out")/${name%.*}.run.json"
skill="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$(dirname "$out")"
rm -f "$out" "$record"
: > "$log"

folder="$(mktemp -d /tmp/ask-gemini.XXXXXX)"
work="$(mktemp -d)"
trap 'rm -rf "$folder" "$work"' EXIT

# Clones on APFS, so a large video costs no time or space; a plain copy elsewhere.
names=()
for file in "$@"; do
  base="$(basename "$file")" copy="$(basename "$file")" n=1
  while [ -e "$folder/$copy" ]; do n=$((n + 1)); copy="$n-$base"; done
  cp -c "$file" "$folder/$copy" 2> /dev/null || cp "$file" "$folder/$copy"
  names+=("$copy")
done

prompt="$(cat "$skill/$job-prompt.md")"
if [ ${#names[@]} -gt 0 ]; then
  prompt="$prompt"$'\n\n'"The files, in your current folder:"$'\n'"$(printf -- '- %s\n' "${names[@]}")"
else
  prompt="$prompt"$'\n\n'"There are no files: work from the brief alone."
fi
prompt="$prompt"$'\n\n'"## The brief"$'\n\n'"$(cat "$brief")"

settings="$(jq -cn --arg home "${HOME%/}" '{toolPermission: "request-review", permissions: {deny: ([
  "command(*)", "write_file(*)", "read_url(*)", "execute_url(*)", "mcp(*)",
  "read_file(/Users/)", "read_file(/Volumes/)", "read_file(\($home)/)"] | unique)}}')"
# agy's own limit comes first, so that a slow answer comes back cut off rather than not at all.
print_timeout="$timeout"
if [ "$timeout" -gt 60 ]; then print_timeout=$((timeout - 30)); fi

# Runs a command in a process group of its own and stops the whole group once
# the deadline passes, returning 124. The same as in reviewer.sh: agy -p has
# been known to hang without output when it isn't run in a terminal.
with_deadline() {
  perl -MPOSIX=:sys_wait_h -e '
    my $seconds = shift;
    defined(my $pid = fork) or die "fork: $!\n";
    if ($pid == 0) { setpgrp(0, 0); exec @ARGV or die "cannot run $ARGV[0]: $!\n" }
    setpgrp($pid, $pid);
    sub stop {
      kill "-TERM", $pid;
      for (1 .. 50) {
        waitpid($pid, WNOHANG);
        last unless kill "ZERO", -$pid;
        select(undef, undef, undef, 0.1);
      }
      kill "-KILL", $pid;
      exit shift;
    }
    $SIG{ALRM} = sub { stop(124) };
    $SIG{$_} = sub { stop(130) } for qw(INT TERM HUP);
    alarm $seconds;
    1 while waitpid($pid, 0) < 0 && $!{EINTR};
    exit($? & 127 ? 128 + ($? & 127) : $? >> 8);
  ' "$@"
}

# Stop the run from reporting itself to Superset as this workspace's agent.
unset SUPERSET_TERMINAL_ID SUPERSET_TAB_ID SUPERSET_PANE_ID

started="$(date +%s)" status=0 deadline=false
# stdin is closed on purpose, and the prompt comes last: -p takes the word after it.
(cd "$folder" && with_deadline "$timeout" agy --model "$model" --output-format stream-json \
  --disable-slash-commands --sandbox --settings "$settings" --print-timeout "${print_timeout}s" \
  -p "$prompt") < /dev/null > "$work/stream" 2> "$work/stderr" || status=$?
cat "$work/stderr" "$work/stream" >> "$log"
if [ "$status" -eq 124 ]; then deadline=true; fi

result="$(jq -cR 'fromjson? | objects | select(.event == "result") | .result' "$work/stream" | tail -n 1)"
result="${result:-null}"
# A file counts as opened when a finished tool step names its path.
opened="$(jq -rR 'fromjson? | objects | select(.event == "step_update") | .step_update
  | select(.step_type == "tool" and .state == "DONE") | .tool_info.parameters // {} | .. | strings' "$work/stream")"
real="$(cd "$folder" && pwd -P)"
missing=()
for copy in ${names[@]+"${names[@]}"}; do
  if ! printf '%s\n' "$opened" | grep -qxF -e "$folder/$copy" -e "$real/$copy" -e "$copy" -e "./$copy"; then
    missing+=("$copy")
  fi
done

jq -n --arg job "$job" --arg model "$model" --argjson seconds "$(( $(date +%s) - started ))" \
  --argjson finished "$(date +%s)" --argjson deadline "$deadline" --argjson result "$result" \
  --argjson files "${#names[@]}" --argjson missing "$(jq -cn '$ARGS.positional' --args ${missing[@]+"${missing[@]}"})" \
  '{harness: "agy", job: $job, model: $model, seconds: $seconds, finished: $finished, deadline: $deadline,
    status: ($result.status // null), finished_reason: ($result.finished_reason // null),
    conversation_id: ($result.conversation_id // null),
    tokens: ($result.usage // null | if . == null then null else {input: (.input_tokens // 0),
      cached: (.cache_read_tokens // 0), output: (.output_tokens // 0), thinking: (.thinking_tokens // 0)} end),
    files: $files, not_opened: $missing}' \
  > "$record"

if [ "$deadline" = true ]; then
  echo "Argon passed its ${timeout}-second deadline and was stopped; see $log" >&2
  exit 1
fi
if [ "$result" = null ]; then
  echo "agy gave no result: $(head -c 400 "$work/stderr"); see $log" >&2
  exit 1
fi
run_status="$(jq -r '.status // ""' <<< "$result")"
reason="$(jq -r '.finished_reason // ""' <<< "$result")"
response="$(jq -r '.response // ""' <<< "$result")"
if [ "$run_status" != SUCCESS ] && [ "$reason" != print_timeout ]; then
  echo "Argon's run ended with status ${run_status:-none}: $(jq -r '(.error // "") | if type == "string" then . else tojson end' <<< "$result"); see $log" >&2
  exit 1
fi
if [ -z "$response" ]; then
  echo "Argon gave no answer. agy said: $(head -c 400 "$work/stderr"); see $log" >&2
  exit 1
fi
if [ ${#missing[@]} -gt 0 ]; then
  echo "Argon didn't open $(printf '%s, ' "${missing[@]}" | sed 's/, $//'), so its answer isn't used; see $log" >&2
  exit 1
fi
printf '%s\n' "$response" > "$out"
if [ -n "$reason" ]; then
  echo "warning: Argon's answer was cut off ($reason); say so when you report it" >&2
fi
