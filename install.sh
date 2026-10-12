#!/usr/bin/env bash
# Installs the skills in skills/ for the current user, so Claude Code and
# Codex find them in every project, and adds the instruction block in
# instructions/ to both agents' per-user instruction files.
#
#   ./install.sh              install or update everything
#   ./install.sh --check      report whether the installed copies match this repository
#   ./install.sh --uninstall  remove exactly what this script installed
#
# Ownership: every installed copy carries a marker naming the commit it came
# from. Install refuses to replace a same-name skill that has no marker, and
# uninstall removes only marked copies and the marked block. Edit the source
# here and reinstall; edits made to the installed copies are overwritten.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
commit="$(git -C "$here" describe --always --dirty 2>/dev/null || echo unknown)"
marker_prefix="<!-- agentic-skills-library: managed copy"
marker="$marker_prefix of $commit, edit the source and reinstall -->"
block_start="<!-- agentic-skills-library:start -->"
block_end="<!-- agentic-skills-library:end -->"

agents_dir="$HOME/.agents/skills"       # read by Codex
claude_dir="$HOME/.claude/skills"       # read by Claude Code
codex_dir="$HOME/.codex/skills"         # also read by Codex, so a same-name skill there shadows ours
instruction_files=("$HOME/.claude/CLAUDE.md" "$HOME/.codex/AGENTS.md")

managed() { [ -f "$1/SKILL.md" ] && grep -qF "$marker_prefix" "$1/SKILL.md"; }

warn_shadow() {
  if [ -e "$codex_dir/$1" ]; then
    echo "warning: $codex_dir/$1 also exists, and Codex may load it instead of this one" >&2
  fi
}

install_skill() {
  local src="$1" name target link
  name="$(basename "$src")"; target="$agents_dir/$name"; link="$claude_dir/$name"
  if [ -e "$target" ] && ! managed "$target"; then
    echo "refusing to replace $target: it is not a copy made by this script" >&2
    return 1
  fi
  if [ -e "$link" ] && [ "$(readlink "$link" || true)" != "$target" ]; then
    echo "refusing to replace $link: it does not point at $target" >&2
    return 1
  fi
  rm -rf "$target"
  mkdir -p "$agents_dir" "$claude_dir"
  # -L copies what a symlink points at, so a script shared between skills
  # becomes a file of its own in each installed copy.
  cp -RL "$src" "$target"
  # The marker goes right after the front matter, so the skill's metadata stays first.
  awk -v m="$marker" 'BEGIN { n = 0 } { print } /^---$/ { n++; if (n == 2) print m }' "$src/SKILL.md" > "$target/SKILL.md"
  find "$target" -name '*.sh' -exec chmod +x {} +
  ln -sfn "$target" "$link"
  echo "installed $name"
  warn_shadow "$name"
}

uninstall_skill() {
  local src="$1" name target link
  name="$(basename "$src")"; target="$agents_dir/$name"; link="$claude_dir/$name"
  if [ -L "$link" ] && [ "$(readlink "$link")" = "$target" ]; then rm "$link"; fi
  if [ -e "$target" ]; then
    if managed "$target"; then rm -rf "$target"; echo "removed $name"
    else echo "left $target alone: it is not a copy made by this script" >&2; fi
  fi
}

# Prints current, changed, missing or "not ours" for an installed skill. The
# copy matches when it has the same files, with the same contents apart from
# the marker, and every file that is executable here is executable there.
skill_state() {
  local src="$1" name target file
  name="$(basename "$src")"; target="$agents_dir/$name"
  if [ ! -e "$target" ]; then echo missing; return; fi
  if ! managed "$target"; then echo "not ours"; return; fi
  if [ "$(readlink "$claude_dir/$name" || true)" != "$target" ] \
    || [ "$(cd "$src" && find -L . -type f | LC_ALL=C sort)" != "$(cd "$target" && find . -type f | LC_ALL=C sort)" ]; then
    echo changed; return
  fi
  while IFS= read -r file; do
    if [ -x "$src/$file" ] && [ ! -x "$target/$file" ]; then echo changed; return; fi
    if [ "$file" = ./SKILL.md ]; then
      grep -vF "$marker_prefix" "$target/SKILL.md" | cmp -s - "$src/SKILL.md" || { echo changed; return; }
    else
      cmp -s "$src/$file" "$target/$file" || { echo changed; return; }
    fi
  done < <(cd "$src" && find -L . -type f)
  echo current
}

