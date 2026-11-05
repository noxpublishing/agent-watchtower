#!/usr/bin/env bash
# Shared helpers. State lives inside the repository's common git directory: every
# worktree sees the same state, and nothing in it can be committed by accident.

tower_home() {
  if [ -n "${TOWER_HOME:-}" ]; then
    mkdir -p "$TOWER_HOME" && printf '%s\n' "$TOWER_HOME"
    return
  fi
  local common
  common=$(git rev-parse --git-common-dir 2>/dev/null) || {
    echo "watchtower: not inside a git repository (or set TOWER_HOME)" >&2
    return 1
  }
  common=$(cd "$common" && pwd)
  mkdir -p "$common/watchtower" && printf '%s\n' "$common/watchtower"
}

worktree_name() {
  basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
}

# The base branch: $TOWER_BASE, else origin's default, else main, else master.
base_branch() {
  if [ -n "${TOWER_BASE:-}" ]; then printf '%s\n' "$TOWER_BASE"; return; fi
  local head
  head=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null) && {
    printf '%s\n' "${head#origin/}"; return
  }
  git show-ref --verify --quiet refs/heads/main && { echo main; return; }
  git show-ref --verify --quiet refs/heads/master && { echo master; return; }
  # No usual name: take the branch of the main checkout rather than guess.
  git worktree list --porcelain 2>/dev/null | sed -n 's|^branch refs/heads/||p' | head -1
}

active_entries() {
  [ -f "$1/active.list" ] || return 0
  grep -v '^[[:space:]]*\(#\|$\)' "$1/active.list" || true
}
