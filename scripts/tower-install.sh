#!/usr/bin/env bash
# Install this checkout for your agents. Links instead of copying, so `git pull` updates it.
#   tower-install.sh claude    skill, flight board and worker classes for Claude Code
#   tower-install.sh codex     skill and worker classes for Codex
#   tower-install.sh all
# Existing files of another origin are left alone and named.
set -u
root=$(cd "$(dirname "$0")/.." && pwd)

link_skill() {
  local target=$1
  mkdir -p "$(dirname "$target")"
  if [ -L "$target" ] && [ "$(cd "$target" 2>/dev/null && pwd -P)" = "$(cd "$root" && pwd -P)" ]; then
    echo "already linked: $target"
  elif [ -e "$target" ] || [ -L "$target" ]; then
    echo "left alone, it is not this checkout: $target"
    return 1
  else
    ln -s "$root" "$target"
    echo "linked: $target"
  fi
}

link_skill_part() {
  mkdir -p "$(dirname "$1")"
  if [ -L "$1" ] || [ -e "$1" ]; then
    echo "already there: $1"
  else
    ln -s "$root/skills/watchtower-setup" "$1"
    echo "linked: $1"
  fi
}

# Codex reads worker classes as TOML; the Markdown files stay the only source.
codex_agents() {
  local dir=$1 file name description effort target tmp
  mkdir -p "$dir"
  for file in "$root"/agents/tower-*.md; do
    name=$(sed -n 's/^name: //p' "$file" | head -1)
    description=$(sed -n 's/^description: "\(.*\)"$/\1/p' "$file" | head -1)
    effort=$(sed -n 's/^effort: //p' "$file" | head -1)
    # Codex keeps your model, so the top class differs by effort alone.
    [ "$name" != tower-ace ] || effort=xhigh
    target="$dir/$name.toml"
    tmp="$target.$$"
    {
      printf 'name = "%s"\n' "$name"
      printf 'description = "%s"\n' "$description"
      printf 'model_reasoning_effort = "%s"\n' "$effort"
      printf 'developer_instructions = """\n'
      awk 'seen >= 2 { print } /^---$/ { seen++ }' "$file" | sed "s|<skill>|$root|g"
      printf '"""\n'
    } > "$tmp"
    mv "$tmp" "$target"
    echo "wrote: $target"
  done
}

install_claude() {
  link_skill "${CLAUDE_HOME:-$HOME/.claude}/skills/watchtower" || exit 1
  echo "Claude Code loads the flight board and the worker classes from that folder. Start a new session."
}

install_codex() {
  local home=${CODEX_HOME:-$HOME/.codex}
  link_skill "$home/skills/watchtower" || exit 1
  link_skill_part "$home/skills/watchtower-setup"
  codex_agents "$home/agents"
  echo "Codex has no side panel. Keep the board beside it: scripts/tower-deck.sh, or scripts/tower-board.sh --html --watch for the browser."
}

case "${1:-}" in
  claude) install_claude ;;
  codex) install_codex ;;
  all) install_claude; install_codex ;;
  *) sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
esac
