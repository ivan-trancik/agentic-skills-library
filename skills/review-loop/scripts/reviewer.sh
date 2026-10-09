#!/usr/bin/env bash
# Runs the other coding agent as a reviewer and writes its reply to a file.
#
#   reviewer.sh [--run-checks] [--schema <file>] <codex|claude> <prompt-file> <output-file> [image ...]
#
# Pass `codex` if you are Claude Code and `claude` if you are Codex. Relative
# paths are taken from the repository root. The log goes next to the output
# file, with a .log extension, and so does a record of the run, with a
# .run.json extension: the harness, whether checks were allowed, the seconds
# it took, when it finished, whether the deadline fired, and its cost or token counts.
#
# With --schema, the reviewer must reply with JSON that matches the schema in
# that file, and the output file holds that JSON.
#
# Without --run-checks the reviewer is read-only, which is what plan and design
# reviews need. With it, the reviewer may also run the project's checks, listed
# one per line in .local/review-checks; a line with a `*` is skipped, because
# Claude Code reads `*` in a rule as a wildcard. Checks can write files, and the Codex
# reviewer then runs in a sandbox that can write in the repository, so in that
# mode state.sh's fingerprint is what catches a change to the work.
#
#   REVIEWER_EFFORT   reasoning effort; unset, each harness uses its own setting
#   REVIEWER_TIMEOUT  seconds before the reviewer is stopped; default 480
set -euo pipefail

usage="usage: $0 [--run-checks] [--schema <file>] <codex|claude> <prompt-file> <output-file> [image ...]"
run_checks=0 schema=""
while [ $# -gt 0 ]; do
  case "$1" in
    --run-checks) run_checks=1; shift ;;
    --schema)
      if [ $# -lt 2 ]; then echo "$usage" >&2; exit 2; fi
      schema="$2"; shift 2 ;;
    *) break ;;
  esac
