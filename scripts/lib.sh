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

# Serialize writers without flock (not present on stock macOS). A lock whose
# recorded owner is dead gets recovered. A lock without a PID may be a live writer
# that has not published yet, so it is left for inspection.
lock_recover_dead() {
  local lock=$1 reap="$1.reap" owner
  # A reaper that died mid-way leaves its mutex behind; nothing holds one for a minute.
  if [ -n "$(find "$reap" -maxdepth 0 -mmin +1 2>/dev/null)" ]; then rmdir "$reap" 2>/dev/null || true; fi
  mkdir "$reap" 2>/dev/null || return 0
  # Read inside the mutex: another writer may have recovered and re-locked already.
  owner=$(cat "$lock/pid" 2>/dev/null) || owner=
  if [ -n "$owner" ] && ! kill -0 "$owner" 2>/dev/null; then
    rm -f "$lock/pid"
    rmdir "$lock" 2>/dev/null || true
  elif [ -z "$owner" ] && [ "${2:-keep}" = expire ] && [ -n "$(find "$lock" -maxdepth 0 -mmin +1 2>/dev/null)" ]; then
    rmdir "$lock" 2>/dev/null || true
  fi
  rmdir "$reap" 2>/dev/null || true
}

# lock_take <dir> [expire]: "expire" also frees an ownerless lock older than a minute.
# The gate keeps such a lock for inspection; a per-area lock guards one quick write.
lock_take() {
  local attempts=0
  held_lock=$1
  while ! mkdir "$held_lock" 2>/dev/null; do
    lock_recover_dead "$held_lock" "${2:-keep}"
    if [ "$attempts" -ge 25 ]; then
      echo "watchtower: lock busy: $held_lock. Inspect its owner/processes; remove it only if orphaned, then retry." >&2
      held_lock=
      return 2
    fi
    sleep 0.2
    attempts=$((attempts + 1))
  done
  printf '%s\n' "$$" > "$held_lock/pid"
  trap 'lock_release' EXIT
  trap 'exit 143' TERM
  trap 'exit 130' INT
}

lock_release() {
  [ -n "${held_lock:-}" ] || return 0
  rm -f "$held_lock/pid"
  rmdir "$held_lock" 2>/dev/null || true
  held_lock=
}

gate_lock() { lock_take "$1/gate.lock"; }

# Limits belong to the person running the fleet, per repository, in `config`.
config_get() {
  [ -f "$1/config" ] || return 0
  sed -n "s/^$2=//p" "$1/config" | tail -1
}

config_set() {
  local tmp="$1/config.$$"
  { [ -f "$1/config" ] && grep -v "^$2=" "$1/config"; printf '%s=%s\n' "$2" "$3"; } > "$tmp"
  mv "$tmp" "$1/config"
}

machine_cores() {
  getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4
}

is_count() {
  case "$1" in ''|*[!0-9]*) return 1 ;; esac
  [ "${#1}" -le 6 ] && [ "$1" -gt 0 ]
}

# Text that reaches shells, JSON, SVG and terminals: no control characters, whoever wrote it.
clean_text() {
  printf '%s' "$1" | LC_ALL=C tr -d '\000-\037\177'
}

# How many areas may fly. Empty means no limit: only the person sets one.
flying_limit() {
  local value=${TOWER_MAX_ACTIVE:-$(config_get "$1" flying)}
  if is_count "$value"; then printf '%s\n' "$value"; fi
}

# How many heavy checks run at once. Unset, it follows the machine: one per four cores.
runway_limit() {
  local value=${TOWER_RUNWAYS:-$(config_get "$1" runways)} cores
  if ! is_count "$value"; then
    cores=$(machine_cores)
    value=$((cores / 4))
    [ "$value" -ge 1 ] || value=1
  fi
  printf '%s\n' "$value"
}

base_checkout_folder() {
  basename "$(git worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p')"
}

worktree_path() {
  git worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p' | while IFS= read -r path; do
    if [ "$(basename "$path")" = "$1" ]; then printf '%s\n' "$path"; break; fi
  done
}

# Areas are small key=value files, so bash, the board and the Claude Code mod read them alike.
area_get() {
  sed -n "s/^$2=//p" "$1" 2>/dev/null | tail -1
}

# area_put <file> key=value...: atomic, so a reader never sees half a file.
area_put() {
  local file=$1 tmp pair key value
  # A dotfile, so readers globbing the folder never pick up a half-written copy.
  tmp="$(dirname "$1")/.$(basename "$1").$$"
  shift
  touch "$file"
  cp "$file" "$tmp"
  for pair in "$@" "updated=$(date +%s)"; do
    key=${pair%%=*}
    value=$(clean_text "${pair#*=}")
    grep -v "^$key=" "$tmp" > "$tmp.next" || true
    printf '%s=%s\n' "$key" "$value" >> "$tmp.next"
    mv "$tmp.next" "$tmp"
  done
  mv "$tmp" "$file"
}

# The open area this worktree works on, by its bound folder name. A finished area
# may share its folder with a later one, and must not receive the later one's reports.
area_of_worktree() {
  local file
  for file in "$1"/areas/*; do
    [ -f "$file" ] || continue
    [ "$(area_get "$file" worktree)" = "$2" ] || continue
    case "$(area_get "$file" state)" in landed|dropped) continue ;; esac
    basename "$file"
    return 0
  done
  return 1
}
