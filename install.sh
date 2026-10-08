#!/usr/bin/env bash
# Installs the skills in skills/ for the current user, so Claude Code and
# Codex find them in every project, and adds the instruction block in
# instructions/ to both agents' per-user instruction files.
#
#   ./install.sh              install or update everything
#   ./install.sh --uninstall  remove exactly what this script installed
#
# Ownership: every installed copy carries a marker. Install refuses to replace
# a same-name skill that has no marker, and uninstall removes only marked
# copies and the marked block. Edit the source here and reinstall; edits made
# to the installed copies are overwritten.
#
# On Windows, run it from Git Bash. There ~/.claude/skills/<name> is a second
# managed copy instead of a symlink.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
marker="<!-- agentic-skills-library: managed copy, edit the source and reinstall -->"
block_start="<!-- agentic-skills-library:start -->"
block_end="<!-- agentic-skills-library:end -->"

agents_dir="$HOME/.agents/skills"       # read by Codex
claude_dir="$HOME/.claude/skills"       # read by Claude Code
instruction_files=("$HOME/.claude/CLAUDE.md" "$HOME/.codex/AGENTS.md")

# On Windows, Git Bash's ln -s makes a plain copy unless Developer Mode is on and
# MSYS=winsymlinks:nativestrict is set. So there ~/.claude/skills gets a marked
# copy, which the ownership checks can recognise, instead of a link.
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) windows=1 ;;
  *) windows=0 ;;
esac

# Claude Code and Codex find the home folder through Windows, not through bash's
# HOME, so say so when the two differ, as they do under Cygwin.
if [ "$windows" = 1 ] && [ -n "${USERPROFILE:-}" ] && [ "$(cygpath -u "$USERPROFILE")" != "${HOME%/}" ]; then
  echo "warning: HOME is $HOME, but Claude Code and Codex look under $(cygpath -u "$USERPROFILE")" >&2
fi

# Windows only. There rm can't delete a file that another program holds open, so
# it can leave part of a copy behind without its marker, and cp -R would then put
# the new copy inside it. Moving the folder aside fails as a whole instead, so
# the copy stays complete and the next run can replace it.
remove_whole() {
  [ -e "$1" ] || [ -L "$1" ] || return 0
  rm -rf "$1.old"
  if ! mv -T "$1" "$1.old" 2> /dev/null; then
    echo "could not remove $1: close whatever has it or a file in it open and run this again" >&2
    return 1
  fi
  rm -rf "$1.old"
}

managed() { [ -f "$1/SKILL.md" ] && grep -qF "$marker" "$1/SKILL.md"; }

install_skill() {
  local src="$1" name target link
  name="$(basename "$src")"; target="$agents_dir/$name"; link="$claude_dir/$name"
  if [ -e "$target" ] && ! managed "$target"; then
    echo "refusing to replace $target: it is not a copy made by this script" >&2
    return 1
  fi
  if [ "$windows" = 1 ]; then
    if [ -e "$link" ] && ! managed "$link"; then
      echo "refusing to replace $link: it is not a copy made by this script" >&2
      return 1
    fi
  elif [ -e "$link" ] && [ "$(readlink "$link" || true)" != "$target" ]; then
    echo "refusing to replace $link: it does not point at $target" >&2
    return 1
  fi
  if [ "$windows" = 1 ]; then remove_whole "$target" || return 1; fi
  rm -rf "$target"
  mkdir -p "$agents_dir" "$claude_dir"
  cp -R "$src" "$target"
  # The marker goes right after the front matter, so the skill's metadata stays first.
  awk -v m="$marker" 'BEGIN { n = 0 } { print } /^---$/ { n++; if (n == 2) print m }' "$src/SKILL.md" > "$target/SKILL.md"
  find "$target" -name '*.sh' -exec chmod +x {} +
  if [ "$windows" = 1 ]; then
    remove_whole "$link" || return 1
    cp -R "$target" "$link"
    echo "installed $name, copied to $claude_dir"
  else
    ln -sfn "$target" "$link"
    echo "installed $name"
  fi
}

uninstall_skill() {
  local src="$1" name target link
  name="$(basename "$src")"; target="$agents_dir/$name"; link="$claude_dir/$name"
  if [ -L "$link" ] && [ "$(readlink "$link")" = "$target" ]; then rm "$link"; fi
  if [ "$windows" = 1 ] && [ -e "$link" ] && [ ! -L "$link" ]; then
    if managed "$link"; then remove_whole "$link"
    else echo "left $link alone: it is not a copy made by this script" >&2; fi
  fi
  if [ "$windows" = 1 ] && managed "$target"; then remove_whole "$target"; echo "removed $name"; fi
  if [ -e "$target" ]; then
    if managed "$target"; then rm -rf "$target"; echo "removed $name"
    else echo "left $target alone: it is not a copy made by this script" >&2; fi
  fi
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

case "${1:-install}" in
  install)
    status=0
    for src in "$here"/skills/*/; do install_skill "${src%/}" || status=1; done
    for file in "${instruction_files[@]}"; do install_block "$file"; done
    exit "$status"
    ;;
  --uninstall|uninstall)
    for src in "$here"/skills/*/; do uninstall_skill "${src%/}"; done
    for file in "${instruction_files[@]}"; do uninstall_block "$file"; done
    ;;
  *)
    echo "usage: $0 [--uninstall]" >&2
    exit 2
    ;;
esac
