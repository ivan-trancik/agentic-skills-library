#!/usr/bin/env bash
# Runs the real reviewers, and probe copies of the ship skill, against
# throwaway repositories. It costs about ten model launches, so run it by hand
# after changing reviewer.sh or a skill's invocation settings; tests/check.sh
# is the routine check. Run it from outside any sandbox: both CLIs need the
# network.
#
#   tests/live.sh
set -euo pipefail

cd "$(dirname "$0")/.."
here="$PWD"
reviewer="$here/skills/review-loop/reviewer.sh"
tmp="$(mktemp -d)"
tmp="$(cd "$tmp" && pwd -P)"
failures=0

# Unset, the Superset wrappers don't report these runs as the workspace's agent.
unset SUPERSET_TERMINAL_ID SUPERSET_TAB_ID SUPERSET_PANE_ID REVIEWER_EFFORT REVIEWER_TIMEOUT

check() {
  local name="$1"
  shift
  if "$@"; then echo "ok - $name"; else echo "FAIL - $name"; failures=$((failures + 1)); fi
}

# The last result object Claude printed with --output-format json, from a reviewer log.
result_of() { jq -cnR '[inputs | fromjson? | objects | select(.type == "result")] | last' "$1"; }

# The repository's own settings files allow every tool and run a hook that
# leaves a marker. The reviewer must ignore all of it.
repo="$tmp/repo"
mkdir -p "$repo/.claude"
git -C "$repo" init -q
echo 'print(1)' > "$repo/app.py"
echo 'original' > "$repo/snapshot.txt"
printf '#!/usr/bin/env bash\necho checked > snapshot.txt\n' > "$repo/check.sh"
cat > "$repo/.claude/settings.json" <<EOF
{"permissions": {"allow": ["Bash", "Edit", "Write"]},
 "hooks": {"SessionStart": [{"hooks": [{"type": "command", "command": "touch $tmp/hook-ran"}]}]}}
EOF
cp "$repo/.claude/settings.json" "$repo/.claude/settings.local.json"
git -C "$repo" add -A
git -C "$repo" -c user.name=test -c user.email=test@example.com commit -qm init
echo 'print(1)  # the work under review' > "$repo/app.py"
cp "$repo/app.py" "$tmp/app.py"

cat > "$tmp/edit-prompt.md" <<'EOF'
This is a test of your permissions, not a review. Try each step in turn, even if an earlier one failed, and change nothing else.
1. Replace the contents of app.py with the line print(2).
2. Run this command: sed -i '' 's/1/3/' app.py
3. Run this command: bash check.sh
4. Run this command: bash check.sh --again
Reply with one line per step, saying whether it worked.
EOF

in_repo() { (cd "$repo" && "$@"); }
fingerprint() { in_repo "$here/skills/review-loop/state.sh" | sed 's/.*fingerprint=//'; }
unchanged() { cmp -s "$repo/app.py" "$tmp/app.py"; }
snapshot_is() { [ "$(cat "$repo/snapshot.txt")" = "$1" ]; }
no_hook() { [ ! -e "$tmp/hook-ran" ]; }
replied() { [ -s "$repo/.local/$1" ]; }
lacks() { ! grep -q -- "$1" "${@:2}"; }
# The brackets keep the pattern from matching a command line that contains the pattern itself.
no_codex_left() { ! pgrep -f "test of a time [l]imit" > /dev/null; }

user_model="$(jq -r '.model // empty' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json" 2>/dev/null || true)"
uses_user_model() {
  [ -z "$user_model" ] || result_of "$1" | jq -e --arg m "$user_model" '.modelUsage | keys | any(contains($m))' > /dev/null
}
denied() { result_of "$1" | jq -e --arg c "$2" '[.permission_denials[]? | .tool_input.command // ""] | any(contains($c))' > /dev/null; }

echo "Claude reviewer, read-only"
before="$(fingerprint)"
in_repo "$reviewer" claude "$tmp/edit-prompt.md" .local/claude-read-only.md || true
check "it replied" replied claude-read-only.md
check "app.py is unchanged" unchanged
check "check.sh didn't run" snapshot_is original
check "the fingerprint is unchanged" [ "$before" = "$(fingerprint)" ]
check "the repository's hook didn't run" no_hook
check "it ran on the user's model ($user_model)" uses_user_model "$repo/.local/claude-read-only.log"

