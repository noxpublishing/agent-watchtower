#!/usr/bin/env bash
# The whole fleet on one screen, kept short because the tower reads it often.
set -u
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"
home=$(tower_home) || exit 2
base=$(base_branch)
limit=${TOWER_TIMEOUT:-5400}
now=$(date +%s)

echo "base: $base @ $(git rev-parse --short "$base" 2>/dev/null)"
if command -v gh >/dev/null 2>&1; then
  ci=$(gh run list --branch "$base" --limit 1 --json headSha,status,conclusion \
    -q '.[0] | .headSha[0:7] + " " + .status + " " + .conclusion' 2>/dev/null) && [ -n "$ci" ] && echo "ci:   $ci"
  done_run=$(gh run list --branch "$base" --status completed --limit 1 --json headSha,conclusion \
    -q '.[0] | .headSha[0:7] + " " + .conclusion' 2>/dev/null)
  case "$done_run" in
    *success|"") ;;
    *) echo "ci:   WARNING, last finished run is not green: $done_run" ;;
  esac
fi

echo
echo "runways:"
busy=0
for lane in "$home"/runways/*; do
  [ -d "$lane" ] || continue
  busy=$((busy + 1))
  started=$(cat "$lane/started" 2>/dev/null || echo "$now")
  age=$(( now - started ))
  flag=""
  [ "$age" -gt $(( limit * 3 / 4 )) ] && flag="  <- close to the time limit, check for a hang"
  printf '  %-22s %-30s %4dm%s\n' "$(cat "$lane/label" 2>/dev/null)" "$(cat "$lane/worktree" 2>/dev/null)" $(( age / 60 )) "$flag"
done
[ "$busy" -eq 0 ] && echo "  all free"
waiting=$(ls "$home/queue" 2>/dev/null | grep -c . || true)
echo "  waiting: $waiting"

echo
echo "worktrees (ahead/behind $base, uncommitted files, state):"
git worktree list --porcelain | sed -n 's/^worktree //p' | while read -r path; do
  folder=$(basename "$path")
  if [ ! -d "$path" ]; then
    printf '  %-34s MISSING, folder is gone (git worktree prune removes the entry)\n' "$folder"
    continue
  fi
  branch=$(git -C "$path" rev-parse --abbrev-ref HEAD 2>/dev/null)
  counts=$(git -C "$path" rev-list --left-right --count "HEAD...$base" 2>/dev/null | tr '\t' '/')
  dirty=$(git -C "$path" status --short 2>/dev/null | grep -c . || true)
  state=flying
  if [ -f "$home/active.list" ]; then
    active_entries "$home" | grep -qxF "$folder" || state=parked
  fi
  printf '  %-34s %-34s %-7s %3s  %s\n' "$folder" "$branch" "$counts" "$dirty" "$state"
done

if [ -f "$home/runway.log" ]; then
  echo
  echo "recent runs:"
  tail -"${TOWER_LOG_LINES:-6}" "$home/runway.log" | sed 's/^/  /'
fi
