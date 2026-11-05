#!/usr/bin/env bash
# Run an expensive verification under the tower's rules.
#   runway.sh [--priority] <label> <command> [args...]
#
# At most TOWER_RUNWAYS jobs run at once (default 3), first come first served.
# Exit codes: the command's own code, or
#   75  parked: this worktree is not on the active list. Do not retry; wait for a call.
#       If nobody is acting as the tower, ask the human.
#   124 hung: stopped after TOWER_TIMEOUT seconds (default 5400). Find the cause first.
#   143 aborted by a person or the tower. Retrying is fine.
set -u
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"

priority=5
if [ "${1:-}" = "--priority" ]; then priority=0; shift; fi
if [ "$#" -lt 2 ]; then
  sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//' >&2
  exit 2
fi
label=$1; shift

home=$(tower_home) || exit 2
name=$(worktree_name)
runways=${TOWER_RUNWAYS:-3}
limit=${TOWER_TIMEOUT:-5400}
log="$home/runway.log"
mkdir -p "$home/queue" "$home/runways"

parked() {
  [ -f "$home/active.list" ] && ! active_entries "$home" | grep -qxF "$name"
}
say_parked() {
  echo "PARKED: '$name' is not on the active list. Do not rerun, do not rebase, do no further work. Commit your state, end your turn and wait for the tower to call you. If nobody is acting as the tower, ask the human."
}

if parked; then say_parked; exit 75; fi

ticket="$home/queue/$priority-$(date +%s)-$$"
: > "$ticket"
lane=
job=
cleanup() {
  rm -f "$ticket"
  if [ -n "$lane" ]; then rm -rf "$lane"; fi
}
on_signal() {
  if [ -n "$job" ]; then kill -TERM -- "-$job" 2>/dev/null; fi
  cleanup
  exit 143
}
trap on_signal INT TERM
trap cleanup EXIT

drop_stale() {
  local item pid
  for item in "$home"/queue/*; do
    [ -e "$item" ] || continue
    pid=${item##*-}
    kill -0 "$pid" 2>/dev/null || rm -f "$item"
  done
  for item in "$home"/runways/*; do
    [ -d "$item" ] || continue
    pid=$(cat "$item/pid" 2>/dev/null) || continue
    if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then rm -rf "$item"; fi
  done
}

position() {
  ls "$home/queue" 2>/dev/null | sort -t- -k1,1n -k2,2n -k3,3n | grep -nxF "$(basename "$ticket")" | cut -d: -f1
}

while :; do
  if parked; then say_parked; rm -f "$ticket"; exit 75; fi
  drop_stale
  free=0
  i=1
  while [ "$i" -le "$runways" ]; do
    [ -d "$home/runways/$i" ] || free=$((free + 1))
    i=$((i + 1))
  done
  pos=$(position)
  if [ -n "$pos" ] && [ "$pos" -le "$free" ]; then
    i=1
    while [ "$i" -le "$runways" ]; do
      if mkdir "$home/runways/$i" 2>/dev/null; then
        lane="$home/runways/$i"
        echo $$ > "$lane/pid"
        printf '%s\n' "$label" > "$lane/label"
        printf '%s\n' "$name" > "$lane/worktree"
        date +%s > "$lane/started"
        break
      fi
      i=$((i + 1))
    done
    [ -n "$lane" ] && break
  fi
  sleep "${TOWER_POLL:-5}"
done
rm -f "$ticket"

start=$(date +%s)
printf '%s start %s %s\n' "$(date '+%F %T')" "$label" "$name" >> "$log"

marker="$lane/timed-out"
# A separate process group, so a timeout also stops test workers and child servers.
if command -v setsid >/dev/null 2>&1; then
  setsid "$@" <&0 &
elif command -v perl >/dev/null 2>&1; then
  perl -MPOSIX -e 'POSIX::setsid(); exec @ARGV or exit 127' "$@" <&0 &
else
  python3 -c 'import os,sys; os.setsid(); os.execvp(sys.argv[1], sys.argv[1:])' "$@" <&0 &
fi
job=$!

(
  waited=0
  while kill -0 "$job" 2>/dev/null; do
    if [ "$waited" -ge "$limit" ]; then
      : > "$marker"
      kill -TERM -- "-$job" 2>/dev/null
      grace=0
      while [ "$grace" -lt 20 ] && kill -0 -- "-$job" 2>/dev/null; do
        sleep 1
        grace=$((grace + 1))
      done
      kill -KILL -- "-$job" 2>/dev/null
      exit 0
    fi
    sleep 1
    waited=$((waited + 1))
  done
) >/dev/null 2>&1 &

wait "$job"
code=$?
[ -e "$marker" ] && code=124
printf '%s end %s %s exit=%s %ss\n' "$(date '+%F %T')" "$label" "$name" "$code" "$(( $(date +%s) - start ))" >> "$log"
exit "$code"