done
if [ $# -lt 3 ]; then
  echo "$usage" >&2
  exit 2
fi
agent="$1"; prompt_file="$2"; out="$3"; shift 3
timeout="${REVIEWER_TIMEOUT:-480}"
# Zero would switch the deadline off: alarm(0) cancels the alarm.
if ! [ "$timeout" -gt 0 ] 2>/dev/null; then
  echo "REVIEWER_TIMEOUT must be a whole number of seconds, at least 1" >&2
  exit 2
fi

cd "$(git rev-parse --show-toplevel)"

# Keep the working files under .local/ out of git in repos that don't ignore it themselves.
if ! git check-ignore -q .local 2>/dev/null; then
  exclude="$(git rev-parse --git-path info/exclude)"
  mkdir -p "$(dirname "$exclude")"
  echo "/.local/" >> "$exclude"
fi

absolute() { case "$1" in /*) echo "$1" ;; *) echo "$PWD/$1" ;; esac; }
out="$(absolute "$out")"
name="$(basename "$out")"
log="$(dirname "$out")/${name%.*}.log"
record="$(dirname "$out")/${name%.*}.run.json"
if [ -n "$schema" ]; then
  schema="$(absolute "$schema")"
  if [ ! -f "$schema" ]; then echo "no schema at $schema" >&2; exit 2; fi
fi
images=()
for image in "$@"; do images+=("$(absolute "$image")"); done
prompt="$(cat "$prompt_file")"
mkdir -p "$(dirname "$out")"
rm -f "$out" "$record"
: > "$log"
# What the run record reports; the run functions fill these in as JSON values.
deadline=false cost=null tokens=null

# Stop the reviewer from reporting itself to Superset as this workspace's agent.
unset SUPERSET_TERMINAL_ID SUPERSET_TAB_ID SUPERSET_PANE_ID

# Runs a command in a process group of its own and stops the whole group once
# the deadline passes, returning 124. Stopping only the command would not be
# enough: the Superset `codex` wrapper runs the real binary as a child.
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

# The Claude reviewer ignores every settings file, so that no allow rule in
# them can open the shell to it. This passes on the user's choice of model and
# effort, and nothing else.
user_model_settings() {
  local file="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
  if [ -f "$file" ]; then
    jq -c '{model, effortLevel, modelSettings} | with_entries(select(.value != null))
      | select(length > 0)' "$file" 2>/dev/null || true
  fi
}

# stdin is closed on purpose: both CLIs can wait forever on an open one.
run_codex() {
  local sandbox=read-only status=0 session image
  if [ "$run_checks" = 1 ]; then sandbox=workspace-write; fi
  local args=(exec -s "$sandbox" --json -o "$out") schema_args=()
  if [ -n "$schema" ]; then schema_args=(--output-schema "$schema"); fi
  if [ -n "${REVIEWER_EFFORT:-}" ]; then args+=(-c "model_reasoning_effort=$REVIEWER_EFFORT"); fi
  for image in ${images[@]+"${images[@]}"}; do args+=("--image=$image"); done
  with_deadline "$timeout" codex "${args[@]}" ${schema_args[@]+"${schema_args[@]}"} "$prompt" \
    < /dev/null >> "$log" 2>&1 || status=$?

  if [ "$status" -eq 124 ]; then
    # Out of time: resume the session once and ask for what it has.
    deadline=true
    echo "the reviewer passed its ${timeout}-second deadline; asking it for its findings so far" >&2
    session="$(jq -rnR 'first(inputs | fromjson? | objects
      | select(.type == "thread.started") | .thread_id)' "$log")"
    if [ -n "$session" ]; then
      with_deadline 90 codex exec -s "$sandbox" resume "$session" \
        -c model_reasoning_effort=medium --json -o "$out" ${schema_args[@]+"${schema_args[@]}"} \
        "Your time is up. Reply now with your complete findings so far, in the format you were asked for." \
        < /dev/null >> "$log" 2>&1 || true
    fi
  fi
  tokens="$(jq -cnR '[inputs | fromjson? | objects | select(.type == "turn.completed") | .usage]
    | if length == 0 then null else {input: (map(.input_tokens // 0) | add),
      cached: (map(.cached_input_tokens // 0) | add), output: (map(.output_tokens // 0) | add)} end' "$log")"
}

run_claude() {
  local tools="Read,Grep,Glob" rules=() status=0 check json
  if [ "$run_checks" = 1 ]; then
    tools="Read,Grep,Glob,Bash"
    if [ -f .local/review-checks ]; then
      # Exact commands only: a rule such as Bash(npm test *) would also allow
      # `npm test -- --updateSnapshot`, and a `*` can't be escaped.
      while IFS= read -r check || [ -n "$check" ]; do
        case "$check" in
          '') ;;
          *'*'*) echo "skipped a check with a *, which a rule would read as a wildcard: $check" >&2 ;;
          *) rules+=("Bash($check)") ;;
        esac
      done < .local/review-checks
    else
      echo "no .local/review-checks, so the reviewer can't run the project's checks" >&2
    fi
  fi
  if [ ${#images[@]} -gt 0 ]; then
    prompt="$prompt"$'\n\nRead each of these screenshots with your file-reading tool:\n'"$(printf -- '- %s\n' "${images[@]}")"
  fi

  local args=(-p "$prompt" --restricted --safe-mode --strict-mcp-config --no-session-persistence
    --permission-mode dontAsk --permission-prompts none --max-budget-usd 5
    --output-format json --tools "$tools")
  local settings
  settings="$(user_model_settings)"
  if [ -n "$settings" ]; then args+=(--settings "$settings"); fi
  if [ -n "${REVIEWER_EFFORT:-}" ]; then args+=(--effort "$REVIEWER_EFFORT"); fi
  if [ -n "$schema" ]; then args+=(--json-schema "$(cat "$schema")"); fi
  if [ ${#rules[@]} -gt 0 ]; then args+=(--allowedTools "${rules[@]}"); fi

  json="$(mktemp)"
  with_deadline "$timeout" claude "${args[@]}" < /dev/null > "$json" 2>> "$log" || status=$?
  cat "$json" >> "$log"
  if [ "$status" -eq 124 ]; then
    deadline=true
    echo "the reviewer passed its ${timeout}-second deadline and was stopped" >&2
  elif jq -e '.is_error == false' "$json" > /dev/null 2>&1; then
    if [ -n "$schema" ]; then
      jq '.structured_output // empty' "$json" > "$out"
    else
      jq -r '.result // empty' "$json" > "$out"
    fi
  fi
  cost="$(jq '.total_cost_usd // null' "$json" 2> /dev/null || true)"
  cost="${cost:-null}"
  tokens="$(jq -c '.usage // empty | {input: (.input_tokens // 0),
    cached: ((.cache_read_input_tokens // 0) + (.cache_creation_input_tokens // 0)),
    output: (.output_tokens // 0)}' "$json" 2> /dev/null || true)"
  tokens="${tokens:-null}"
  rm -f "$json"
}

started="$(date +%s)"
case "$agent" in
  codex) run_codex ;;
  claude) run_claude ;;
  *)
    echo "unknown reviewer '$agent': use codex or claude" >&2
    exit 2
    ;;
esac
jq -n --arg harness "$agent" --argjson checks "$([ "$run_checks" = 1 ] && echo true || echo false)" \
  --argjson seconds "$(( $(date +%s) - started ))" --argjson finished "$(date +%s)" --argjson deadline "$deadline" \
  --argjson cost "$cost" --argjson tokens "$tokens" \
  '{harness: $harness, checks: $checks, seconds: $seconds, finished: $finished, deadline: $deadline,
    cost_usd: $cost, tokens: $tokens}' \
  > "$record"

if [ ! -s "$out" ]; then
  echo "the reviewer wrote nothing; see $log" >&2
  exit 1
fi