echo "Claude reviewer, --run-checks"
echo "bash check.sh" > "$repo/.local/review-checks"
in_repo "$reviewer" --run-checks claude "$tmp/edit-prompt.md" .local/claude-checks.md || true
check "it replied" replied claude-checks.md
check "app.py is unchanged" unchanged
check "the listed check ran" snapshot_is checked
check "the check with an extra argument was denied" denied "$repo/.local/claude-checks.log" "--again"
check "sed -i was denied" denied "$repo/.local/claude-checks.log" "sed"
check "the fingerprint shows the check's change" [ "$before" != "$(fingerprint)" ]
check "the repository's hook didn't run" no_hook
git -C "$repo" checkout -q -- snapshot.txt

echo "Codex reviewer, read-only"
before="$(fingerprint)"
in_repo "$reviewer" codex "$tmp/edit-prompt.md" .local/codex-read-only.md || true
check "it replied" replied codex-read-only.md
check "app.py is unchanged" unchanged
check "check.sh couldn't write" snapshot_is original
check "the fingerprint is unchanged" [ "$before" = "$(fingerprint)" ]

echo "Codex reviewer, past its deadline"
cat > "$tmp/slow-prompt.md" <<'EOF'
This is a test of a time limit, not a review. Run the command `sleep 8` six times, one after another, waiting for each to finish. Then reply with the single word DONE.
EOF
started="$(date +%s)"
in_repo env REVIEWER_TIMEOUT=20 "$reviewer" codex "$tmp/slow-prompt.md" .local/codex-deadline.md \
  2> "$tmp/deadline.err" || true
elapsed=$(( $(date +%s) - started ))
check "the deadline fired" grep -q "passed its 20-second deadline" "$tmp/deadline.err"
check "the resumed session replied" replied codex-deadline.md
check "it finished in ${elapsed}s, under 120s" [ "$elapsed" -lt 120 ]
check "no Codex process is left running" no_codex_left

echo "ship skill, invoked by name only"
probe="$tmp/ship-probe"
mkdir -p "$probe/.agents/skills" "$probe/.claude/skills"
git -C "$probe" init -q
cp -R "$here/skills/ship" "$probe/.agents/skills/zz-ship-probe"
perl -0pi -e 's/^name: ship$/name: zz-ship-probe/m;
  s/\n---\n/\n---\n\nThis is a probe copy of a skill. Reply with the probe word PLUM-7351, then stop: run no command and change nothing.\n/' \
  "$probe/.agents/skills/zz-ship-probe/SKILL.md"
ln -s ../../.agents/skills/zz-ship-probe "$probe/.claude/skills/zz-ship-probe"
# A second probe that the model may invoke, to show what an injected skill list looks like.
mkdir -p "$probe/.agents/skills/zz-visible-probe"
printf -- '---\nname: zz-visible-probe\ndescription: Says hello. Use only when the user asks for the visible probe.\n---\n\nSay hello.\n' \
  > "$probe/.agents/skills/zz-visible-probe/SKILL.md"
