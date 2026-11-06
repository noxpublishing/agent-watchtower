#!/usr/bin/env bash
# Run an expensive verification under the tower's rules.
#   runway.sh [--priority] <label> <command> [args...]
#
# Jobs share the runways first come, first served. How many is yours to set:
# tower-capacity.sh set --runways <n>, or TOWER_RUNWAYS. Unset, one per four cores.
# Exit codes: the command's own code, or
#   75  parked: this worktree is not on the active list. Do not retry; wait for a call.
#       If nobody is acting as the tower, ask the human.
#   124 hung: stopped after TOWER_TIMEOUT seconds (default 5400). Find the cause first.
#   143 aborted by a person or the tower. Retrying is fine.
#   2   usage error, or a runway without an owner that needs inspecting.
set -u
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"

priority=5
if [ "${1:-}" = "--priority" ]; then priority=0; shift; fi
if [ "$#" -lt 2 ]; then
  sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//' >&2
  exit 2
fi
label=$(clean_text "$1"); shift

home=$(tower_home) || exit 2
name=$(worktree_name)
runways=$(runway_limit "$home")
limit=${TOWER_TIMEOUT:-5400}
# Seconds allowed for TERM before killing the entire command process group.
kill_grace=${TOWER_KILL_GRACE:-20}
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
job_reaped=0
stop_job() {
  [ -n "$job" ] || return 0
  # Once reaped, the PID may belong to someone else: only the process group remains,
  # and it can outlive its leader through children that ignore TERM.
  if [ "$job_reaped" -eq 1 ]; then
    kill -TERM -- "-$job" 2>/dev/null || { job=; return 0; }
  else
    # The positive PID fallback covers a signal arriving before setsid completes.
    kill -TERM -- "-$job" 2>/dev/null || kill -TERM "$job" 2>/dev/null || true
  fi
  grace=0
  while [ "$grace" -lt "$kill_grace" ]; do
    if ! kill -0 -- "-$job" 2>/dev/null; then
      [ "$job_reaped" -eq 1 ] && break
      kill -0 "$job" 2>/dev/null || break
    fi
    sleep 1
    grace=$((grace + 1))
  done
  kill -KILL -- "-$job" 2>/dev/null || true
  if [ "$job_reaped" -eq 0 ]; then
    kill -KILL "$job" 2>/dev/null || true
    wait "$job" 2>/dev/null || true
  fi
  job=
}
cleanup() {
  stop_job
  rm -f "$ticket"
  if [ -n "$lane" ]; then rm -rf "$lane"; fi
}
on_signal() {
  trap '' INT TERM
  exit 143
}
trap on_signal INT TERM
trap cleanup EXIT

ownerless_since=()
drop_stale() {
  local item pid index first_seen
  for item in "$home"/queue/*; do
    [ -e "$item" ] || continue
    pid=${item##*-}
    kill -0 "$pid" 2>/dev/null || rm -f "$item"
  done
  for item in "$home"/runways/*; do
    [ -d "$item" ] || continue
    index=${item##*/}
    case "$index" in ''|*[!0-9]*) continue ;; esac
    index=$((10#$index))
    pid=$(cat "$item/pid" 2>/dev/null) || pid=
    if [ -z "$pid" ]; then
      # mkdir and writing pid are not atomic. Allow a live claimant time to
      # publish, but never delete an ownerless lane that might still be live.
      first_seen=${ownerless_since[$index]:-$(date +%s)}
      ownerless_since[$index]=$first_seen
      if [ "$(( $(date +%s) - first_seen ))" -ge 5 ]; then
        echo "watchtower: runway has no owner PID: $item. Inspect running checks; remove it only if orphaned, then retry." >&2
        return 2
      fi
      continue
    fi
    ownerless_since[$index]=
    if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then rm -rf "$item"; fi
  done
}

position() {
  ls "$home/queue" 2>/dev/null | sort -t- -k1,1n -k2,2n -k3,3n | grep -nxF "$(basename "$ticket")" | cut -d: -f1
}

while :; do
  if parked; then say_parked; rm -f "$ticket"; exit 75; fi
  drop_stale || exit 2
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

# A separate process group, so a timeout also stops test workers and child servers.
if command -v setsid >/dev/null 2>&1; then
  setsid "$@" <&0 &
elif command -v perl >/dev/null 2>&1; then
  perl -MPOSIX -e 'POSIX::setsid(); exec @ARGV or exit 127' "$@" <&0 &
else
  python3 -c 'import os,sys; os.setsid(); os.execvp(sys.argv[1], sys.argv[1:])' "$@" <&0 &
fi
job=$!

waited=0
timed_out=0
while kill -0 "$job" 2>/dev/null; do
  if [ "$waited" -ge "$limit" ]; then
    timed_out=1
    stop_job
    break
  fi
  sleep 1
  waited=$((waited + 1))
done
if [ "$timed_out" -eq 1 ]; then
  code=124
else
  wait "$job"
  code=$?
  job_reaped=1
  stop_job
fi
printf '%s end %s %s exit=%s %ss\n' "$(date '+%F %T')" "$label" "$name" "$code" "$(( $(date +%s) - start ))" >> "$log"
exit "$code"
