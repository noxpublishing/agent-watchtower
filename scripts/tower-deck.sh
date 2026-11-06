#!/usr/bin/env bash
# Put the live board beside your agents, in the best place this terminal offers.
#   tower-deck.sh            tmux: a pane on the right. macOS: a window of its own.
#   tower-deck.sh --print    say what it would do, and the command to run by hand
# Quit the deck with q. Claude Code's desktop app has its own panel and terminal tabs.
set -u
here=$(cd "$(dirname "$0")" && pwd)
root=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "watchtower: not inside a git repository" >&2; exit 2; }
board="$here/tower-board.sh"
command=$(printf 'cd %q && %q --watch' "$root" "$board")
dry=0
[ "${1:-}" != --print ] || dry=1

if [ -n "${TMUX:-}" ]; then
  if tmux list-panes -F '#{pane_title}' | grep -qx watchtower-deck; then
    echo "already open in this window"
    exit 0
  fi
  width=$(( $(tmux display -p '#{window_width}') * 2 / 5 ))
  [ "$width" -ge 46 ] || width=46
  if [ "$dry" -eq 1 ]; then echo "tmux pane, $width columns: $command"; exit 0; fi
  tmux split-window -d -h -l "$width" "$command"
  tmux select-pane -t '{right}' -T watchtower-deck
  echo "deck open in a tmux pane on the right"
  exit 0
fi

if [ "$(uname)" = Darwin ]; then
  case "${TERM_PROGRAM:-}" in
    iTerm.app) app=iTerm ;;
    *) app=Terminal ;;
  esac
  if [ "$dry" -eq 1 ]; then echo "$app window: $command"; exit 0; fi
  if [ "$app" = iTerm ]; then
    osascript -e 'on run argv' -e 'tell application "iTerm" to create window with default profile command "/bin/bash -lc " & quoted form of (item 1 of argv)' -e 'end run' "$command" >/dev/null
  else
    osascript -e 'on run argv' -e 'tell application "Terminal" to do script (item 1 of argv)' -e 'tell application "Terminal" to activate' -e 'end run' "$command" >/dev/null
  fi
  echo "deck open in a new $app window"
  exit 0
fi

echo "no way to open a window from here. Run this in a second terminal:"
echo "$command"