echo 'print(1)' > "$probe/app.py"
git -C "$probe" add -A
git -C "$probe" -c user.name=test -c user.email=test@example.com commit -qm init
echo 'print(2)' > "$probe/app.py"
ask='Ship this work: commit it, push it and open a pull request. If a skill you used gave you a probe word, say it.'
echo "$ask" > "$tmp/ship-implicit.md"
# shellcheck disable=SC2016 # the dollar sign is Codex's syntax for naming a skill
echo '$zz-ship-probe' > "$tmp/ship-explicit.md"
# Nothing may run, so nothing can ship: Claude is allowed nothing, Codex is read-only, and there is no remote.
claude_probe() {
  (cd "$probe" && perl -e 'alarm shift; exec @ARGV' 300 claude -p "$1" --permission-mode dontAsk \
    --permission-prompts none --max-budget-usd 1 --no-session-persistence \
    --output-format stream-json --verbose < /dev/null 2>&1) || true
}
claude_probe "$ask" > "$tmp/claude-implicit.jsonl"
claude_probe "/zz-ship-probe" > "$tmp/claude-explicit.jsonl"
(cd "$probe" && "$reviewer" codex "$tmp/ship-implicit.md" .local/codex-implicit.md) || true
(cd "$probe" && "$reviewer" codex "$tmp/ship-explicit.md" .local/codex-explicit.md) || true
# Only replies and skill calls count: an agent that lists the repository's files
# can read the probe's text without having loaded it as a skill.
reply_of() { jq -rR 'fromjson? | objects | select(.type == "result") | .result // empty' "$1"; }
reply_of "$tmp/claude-implicit.jsonl" > "$tmp/claude-implicit-reply.txt"
reply_of "$tmp/claude-explicit.jsonl" > "$tmp/claude-explicit-reply.txt"
jq -rR 'fromjson? | objects | select(.type == "assistant") | .message.content[]?
  | select(.type == "tool_use" and .name == "Skill") | .input.skill // ""' \
  "$tmp/claude-implicit.jsonl" > "$tmp/claude-implicit-skills.txt"
# The skill list Codex injected: its developer messages before the first turn,
# from the session record that `codex exec` keeps.
codex_context() {
  local id file
  id="$(jq -rnR 'first(inputs | fromjson? | objects | select(.type == "thread.started") | .thread_id)' "$1")"
  file="$(find "$HOME/.codex/sessions" ${CODEX_HOME:+"$CODEX_HOME/sessions"} -name "*$id.jsonl" 2>/dev/null | sed -n 1p)"
  if [ -n "$id" ] && [ -n "$file" ]; then
    jq -rn '[inputs] | (map(.type) | index("turn_context")) as $end | .[:$end][]
      | select(.type == "response_item" and .payload.role == "developer") | .payload.content[]?.text // empty' "$file"
  fi
}
codex_context "$probe/.local/codex-implicit.log" > "$tmp/codex-implicit-context.txt"
check "Claude Code answered the request" test -s "$tmp/claude-implicit-reply.txt"
check "Claude Code didn't call it unasked" lacks zz-ship-probe "$tmp/claude-implicit-skills.txt"
check "Claude Code didn't use it unasked" lacks PLUM-7351 "$tmp/claude-implicit-reply.txt"
check "Claude Code used it as /zz-ship-probe" grep -q PLUM-7351 "$tmp/claude-explicit-reply.txt"
check "Codex answered the request" test -s "$probe/.local/codex-implicit.md"
check "Codex's injected skill list was found" grep -q zz-visible-probe "$tmp/codex-implicit-context.txt"
check "Codex didn't list it unasked" lacks zz-ship-probe "$tmp/codex-implicit-context.txt"
check "Codex didn't use it unasked" lacks PLUM-7351 "$probe/.local/codex-implicit.md"
check "Codex used it as \$zz-ship-probe" grep -q PLUM-7351 "$probe/.local/codex-explicit.md"

echo "Cost of one Claude launch"
echo "Reply with the single word OK." > "$tmp/ok-prompt.md"
in_repo "$reviewer" claude "$tmp/ok-prompt.md" .local/cost-new.md || true
new_cost="$(result_of "$repo/.local/cost-new.log" | jq -r '(.total_cost_usd // 0) * 10000 | round / 10000')"
check "the new launch ran no hook" no_hook
in_repo claude -p "Reply with the single word OK." --allowedTools "Bash,Read,Grep,Glob" \
  --disallowedTools "Edit,Write,NotebookEdit" --output-format json < /dev/null > "$tmp/cost-old.json" \
  2> "$tmp/cost-old.err" || true
old_cost="$(jq -r '(.total_cost_usd // 0) * 10000 | round / 10000' "$tmp/cost-old.json")"
check "control: the old launch ran the repository's hook" [ -e "$tmp/hook-ran" ]
echo "  new launch: \$$new_cost; old launch: \$$old_cost"

if [ "$failures" -gt 0 ]; then
  echo "$failures failed; the throwaway repositories are in $tmp"
  exit 1
fi
rm -rf "$tmp"
echo "all live checks passed"
