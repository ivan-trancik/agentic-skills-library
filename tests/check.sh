#!/usr/bin/env bash
# The checks for this repository: syntax, lint and permissions for every
# script, Claude Code's skill validator, tests that run reviewer.sh and
# state.sh against the stub codex and claude commands in tests/stubs, and
# tests of install.sh against a fake home. Free and offline: no model is
# called, and it runs inside Codex's sandbox.
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
unset CLAUDE_CONFIG_DIR REVIEWER_EFFORT REVIEWER_TIMEOUT

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
echo "ok - state.sh"

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
[ "$(grep -c ': current$' "$tmp/check.out")" = 8 ] || fail "--check doesn't report all six skills and both blocks current"
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
