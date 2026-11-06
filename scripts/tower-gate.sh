#!/usr/bin/env bash
# Decide who may fly. Everyone else stays in the holding pattern.
#   tower-gate.sh list
#   tower-gate.sh add [--force] <worktree-folder-name>...
#       refuses unknown worktrees, and anything past the limit if you set one:
#       tower-capacity.sh set --flying <n>, or TOWER_MAX_ACTIVE. No limit by default.
#   tower-gate.sh room                            exit 0 if one more may fly
#   tower-gate.sh rm  <worktree-folder-name>...
#   tower-gate.sh off                             remove the gate: everyone may run
# The folder of the base checkout does not count toward the limit.
set -u
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"
home=$(tower_home) || exit 2
list="$home/active.list"
max=$(flying_limit "$home")
base_folder=$(base_checkout_folder)
# Reading needs no lock, so a stuck writer cannot hide the state.
case "${1:-list}" in list|room) ;; *) gate_lock "$home" || exit 2 ;; esac

count() { active_entries "$home" | grep -vxF "$base_folder" | grep -c . || true; }

case "${1:-list}" in
  list)
    if [ -f "$list" ]; then
      echo "active ($(count)/${max:-no limit}):"
      active_entries "$home" | sed -e "s/^$base_folder\$/$base_folder (base checkout, not counted)/" -e 's/^/  /'
    else
      echo "no gate: every worktree may run"
    fi
    ;;
  room)
    if [ -n "$max" ] && [ "$(count)" -ge "$max" ]; then
      echo "refused: your limit is $max active. Land or park one, or raise it with tower-capacity.sh set --flying <n>." >&2
      exit 1
    fi
    ;;
  add)
    shift
    force=0
    if [ "${1:-}" = "--force" ]; then force=1; shift; fi
    [ -f "$list" ] || printf '# Worktree folders allowed on the runways, one per line.\n%s\n' "$base_folder" > "$list"
    for item in "$@"; do
      if active_entries "$home" | grep -qxF "$item"; then continue; fi
      if [ "$force" -eq 0 ] && ! git worktree list --porcelain | sed -n 's/^worktree //p' | while read -r path; do basename "$path"; done | grep -qxF "$item"; then
        echo "refused: no worktree folder named $item. Check tower-status.sh, or use --force if it is about to exist." >&2
        exit 1
      fi
      if [ "$force" -eq 0 ] && [ -n "$max" ] && [ "$(count)" -ge "$max" ]; then
        echo "refused: $item. Your limit is $max active. Land or park one, raise it with tower-capacity.sh set --flying <n>, or use --force for a short integration run." >&2
        exit 1
      fi
      printf '%s\n' "$item" >> "$list"
      echo "active: $item"
    done
    ;;
  rm)
    shift
    [ -f "$list" ] || exit 0
    for item in "$@"; do
      if [ "$item" = "$base_folder" ]; then
        echo "kept: $item is the base checkout, where the tower itself verifies" >&2
        continue
      fi
      grep -vxF "$item" "$list" > "$list.tmp" || true
      mv "$list.tmp" "$list"
      echo "parked: $item"
    done
    ;;
  off) rm -f "$list"; echo "gate removed" ;;
  *) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
esac