# Writes the instruction block into a file, replacing an earlier block if present.
install_block() {
  local file="$1" tmp
  mkdir -p "$(dirname "$file")"
  touch "$file"
  tmp="$(mktemp)"
  awk -v s="$block_start" -v e="$block_end" '$0 == s { skip = 1 } !skip { print } $0 == e { skip = 0 }' "$file" > "$tmp"
  { cat "$tmp"; [ -s "$tmp" ] && echo; echo "$block_start"; cat "$here"/instructions/*.md; echo "$block_end"; } > "$file"
  rm -f "$tmp"
  echo "wrote instruction block to $file"
}

uninstall_block() {
  local file="$1" tmp
  [ -f "$file" ] || return 0
  grep -qF "$block_start" "$file" || return 0
  tmp="$(mktemp)"
  awk -v s="$block_start" -v e="$block_end" '$0 == s { skip = 1 } !skip { print } $0 == e { skip = 0 }' "$file" > "$tmp"
  mv "$tmp" "$file"
  echo "removed instruction block from $file"
}

block_state() {
  local file="$1"
  if [ ! -f "$file" ] || ! grep -qF "$block_start" "$file"; then echo missing; return; fi
  if awk -v s="$block_start" -v e="$block_end" '$0 == e { inside = 0 } inside { print } $0 == s { inside = 1 }' "$file" \
    | cmp -s - <(cat "$here"/instructions/*.md); then
    echo current
  else
    echo changed
  fi
}

# Says when a CLI differs from the version tests/live.sh last passed on.
version_notes() {
  local file="$here/research/verified-versions" cli verified installed
  [ -f "$file" ] || return 0
  while read -r cli verified; do
    # Unset, the Superset wrappers don't report these calls as the workspace's agent.
    case "$cli" in
      claude) installed="$(env -u SUPERSET_TERMINAL_ID -u SUPERSET_TAB_ID -u SUPERSET_PANE_ID claude --version 2>/dev/null | awk '{ print $1 }' || true)" ;;
      codex) installed="$(env -u SUPERSET_TERMINAL_ID -u SUPERSET_TAB_ID -u SUPERSET_PANE_ID codex --version 2>/dev/null | awk '{ print $NF }' || true)" ;;
      *) continue ;;
    esac
    if [ -n "$installed" ] && [ "$installed" != "$verified" ]; then
      echo "note: $cli is $installed, but the skills were last verified on $verified; run tests/live.sh"
    fi
  done < "$file"
}

case "${1:-install}" in
  install)
    status=0
    for src in "$here"/skills/*/; do install_skill "${src%/}" || status=1; done
    for file in "${instruction_files[@]}"; do install_block "$file"; done
    exit "$status"
    ;;
  --check|check)
    status=0
    for src in "$here"/skills/*/; do
      state="$(skill_state "${src%/}")"
      echo "$(basename "$src"): $state"
      if [ "$state" != current ]; then status=1; fi
      warn_shadow "$(basename "$src")"
    done
    for file in "${instruction_files[@]}"; do
      state="$(block_state "$file")"
      echo "instruction block in $file: $state"
      if [ "$state" != current ]; then status=1; fi
    done
    version_notes
    exit "$status"
    ;;
  --uninstall|uninstall)
    for src in "$here"/skills/*/; do uninstall_skill "${src%/}"; done
    for file in "${instruction_files[@]}"; do uninstall_block "$file"; done
    ;;
  *)
    echo "usage: $0 [--check|--uninstall]" >&2
    exit 2
    ;;
esac
