#!/usr/bin/env bash
# The checks for this repository: syntax, lint and permissions for every
# script, Claude Code's skill validator, tests that run reviewer.sh and
# state.sh against the stub codex and claude commands in tests/stubs, tests
# that run ask.sh against the stub agy, and tests of install.sh against a
# fake home. Free and offline: no model is called, and it runs inside Codex's
# sandbox.
#
#   tests/check.sh
set -euo pipefail

cd "$(dirname "$0")/.."
here="$PWD"

fail() { echo "FAIL - $*" >&2; exit 1; }

# Symlinked copies of a script are checked once, at their source.
scripts=(install.sh tests/*.sh tests/stubs/*)
while IFS= read -r -d '' script; do scripts+=("$script"); done < <(find skills -type f -name '*.sh' -print0)
for script in "${scripts[@]}"; do
  bash -n "$script"
  [ -x "$script" ] || fail "$script is not executable"
done
shellcheck "${scripts[@]}"
while IFS= read -r -d '' script; do node --check "$script" || fail "$script doesn't parse"; done \
  < <(find skills -type f -name '*.cjs' -print0)
while IFS= read -r -d '' link; do
  [ -e "$link" ] || fail "$link points at nothing"
done < <(find skills -type l -print0)
echo "ok - syntax, shellcheck, permissions and links"

# Unset, the Superset wrapper doesn't report this run as the workspace's agent.
if ! validation="$(env -u SUPERSET_TERMINAL_ID -u SUPERSET_TAB_ID -u SUPERSET_PANE_ID \
  claude plugin validate skills 2>&1)"; then
  echo "$validation" >&2
  echo "FAIL - claude plugin validate skills" >&2
  exit 1
fi
echo "ok - claude plugin validate skills"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
tmp="$(cd "$tmp" && pwd -P)"
repo="$tmp/repo"
out="$repo/.local/out.md"
mkdir -p "$repo" "$tmp/home/.claude"
git -C "$repo" init -q
echo 'print(1)' > "$repo/app.py"
git -C "$repo" add app.py
git -C "$repo" -c user.name=test -c user.email=test@example.com commit -qm init
echo "Review the work." > "$tmp/prompt.md"
# A user settings file that allows everything. Only the model may reach the reviewer.
cat > "$tmp/home/.claude/settings.json" <<'EOF'
{"model": "opus", "modelSettings": {"claude-opus-5-5": {"effortLevel": "xhigh"}},
 "permissions": {"allow": ["Bash", "Edit", "Write"]}, "hooks": {"Stop": []}}
EOF
export STUB_RECORD="$tmp/calls" HOME="$tmp/home"
unset CLAUDE_CONFIG_DIR REVIEWER_EFFORT REVIEWER_TIMEOUT REVIEWER_STRENGTH REVIEWER_MODEL CLAUDE_CODE_EFFORT_LEVEL

# Runs reviewer.sh in the test repository with the stubs first on PATH.
review() {
  rm -rf "$STUB_RECORD"
  mkdir -p "$STUB_RECORD"
  (cd "$repo" && PATH="$here/tests/stubs:$PATH" "$here/skills/review-loop/scripts/reviewer.sh" "$@")
}

# has <call> <argument>...: the recorded call has these arguments, in this order, in a row.
has() {
  local call="$STUB_RECORD/$1" run="" argument
  shift
  for argument in "$@"; do run="$run"$'\037'"$argument"; done
  case $'\037'"$(tr '\0' '\037' < "$call")" in *"$run"$'\037'*) return 0 ;; esac
  return 1
}

# mentions <call> <text>: some argument of the recorded call contains the text.
mentions() {
  case "$(tr '\0' '\n' < "$STUB_RECORD/$1")" in *"$2"*) return 0 ;; esac
  return 1
}

# still_running <name>: the child process a stub left behind is still running.
still_running() { kill -0 "$(cat "$STUB_RECORD/$1.child")" 2>/dev/null; }

review codex "$tmp/prompt.md" .local/out.md .local/shot.png
has codex.1 exec -s read-only --json -o "$out" || fail "codex read-only launch"
has codex.1 "--image=$repo/.local/shot.png" || fail "codex screenshot path"
if mentions codex.1 model_reasoning_effort; then fail "codex effort set without REVIEWER_EFFORT"; fi
if has codex.1 -m; then fail "codex model set without REVIEWER_MODEL"; fi
[ "$(cat "$out")" = "NO MUST-FIX FINDINGS" ] || fail "codex reply"
echo "ok - codex reviewer, read-only"

REVIEWER_EFFORT=high review --run-checks codex "$tmp/prompt.md" .local/out.md
has codex.1 exec -s workspace-write || fail "codex sandbox with --run-checks"
has codex.1 -c model_reasoning_effort=high || fail "codex REVIEWER_EFFORT"
echo "ok - codex reviewer, --run-checks"

STUB_SLEEP=30 REVIEWER_TIMEOUT=2 review codex "$tmp/prompt.md" .local/out.md 2> /dev/null
has codex.2 exec -s read-only resume stub-thread -c model_reasoning_effort=medium \
  || fail "codex resume after the deadline"
if still_running codex; then fail "codex child still running after the deadline"; fi
[ "$(cat "$out")" = "FINDINGS AFTER RESUME" ] || fail "codex reply after resume"
echo "ok - codex reviewer, deadline and resume"

review claude "$tmp/prompt.md" .local/out.md .local/shot.png
for flag in --restricted --safe-mode --strict-mcp-config --no-session-persistence; do
  has claude.1 "$flag" || fail "claude $flag"
done
has claude.1 --permission-mode dontAsk || fail "claude permission mode"
has claude.1 --permission-prompts none || fail "claude permission prompts"
has claude.1 --tools Read,Grep,Glob || fail "claude read-only tools"
has claude.1 --settings '{"model":"opus","modelSettings":{"claude-opus-5-5":{"effortLevel":"xhigh"}}}' \
  || fail "claude user model settings"
if mentions claude.1 Bash; then fail "claude read-only launch mentions Bash"; fi
if mentions claude.1 --effort; then fail "claude effort set without REVIEWER_EFFORT"; fi
if mentions claude.1 --model; then fail "claude model set without REVIEWER_MODEL"; fi
has claude.1 --max-budget-usd 5 || fail "claude budget"
[ "$(cat "$STUB_RECORD/claude.1.env")" = "CLAUDE_CODE_EFFORT_LEVEL=unset" ] || fail "claude effort variable set without an effort"
mentions claude.1 "$repo/.local/shot.png" || fail "claude screenshot path"
[ "$(cat "$out")" = "NO MUST-FIX FINDINGS" ] || fail "claude reply"
echo "ok - claude reviewer, read-only"

printf 'npm test\nshellcheck scripts/*.sh\nmake lint\n' > "$repo/.local/review-checks"
REVIEWER_EFFORT=high review --run-checks claude "$tmp/prompt.md" .local/out.md 2> "$tmp/stderr"
has claude.1 --tools Read,Grep,Glob,Bash || fail "claude tools with --run-checks"
has claude.1 --allowedTools "Bash(npm test)" "Bash(make lint)" || fail "claude check rules"
if mentions claude.1 '*'; then fail "claude rule with a wildcard"; fi
grep -qF 'skipped a check with a *' "$tmp/stderr" || fail "no warning for the skipped check"
has claude.1 --effort high || fail "claude REVIEWER_EFFORT"
[ "$(cat "$STUB_RECORD/claude.1.env")" = "CLAUDE_CODE_EFFORT_LEVEL=high" ] || fail "claude REVIEWER_EFFORT not in the environment"
echo "ok - claude reviewer, --run-checks"

if STUB_SLEEP=30 REVIEWER_TIMEOUT=2 review claude "$tmp/prompt.md" .local/out.md 2> /dev/null; then
  fail "claude past the deadline exits 0"
fi
if still_running claude; then fail "claude child still running after the deadline"; fi
[ ! -e "$out" ] || fail "claude reply written after the deadline"
if STUB_ERROR=1 review claude "$tmp/prompt.md" .local/out.md 2> /dev/null; then
  fail "claude error exits 0"
fi
[ ! -e "$out" ] || fail "claude error written as a reply"
echo "ok - claude reviewer, deadline and error"

schema="$here/skills/review-loop/findings.schema.json"
finding='{"verdict":"NEEDS_CHANGES","findings":[{"file":"app.py","line":1,"summary":"s","failure_scenario":"f","confidence":"plausible"}],"below_threshold":[],"declined":[]}'
record="$repo/.local/out.run.json"
STUB_REPLY="$finding" review --schema "$schema" codex "$tmp/prompt.md" .local/out.json
has codex.1 --output-schema "$schema" || fail "codex without --output-schema"
jq -e '.verdict == "NEEDS_CHANGES"' "$repo/.local/out.json" > /dev/null || fail "codex schema reply"
jq -e '.harness == "codex" and .checks == false and .deadline == false and .cost_usd == null
  and .tokens == {input: 100, cached: 40, output: 7} and (.seconds | type == "number")
  and (.finished | type == "number")' "$record" > /dev/null \
  || fail "codex run record: $(cat "$record")"
STUB_REPLY="$finding" review --run-checks --schema "$schema" claude "$tmp/prompt.md" .local/out.json 2> /dev/null
has claude.1 --json-schema "$(cat "$schema")" || fail "claude without --json-schema"
jq -e '.verdict == "NEEDS_CHANGES"' "$repo/.local/out.json" > /dev/null || fail "claude schema reply"
jq -e '.harness == "claude" and .checks == true and .cost_usd == 0.01 and .tokens == {input: 10, cached: 5, output: 3}' \
  "$record" > /dev/null || fail "claude run record: $(cat "$record")"
STUB_SLEEP=30 REVIEWER_TIMEOUT=2 STUB_RESUME_REPLY="$finding" review --schema "$schema" codex "$tmp/prompt.md" .local/out.json 2> /dev/null
has codex.2 resume stub-thread || fail "no resume"
has codex.2 --output-schema "$schema" || fail "codex resumed without the schema"
jq -e '.verdict == "NEEDS_CHANGES"' "$repo/.local/out.json" > /dev/null || fail "schema reply after resume"
jq -e '.deadline == true and .tokens == {input: 200, cached: 80, output: 14}' "$record" > /dev/null \
  || fail "the run record doesn't add up both turns: $(cat "$record")"
if review --schema "$tmp/none.json" codex "$tmp/prompt.md" .local/out.json 2> /dev/null; then fail "a missing schema accepted"; fi
echo "ok - --schema and run records"

# REVIEWER_STRENGTH=max runs each reviewer on the strongest model and effort
# its harness offers, an explicit REVIEWER_MODEL or REVIEWER_EFFORT beats the
# pin, and the run record says what was asked for.
REVIEWER_STRENGTH=max review codex "$tmp/prompt.md" .local/out.md
has codex.1 -m gpt-6-astra || fail "codex max model"
has codex.1 -c model_reasoning_effort=max || fail "codex max effort"
jq -e '.strength == "max" and .model == "gpt-6-astra" and .effort == "max"' "$record" > /dev/null \
  || fail "codex max run record: $(cat "$record")"
REVIEWER_STRENGTH=max REVIEWER_MODEL=gpt-6.1-sol REVIEWER_EFFORT=ultra review codex "$tmp/prompt.md" .local/out.md
has codex.1 -m gpt-6.1-sol || fail "REVIEWER_MODEL doesn't beat the pin"
has codex.1 -c model_reasoning_effort=ultra || fail "REVIEWER_EFFORT doesn't beat the pin"
REVIEWER_MODEL=gpt-6.1-sol review codex "$tmp/prompt.md" .local/out.md
has codex.1 -m gpt-6.1-sol || fail "codex REVIEWER_MODEL"
if mentions codex.1 model_reasoning_effort; then fail "codex effort set by REVIEWER_MODEL"; fi
jq -e '.strength == "default" and .model == "gpt-6.1-sol" and .effort == null' "$record" > /dev/null \
  || fail "codex run record with REVIEWER_MODEL: $(cat "$record")"
STUB_SLEEP=30 REVIEWER_TIMEOUT=2 REVIEWER_STRENGTH=max review codex "$tmp/prompt.md" .local/out.md 2> /dev/null
has codex.2 resume stub-thread -m gpt-6-astra -c model_reasoning_effort=medium \
  || fail "codex resume at max strength doesn't keep the model and drop to medium"
REVIEWER_STRENGTH=max review claude "$tmp/prompt.md" .local/out.md
has claude.1 --model best || fail "claude max model"
has claude.1 --effort max || fail "claude max effort"
has claude.1 --max-budget-usd 20 || fail "claude max budget"
has claude.1 --settings '{"model":"opus","modelSettings":{"claude-opus-5-5":{"effortLevel":"xhigh"}}}' \
  || fail "claude max strength drops the user settings"
[ "$(cat "$STUB_RECORD/claude.1.env")" = "CLAUDE_CODE_EFFORT_LEVEL=max" ] || fail "claude max effort not in the environment"
jq -e '.strength == "max" and .model == "best" and .effort == "max"' "$record" > /dev/null \
  || fail "claude max run record: $(cat "$record")"
CLAUDE_CODE_EFFORT_LEVEL=low REVIEWER_EFFORT=high review claude "$tmp/prompt.md" .local/out.md
[ "$(cat "$STUB_RECORD/claude.1.env")" = "CLAUDE_CODE_EFFORT_LEVEL=high" ] || fail "an inherited effort variable beats REVIEWER_EFFORT"
CLAUDE_CODE_EFFORT_LEVEL=low review claude "$tmp/prompt.md" .local/out.md
[ "$(cat "$STUB_RECORD/claude.1.env")" = "CLAUDE_CODE_EFFORT_LEVEL=low" ] || fail "the reviewer changed an inherited effort variable although it was given no effort"
if REVIEWER_STRENGTH=most review codex "$tmp/prompt.md" .local/out.md 2> /dev/null; then fail "REVIEWER_STRENGTH=most accepted"; fi
echo "ok - REVIEWER_STRENGTH, REVIEWER_MODEL and REVIEWER_EFFORT"

echo OLD > "$out"
if STUB_REPLY='' review codex "$tmp/prompt.md" .local/out.md 2> /dev/null; then
  fail "empty reply exits 0"
fi
[ ! -e "$out" ] || fail "earlier reply left in place"
if review codex 2> /dev/null; then fail "missing arguments accepted"; fi
if review nobody "$tmp/prompt.md" .local/out.md 2> /dev/null; then fail "unknown reviewer accepted"; fi
for bad in soon 0 -5 1.5; do
  if REVIEWER_TIMEOUT="$bad" review codex "$tmp/prompt.md" .local/out.md 2> /dev/null; then
    fail "REVIEWER_TIMEOUT=$bad accepted"
  fi
done
echo "ok - empty replies and usage errors"

state() { (cd "$repo" && "$here/skills/review-loop/scripts/state.sh"); }
before="$(state)"
echo 'print(2)' >> "$repo/app.py"
edited="$(state)"
echo 'new' > "$repo/notes.txt"
added="$(state)"
echo 'scratch' > "$repo/.local/scratch.txt"
{ [ "${before%% *}" = lines=0 ] && [ "${edited%% *}" = lines=1 ] && [ "${added%% *}" = lines=2 ]; } \
  || fail "state.sh lines"
{ [ "${before#* }" != "${edited#* }" ] && [ "${edited#* }" != "${added#* }" ]; } \
  || fail "state.sh fingerprint misses a change"
[ "$(state)" = "$added" ] || fail "state.sh counts files in .local/"
[ "$(git -C "$repo" cat-file -t "${added#*fingerprint=}")" = tree ] || fail "the fingerprint is not a git tree"
git -C "$repo" diff --name-status "${before#*fingerprint=}" "${added#*fingerprint=}" > "$tmp/diff.out"
{ grep -qx "$(printf 'M\tapp.py')" "$tmp/diff.out" && grep -qx "$(printf 'A\tnotes.txt')" "$tmp/diff.out"; } \
  || fail "the diff of two fingerprints misses a change: $(cat "$tmp/diff.out")"
git -C "$repo" diff --cached --quiet || fail "state.sh staged something"
if git -C "$repo" ls-files --error-unmatch notes.txt > /dev/null 2>&1; then fail "state.sh added a file to the index"; fi
outer="$tmp/outer"
git init -q "$tmp/inner"
echo one > "$tmp/inner/f.txt"
git -C "$tmp/inner" add f.txt
git -C "$tmp/inner" -c user.name=test -c user.email=test@example.com commit -qm inner
git init -q "$outer"
git -C "$outer" -c protocol.file.allow=always submodule add -q "$tmp/inner" inner 2> /dev/null
git -C "$outer" -c user.name=test -c user.email=test@example.com commit -qm outer
clean="$( (cd "$outer" && "$here/skills/review-loop/scripts/state.sh") )"
echo two > "$outer/inner/f.txt"
dirty="$( (cd "$outer" && "$here/skills/review-loop/scripts/state.sh") )"
[ "${clean#*fingerprint=}" != "${dirty#*fingerprint=}" ] || fail "an edit inside a submodule leaves the fingerprint unchanged"
printf 'same\n' > "$outer/inner/one.txt"
printf 'same\n' > "$outer/inner/two.txt"
ln -s one.txt "$outer/inner/link.txt"
to_one="$( (cd "$outer" && "$here/skills/review-loop/scripts/state.sh") )"
ln -sfn two.txt "$outer/inner/link.txt"
to_two="$( (cd "$outer" && "$here/skills/review-loop/scripts/state.sh") )"
[ "${to_one#*fingerprint=}" != "${to_two#*fingerprint=}" ] \
  || fail "retargeting a symlink inside a submodule leaves the fingerprint unchanged"
mkdir -p "$outer/.agentic-skills-library"
echo 'mine' > "$outer/.agentic-skills-library/notes.txt"
if (cd "$outer" && "$here/skills/review-loop/scripts/state.sh") > /dev/null 2>&1; then
  fail "state.sh wrote over a path the work uses"
fi
rm -rf "$outer/.agentic-skills-library"
(cd "$outer" && "$here/skills/review-loop/scripts/state.sh") > /dev/null || fail "state.sh fails on a sound submodule"
# A required filter that doesn't exist makes git add fail inside the submodule.
git -C "$outer/inner" config filter.missing.required true
echo '*.bad filter=missing' > "$outer/inner/.gitattributes"
echo 'x' > "$outer/inner/new.bad"
if (cd "$outer" && "$here/skills/review-loop/scripts/state.sh") > /dev/null 2>&1; then
  fail "state.sh succeeds when a submodule can't be snapshotted"
fi
echo "ok - state.sh"

# refute.sh sends only findings not confirmed by running, and splits off the refuted ones.
cat > "$repo/.local/round.json" <<'EOF'
{"verdict": "NEEDS_CHANGES", "below_threshold": [], "declined": [], "findings": [
  {"file": "app.py", "line": 1, "summary": "ran it", "failure_scenario": "f", "confidence": "confirmed-by-running"},
  {"file": "app.py", "line": 1, "summary": "read it", "failure_scenario": "f", "confidence": "confirmed-by-reading"},
  {"file": "app.py", "line": 1, "summary": "guessed", "failure_scenario": "f", "confidence": "plausible"}]}
EOF
refute() {
  rm -rf "$STUB_RECORD"
  mkdir -p "$STUB_RECORD"
  (cd "$repo" && PATH="$here/tests/stubs:$PATH" "$here/skills/review-loop/scripts/refute.sh" "$@")
}
STUB_REPLY='{"verdicts": [{"finding": 2, "verdict": "refuted", "evidence": "app.py:1 shows it"},
  {"finding": 1, "verdict": "stands", "evidence": "checked"}]}' refute codex .local/round.json > /dev/null
has codex.1 --output-schema "$here/skills/review-loop/verdicts.schema.json" || fail "refute.sh doesn't ask for verdicts"
jq -e '[.[].summary] == ["read it", "guessed"]' "$repo/.local/refute-input.json" > /dev/null \
  || fail "refute.sh sent the wrong findings"
jq -e '[.findings[].summary] == ["ran it", "read it"]' "$repo/.local/round.kept.json" > /dev/null \
  || fail "refute.sh kept the wrong findings"
jq -e 'length == 1 and .[0].finding.summary == "guessed" and .[0].evidence == "app.py:1 shows it"' \
  "$repo/.local/round.refuted.json" > /dev/null || fail "refute.sh lost the refuted finding"
jq '.findings |= map(select(.confidence == "confirmed-by-running"))' "$repo/.local/round.json" > "$repo/.local/ran.json"
refute codex .local/ran.json > /dev/null
[ -z "$(ls "$STUB_RECORD")" ] || fail "refute.sh ran a reviewer with nothing to refute"
cmp -s "$repo/.local/ran.json" "$repo/.local/ran.kept.json" || fail "refute.sh changed a round with nothing to refute"
STUB_REPLY='' refute codex .local/round.json > /dev/null 2>&1 || fail "refute.sh failed when its reviewer did"
jq -e '.findings | length == 3' "$repo/.local/round.kept.json" > /dev/null || fail "a failed refute run dropped findings"
echo "ok - refute.sh"

# log-round.sh adds up this round's run records, and counts the findings in
# lines that the previous round's fixes changed, not this round's.
logged="$tmp/logged"
mkdir -p "$logged"
git -C "$logged" init -q
seq 1 12 > "$logged/numbers.txt"
git -C "$logged" add numbers.txt
git -C "$logged" -c user.name=test -c user.email=test@example.com commit -qm init
snapshot() { (cd "$logged" && "$here/skills/review-loop/scripts/state.sh") | sed 's/.*fingerprint=//'; }
before_fixes="$(snapshot)"
perl -pi -e 's/^3$/three/' "$logged/numbers.txt"
printf 'new\nmore\n' > "$logged/added.txt"
after_fixes="$(snapshot)"
perl -pi -e 's/^10$/ten/' "$logged/numbers.txt"
mkdir -p "$logged/.local"
cat > "$logged/.local/review-round-2.json" <<EOF
{"verdict": "NEEDS_CHANGES", "below_threshold": [], "declined": [], "findings": [
  {"file": "$logged/numbers.txt", "line": 3, "summary": "s", "failure_scenario": "f", "confidence": "plausible"},
  {"file": "numbers.txt", "line": 10, "summary": "s", "failure_scenario": "f", "confidence": "plausible"},
  {"file": "added.txt", "line": 1, "summary": "s", "failure_scenario": "f", "confidence": "plausible"},
  {"file": "added.txt", "line": 2, "summary": "s", "failure_scenario": "f", "confidence": "plausible"}]}
EOF
run_record() { # run_record <name> <finished> <seconds> <input tokens> <cached tokens>
  printf '{"harness": "codex", "checks": true, "strength": "max", "model": "gpt-6-astra", "effort": "max", "seconds": %s, "finished": %s, "deadline": false, "cost_usd": null, "tokens": {"input": %s, "cached": %s, "output": 1}}\n' \
    "$3" "$2" "$4" "$5" > "$logged/.local/review-round-2$1.run.json"
}
run_record "" 1000 30 100 40
run_record .verdicts 1010 12 50 10
run_record .referee-F1 1020 5 10 0
run_record .referee-F2 1030 5 10 0
run_record .stale 900 99 1000 500
log_round() { (cd "$logged" && XDG_STATE_HOME="$tmp/state" "$here/skills/review-loop/scripts/log-round.sh" "$@"); }
log_round --round 2 --reported 4 --refuted 1 --accepted 1 --rejected 1 --disputed 0 \
  --before "$before_fixes" --after "$after_fixes" --exit clean > /dev/null
line="$(tail -n 1 "$tmp/state/agentic-skills-library/review-loop.jsonl")"
jq -e '.round == 2 and .reported == 4 and .refuted == 1 and .accepted == 1 and .rejected == 1 and .disputed == 0
  and .in_previous_fix == 3 and .lines == 6 and .exit == "clean" and .reviewer == "codex"
  and .strength == "max" and .model == "gpt-6-astra" and .effort == "max"
  and .seconds == 52 and .cost_usd == null and .tokens == {input: 170, cached: 50, output: 4}' <<< "$line" > /dev/null \
  || fail "log-round.sh wrote $line"
log_round --round 1 --reported 0 --refuted 0 --accepted 0 --rejected 0 --disputed 0 > /dev/null
jq -e '.round == 1 and .in_previous_fix == null and .exit == null and .seconds == 0
  and .strength == null and .model == null and .effort == null' \
  <<< "$(tail -n 1 "$tmp/state/agentic-skills-library/review-loop.jsonl")" > /dev/null || fail "log-round.sh without records"
if log_round --round 1 --reported x 2> /dev/null; then fail "log-round.sh accepted a bad count"; fi
# The outer repository's submodule still can't be snapshotted, so state.sh fails there.
(cd "$outer" && XDG_STATE_HOME="$tmp/state" "$here/skills/review-loop/scripts/log-round.sh" --round 1 --reported 0 \
  --refuted 0 --accepted 0 --rejected 0 --disputed 0 --exit "snapshot failed") > /dev/null \
  || fail "log-round.sh can't log a round that state.sh fails in"
jq -e '.lines == null and .exit == "snapshot failed"' \
  <<< "$(tail -n 1 "$tmp/state/agentic-skills-library/review-loop.jsonl")" > /dev/null || fail "log-round.sh logged the failed snapshot wrongly"
if log_round --round 1 --reported 0 --refuted 0 --accepted 0 --rejected 0 --disputed 0 --before "$before_fixes" 2> /dev/null; then
  fail "log-round.sh accepted --before without --after"
fi
echo "ok - log-round.sh"

# screenshot.sh --check finds the canary word in a review, in any case, and nothing else will do.
shots="$tmp/shots"
mkdir -p "$shots"
printf '%s' PLUM | shasum | cut -d' ' -f1 > "$shots/canary.sha"
canary_check() { printf '%b' "$1" > "$tmp/design-review.md"; "$here/skills/review-design/scripts/screenshot.sh" --check "$2" "$tmp/design-review.md" > /dev/null 2>&1; }
canary_check 'CANARY: PLUM\nNO MUST-FIX DESIGN FINDINGS\n' "$shots" || fail "the canary check missed the word"
canary_check '**CANARY: plum**\n' "$shots" || fail "the canary check missed the word in bold or lower case"
if canary_check 'CANARY: NONE\n' "$shots"; then fail "the canary check passed NONE"; fi
if canary_check 'CANARY: PLUMS\n' "$shots"; then fail "the canary check passed a different word"; fi
if canary_check 'No canary here.\n' "$shots"; then fail "the canary check passed a review without the word"; fi
if canary_check 'CANARY: PLUM\n' "$tmp/nowhere"; then fail "the canary check passed without a hash"; fi
echo "ok - screenshot.sh --check"

# ask.sh runs Argon in a throwaway folder that holds copies of the files and
# nothing else, and keeps an answer only from a run that answered and opened them all.
ask() {
  rm -rf "$STUB_RECORD"
  mkdir -p "$STUB_RECORD"
  (cd "$repo" && PATH="$here/tests/stubs:$PATH" "$here/skills/ask-gemini/scripts/ask.sh" "$@")
}
# prompt_of <call>: the call's last argument, when the one before it is -p.
prompt_of() { perl -0ne 'chomp; push @a, $_; END { print $a[-1] if @a > 1 && $a[-2] eq "-p" }' "$STUB_RECORD/$1"; }
# settings_of <call>: the argument after --settings.
settings_of() { perl -0ne 'chomp; if ($take) { print; exit } $take = ($_ eq "--settings")' "$STUB_RECORD/$1"; }
gemini="$repo/.local/gemini"
mkdir -p "$gemini" "$repo/clips/a" "$repo/clips/b"
echo "What colour is the screen?" > "$gemini/brief.md"
printf 'video' > "$repo/clips/a/clip.mp4"
printf 'another video' > "$repo/clips/b/clip.mp4"
printf 'audio' > "$repo/talk.m4a"
answer="$gemini/answer.md"
ask_record="$gemini/answer.run.json"
brief=(.local/gemini/brief.md .local/gemini/answer.md)

# An open stdin with nothing on it, which agy -p can wait on forever.
ask --media "${brief[@]}" clips/a/clip.mp4 talk.m4a clips/b/clip.mp4 < <(sleep 10)
folder="$(cat "$STUB_RECORD/agy.1.cwd")"
case "$folder" in /tmp/ask-gemini.*) ;; *) fail "ask.sh ran agy in $folder, not in a throwaway folder" ;; esac
[ ! -e "$folder" ] || fail "ask.sh left its throwaway folder behind"
[ "$(tr '\n' ' ' < "$STUB_RECORD/agy.1.files")" = "2-clip.mp4 clip.mp4 talk.m4a " ] \
  || fail "the throwaway folder held $(tr '\n' ' ' < "$STUB_RECORD/agy.1.files")"
[ "$(cat "$STUB_RECORD/agy.1.stdin")" = closed ] || fail "ask.sh left agy's stdin open"
has agy.1 --model gemini-4-argon-medium || fail "ask.sh --media model"
has agy.1 --output-format stream-json || fail "ask.sh output format"
has agy.1 --disable-slash-commands || fail "ask.sh slash commands"
has agy.1 --sandbox || fail "ask.sh terminal sandbox"
has agy.1 --print-timeout 450s || fail "ask.sh print timeout"
jq -e --arg home "$HOME" '.toolPermission == "request-review" and (.permissions.deny | contains(["command(*)",
  "write_file(*)", "read_url(*)", "execute_url(*)", "mcp(*)", "read_file(/Users/)", "read_file(/Volumes/)",
  "read_file(\($home)/)"]))' <<< "$(settings_of agy.1)" > /dev/null || fail "ask.sh session settings: $(settings_of agy.1)"
prompt="$(prompt_of agy.1)"
case "$prompt" in "$(head -n 1 "$here/skills/ask-gemini/media-prompt.md")"*) ;; *) fail "the prompt doesn't start with the media instructions" ;; esac
case "$prompt" in *"- clip.mp4"*"- talk.m4a"*"- 2-clip.mp4"*"## The brief"*"What colour is the screen?") ;;
  *) fail "the prompt lacks the files or the brief: $prompt" ;; esac
[ "$(cat "$answer")" = "NOTHING TO REPORT" ] || fail "ask.sh answer"
jq -e '.harness == "agy" and .job == "media" and .model == "gemini-4-argon-medium" and .status == "SUCCESS"
  and .deadline == false and .finished_reason == null and .conversation_id == "stub-conversation" and .files == 3
  and .not_opened == [] and .tokens == {input: 100, cached: 40, output: 7, thinking: 3}
  and (.seconds | type == "number") and (.finished | type == "number")' "$ask_record" > /dev/null \
  || fail "ask.sh run record: $(cat "$ask_record")"
echo "ok - ask.sh, media"

ask --second-opinion "${brief[@]}"
has agy.1 --model gemini-4-argon-high || fail "ask.sh --second-opinion model"
case "$(prompt_of agy.1)" in "$(head -n 1 "$here/skills/ask-gemini/second-opinion-prompt.md")"*"There are no files"*) ;;
  *) fail "the second-opinion prompt" ;; esac
[ ! -s "$STUB_RECORD/agy.1.files" ] || fail "a run without files had files in its folder"
GEMINI_MODEL=gemini-4-argon-low ask --media "${brief[@]}" talk.m4a
has agy.1 --model gemini-4-argon-low || fail "ask.sh GEMINI_MODEL"
echo "ok - ask.sh, second opinion and GEMINI_MODEL"

echo OLD > "$answer"
if STUB_SKIP_OPEN=talk.m4a ask --media "${brief[@]}" clips/a/clip.mp4 talk.m4a 2> "$tmp/stderr"; then
  fail "ask.sh kept an answer from a run that didn't open a file"
fi
[ ! -e "$answer" ] || fail "ask.sh left an answer behind when a file wasn't opened"
grep -qF "didn't open talk.m4a" "$tmp/stderr" || fail "ask.sh doesn't name the file Argon didn't open"
jq -e '.not_opened == ["talk.m4a"]' "$ask_record" > /dev/null || fail "the run record doesn't name the unopened file"
if STUB_STATUS=ERROR ask --media "${brief[@]}" talk.m4a 2> /dev/null; then fail "ask.sh accepted an ERROR status"; fi
[ ! -e "$answer" ] || fail "ask.sh wrote the answer of a failed run"
if STUB_REPLY='' ask --media "${brief[@]}" talk.m4a 2> /dev/null; then fail "ask.sh accepted an empty answer"; fi
[ ! -e "$answer" ] || fail "ask.sh wrote an empty answer"
STUB_FINISHED_REASON=print_timeout ask --media "${brief[@]}" talk.m4a 2> "$tmp/stderr" \
  || fail "ask.sh dropped an answer that agy's time limit cut off"
grep -qF 'cut off (print_timeout)' "$tmp/stderr" || fail "ask.sh doesn't warn of a cut-off answer"
jq -e '.finished_reason == "print_timeout"' "$ask_record" > /dev/null || fail "the run record doesn't say the answer was cut off"
if STUB_SLEEP=30 GEMINI_TIMEOUT=2 ask --media "${brief[@]}" talk.m4a 2> "$tmp/stderr"; then
  fail "ask.sh past the deadline exits 0"
fi
if still_running agy; then fail "agy still running after the deadline"; fi
grep -qF 'passed its 2-second deadline' "$tmp/stderr" || fail "ask.sh doesn't report the deadline"
jq -e '.deadline == true' "$ask_record" > /dev/null || fail "the run record misses the deadline"
[ ! -e "$answer" ] || fail "ask.sh wrote an answer after the deadline"
[ ! -e "$(cat "$STUB_RECORD/agy.1.cwd")" ] || fail "ask.sh left its throwaway folder behind after the deadline"
echo "ok - ask.sh, failed runs and the deadline"

mkdir -p "$HOME/.gemini/antigravity-cli"
echo '{"toolPermission": "always-proceed"}' > "$HOME/.gemini/antigravity-cli/settings.json"
if ask --media "${brief[@]}" talk.m4a 2> "$tmp/stderr"; then fail "ask.sh ran under a global always-proceed"; fi
[ ! -e "$STUB_RECORD/agy.1" ] || fail "ask.sh called agy under a global always-proceed"
grep -qF 'always-proceed' "$tmp/stderr" || fail "ask.sh doesn't say why it refused"
rm "$HOME/.gemini/antigravity-cli/settings.json"
if ask 2> /dev/null; then fail "ask.sh accepted no arguments"; fi
if ask --video "${brief[@]}" 2> /dev/null; then fail "ask.sh accepted an unknown job"; fi
if ask --media .local/gemini/none.md .local/gemini/answer.md 2> /dev/null; then fail "ask.sh accepted a missing brief"; fi
if ask --media "${brief[@]}" none.mp4 2> /dev/null; then fail "ask.sh accepted a missing file"; fi
for bad in soon 0 -5 1.5; do
  if GEMINI_TIMEOUT="$bad" ask --media "${brief[@]}" 2> /dev/null; then fail "GEMINI_TIMEOUT=$bad accepted"; fi
done
echo "ok - ask.sh, refusals and usage errors"

# log.sh adds one line per Gemini job, with the run's record when there is one.
gemini_log() { (cd "$repo" && XDG_STATE_HOME="$tmp/state" "$here/skills/ask-gemini/scripts/log.sh" "$@"); }
ask --media "${brief[@]}" talk.m4a
gemini_log --job media --added yes --corrections 007 --answer .local/gemini/answer.md > /dev/null
line="$(tail -n 1 "$tmp/state/agentic-skills-library/ask-gemini.jsonl")"
jq -e '.job == "media" and .route == "cli" and .added == true and .corrections == 7 and .repo == "repo"
  and .model == "gemini-4-argon-medium" and .tokens.input == 100 and (.seconds | type == "number")
  and (.time | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T"))' <<< "$line" > /dev/null || fail "log.sh wrote $line"
gemini_log --job gmail-drive --added no --corrections 0 > /dev/null
line="$(tail -n 1 "$tmp/state/agentic-skills-library/ask-gemini.jsonl")"
jq -e '.job == "gmail-drive" and .route == "app" and .added == false and .model == null' <<< "$line" > /dev/null \
  || fail "log.sh wrote $line for a hand-off"
for bad in "--job video --added yes --corrections 0" "--job media --added maybe --corrections 0" \
  "--job media --added yes --corrections x" "--job media --added yes"; do
  # shellcheck disable=SC2086 # each word is an argument
  if gemini_log $bad 2> /dev/null; then fail "log.sh accepted $bad"; fi
done
echo "ok - ask-gemini's log.sh"

# install.sh, run from a copy of this repository with its own commit, against a fake home.
copy="$tmp/copy"
home="$tmp/install-home"
mkdir -p "$copy/research" "$home"
cp -R "$here/install.sh" "$here/skills" "$here/instructions" "$copy/"
printf 'claude 2.1.294\ncodex 0.160.1\n' > "$copy/research/verified-versions"
git -C "$copy" init -q
git -C "$copy" add -A
git -C "$copy" -c user.name=test -c user.email=test@example.com commit -qm copy
installer() { HOME="$home" PATH="$here/tests/stubs:$PATH" "$copy/install.sh" "$@"; }
installed="$home/.agents/skills"

installer > /dev/null 2>&1 || fail "install"
[ -f "$installed/review-plan/scripts/reviewer.sh" ] && [ ! -L "$installed/review-plan/scripts/reviewer.sh" ] \
  || fail "the shared runner is not installed as a file of its own"
cmp -s "$installed/review-plan/scripts/reviewer.sh" "$here/skills/review-loop/scripts/reviewer.sh" \
  || fail "the installed runner differs from its source"
grep -qF "managed copy of $(git -C "$copy" rev-parse --short HEAD)" "$installed/ship/SKILL.md" \
  || fail "the marker doesn't name the commit"
[ "$(readlink "$home/.claude/skills/ship")" = "$installed/ship" ] || fail "no Claude Code link"
grep -qF 'agentic-skills-library:start' "$home/.codex/AGENTS.md" || fail "no instruction block"
installer --check > "$tmp/check.out" 2>&1 || fail "--check right after install: $(cat "$tmp/check.out")"
[ "$(grep -c ': current$' "$tmp/check.out")" = 9 ] || fail "--check doesn't report all seven skills and both blocks current"
if grep -q '^note:' "$tmp/check.out"; then fail "--check notes a version that matches"; fi
STUB_CODEX_VERSION=0.999.0 installer --check > "$tmp/check.out" 2>&1 || true
grep -q '^note: codex is 0.999.0, but the skills were last verified on 0.160.1' "$tmp/check.out" \
  || fail "--check doesn't note a new Codex version"

echo 'edited' >> "$installed/review-loop/reviewer-prompt.md"
chmod -x "$installed/review-plan/scripts/reviewer.sh"
rm -rf "$installed/save-review"
mkdir -p "$home/.codex/skills/ship"
if installer --check > "$tmp/check.out" 2>&1; then fail "--check passes a changed install"; fi
grep -qx 'review-loop: changed' "$tmp/check.out" || fail "--check misses a changed file"
grep -qx 'review-plan: changed' "$tmp/check.out" || fail "--check misses a script that lost its execute bit"
grep -qx 'save-review: missing' "$tmp/check.out" || fail "--check misses a missing skill"
grep -q 'warning: .*/.codex/skills/ship also exists' "$tmp/check.out" || fail "no warning for a shadowing skill"

installer > /dev/null 2>&1 || fail "reinstall"
installer --check > /dev/null 2>&1 || fail "reinstall doesn't restore the copies"
installer --uninstall > /dev/null 2>&1
[ ! -e "$installed/ship" ] && [ ! -e "$home/.claude/skills/ship" ] || fail "uninstall leaves a skill"
if grep -qF 'agentic-skills-library:start' "$home/.claude/CLAUDE.md"; then fail "uninstall leaves the block"; fi
[ -d "$home/.codex/skills/ship" ] || fail "uninstall removed a skill it doesn't own"
echo "ok - install.sh"

echo "all checks passed"
