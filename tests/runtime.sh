#!/usr/bin/env bash
# Portable Bash regression fixtures: kill only processes created by this test.
set -u
root=$(cd "$(dirname "$0")/.." && pwd)
s="$root/scripts"
work=$(mktemp -d)
runners=
cleanup() {
  trap '' INT TERM
  for pid in $runners; do kill -TERM "$pid" 2>/dev/null || true; done
  for file in "$work"/tree-*/leader.pid; do
    [ -f "$file" ] || continue
    pid=$(cat "$file")
    kill -KILL -- "-$pid" 2>/dev/null || true
  done
  wait 2>/dev/null || true
  rm -rf "$work"
}
trap cleanup EXIT
trap 'exit 143' TERM
trap 'exit 130' INT
fail() { echo "FAIL $*"; exit 1; }
pass() { echo "ok   $*"; }
alive() {
  # Unreaped orphan zombies are no longer executing and cannot hold resources.
  state=$(ps -o stat= -p "$1" 2>/dev/null) || return 1
  case "$state" in *Z*|'') return 1 ;; esac
}
await_file() {
  tries=0
  while [ ! -f "$1" ]; do
    tries=$((tries + 1)); [ "$tries" -lt 100 ] || fail "missing fixture $1"
    sleep 0.1
  done
}
export TOWER_POLL=0.1 TOWER_KILL_GRACE=1 TOWER_TIMEOUT=15
# Synthetic repositories must not share the caller's real tower state.
unset TOWER_HOME
git init -q -b main "$work/repo"
cd "$work/repo" || exit 1
git -c user.name=Test -c user.email=test@example.invalid commit --allow-empty -qm init
"$s/tower-init.sh" >/dev/null
home="$work/repo/.git/watchtower"
for i in 1 2 3 4 5 6; do git worktree add -q -b "area/$i" "$work/w$i"; done

# Release all six writers together; repeat to expose the original check/add race.
for trial in 1 2 3 4 5; do
  "$s/tower-gate.sh" off >/dev/null
  "$s/tower-init.sh" >/dev/null
  release="$work/gate-$trial"
  pids=
  for i in 1 2 3 4 5 6; do
    (while [ ! -f "$release" ]; do sleep 0.1; done
     exec env TOWER_MAX_ACTIVE=1 "$s/tower-gate.sh" add "w$i" >"$work/add-$i.log" 2>&1) &
    pids="$pids $!"; runners="$runners $!"
  done
  touch "$release"
  admitted=0
  for pid in $pids; do
    if wait "$pid"; then admitted=$((admitted + 1)); else
      code=$?; [ "$code" -eq 1 ] || fail "gate writer returned $code"
    fi
  done
  runners=
  [ "$admitted" -eq 1 ] || fail "concurrent gate admitted $admitted workers"
  entries=$(grep -v '^#' "$home/active.list" | grep -vc '^repo$' || true)
  [ "$entries" -eq 1 ] || fail "gate contains $entries workers"
done
pass "six concurrent gate writers respect max=1 in five trials"

# An orphaned lock fails boundedly and is left for inspection.
mkdir "$home/gate.lock"
"$s/tower-gate.sh" add --force w2 >"$work/lock.log" 2>&1
[ "$?" -eq 2 ] || fail "orphaned gate lock did not fail"
grep -q 'Inspect its owner' "$work/lock.log" || fail "gate lock needs actionable error"
[ -d "$home/gate.lock" ] || fail "orphaned lock was deleted"
rmdir "$home/gate.lock"
pass "orphaned gate lock fails without deleting another owner's lock"

# A lock left by a dead writer recovers by itself, and reading never needs the lock.
mkdir "$home/gate.lock"
"$s/tower-gate.sh" list >/dev/null || fail "list needs no lock"
rmdir "$home/gate.lock"
mkdir "$home/gate.lock"; echo 999999 > "$home/gate.lock/pid"
"$s/tower-gate.sh" add --force w3 >/dev/null || fail "dead owner's lock was not recovered"
[ ! -e "$home/gate.lock" ] || fail "gate lock left behind"
# A lock with a live owner stays.
mkdir "$home/gate.lock"; echo "$$" > "$home/gate.lock/pid"
"$s/tower-gate.sh" add --force w4 >/dev/null 2>&1
[ "$?" -eq 2 ] || fail "live owner's lock did not block"
[ -f "$home/gate.lock/pid" ] || fail "live owner's lock was removed"
rm "$home/gate.lock/pid"; rmdir "$home/gate.lock"
pass "dead writer's lock recovers, a live writer's lock stays"
"$s/tower-gate.sh" off >/dev/null

# Two lanes must really overlap; a start barrier prevents a serial false pass.
mkdir "$work/in"
cat > "$work/check.sh" <<'SH'
touch "$1/in/$$"
ls "$1/in" | wc -l >> "$1/peak"
while [ ! -f "$1/release" ]; do sleep 0.1; done
sleep 1
rm "$1/in/$$"
SH
pids=
for i in 1 2 3 4 5 6; do
  (exec env TOWER_RUNWAYS=2 "$s/runway.sh" "capacity-$i" bash "$work/check.sh" "$work" >"$work/job-$i.log" 2>&1) &
  pids="$pids $!"; runners="$runners $!"
done
tries=0
while [ "$(ls "$work/in" | wc -l | tr -d ' ')" -lt 2 ]; do
  tries=$((tries + 1)); [ "$tries" -lt 100 ] || fail "two checks never overlapped"
  sleep 0.1
done
touch "$work/release"
for pid in $pids; do wait "$pid" || fail "capacity check failed"; done
runners=
peak=$(sort -n "$work/peak" | tail -1 | tr -d ' ')
[ "$peak" -eq 2 ] || fail "expected actual peak 2, got $peak"
pass "six competing checks overlap at exactly two lanes"

# Order: with one lane, waiting checks run first come, first served.
order="$work/order"; : > "$order"
(exec env TOWER_RUNWAYS=1 "$s/runway.sh" order-hold sleep 5 >/dev/null 2>&1) &
pids="$!"; runners="$runners $!"
sleep 1.2
for i in 1 2 3; do
  (exec env TOWER_RUNWAYS=1 "$s/runway.sh" "order-$i" sh -c "echo $i >> '$order'" >/dev/null 2>&1) &
  pids="$pids $!"; runners="$runners $!"
  sleep 1.2
done
for pid in $pids; do wait "$pid" || fail "ordered check failed"; done
runners=
[ "$(tr -d '\n' < "$order")" = 123 ] || fail "not first come, first served: $(tr -d '\n' < "$order")"
pass "waiting checks run first come, first served"

# A lane with no pid may be an incomplete live claim: report, never erase it.
mkdir "$home/runways/1"
TOWER_RUNWAYS=1 "$s/runway.sh" ownerless true >"$work/ownerless.log" 2>&1
[ "$?" -eq 2 ] || fail "ownerless lane did not fail boundedly"
grep -q 'no owner PID' "$work/ownerless.log" || fail "missing ownerless diagnosis"
[ -d "$home/runways/1" ] || fail "ownerless lane was unsafely removed"
rmdir "$home/runways/1"
pass "ownerless lane fails boundedly and remains available for inspection"

cat > "$work/child.sh" <<'SH'
trap '' TERM
echo "$$" > "$1"
while :; do sleep 1; done
SH
cat > "$work/parent.sh" <<'SH'
echo "$$" > "$1/leader.pid"
bash "$2/child.sh" "$1/child.pid" &
wait
SH
# A normal finish still stops children left behind, without touching the old PID.
cat > "$work/leaves-child.sh" <<'SH'
sh -c 'trap "" TERM; echo $$ > "$1"; while :; do sleep 1; done' _ "$1" &
sleep 0.5
exit 0
SH
TOWER_RUNWAYS=1 "$s/runway.sh" leftover bash "$work/leaves-child.sh" "$work/left.pid" >/dev/null 2>&1
code=$?
[ "$code" -eq 0 ] || fail "normal finish returned $code"
left=$(cat "$work/left.pid")
alive "$left" && fail "child left behind after a normal finish"
pass "a normal finish stops leftover children and keeps its exit code"

for mode in abort timeout; do
  dir="$work/tree-$mode"; mkdir "$dir"
  (exec env TOWER_RUNWAYS=1 TOWER_TIMEOUT=3 "$s/runway.sh" "$mode" bash "$work/parent.sh" "$dir" "$work" >"$dir/log" 2>&1) &
  runner=$!; runners="$runners $runner"
  await_file "$dir/child.pid"
  leader=$(cat "$dir/leader.pid"); child=$(cat "$dir/child.pid")
  alive "$child" || fail "stubborn child did not start"
  if [ "$mode" = abort ]; then kill -TERM "$runner"; expected=143; else expected=124; fi
  tries=0
  while alive "$runner"; do
    if [ ! -d "$home/runways/1" ] && alive "$child"; then
      fail "$mode released its lane while the child was executing"
    fi
    tries=$((tries + 1)); [ "$tries" -lt 100 ] || fail "$mode did not finish"
    sleep 0.1
  done
  wait "$runner"; code=$?
  runners=
  [ "$code" -eq "$expected" ] || fail "$mode returned $code, expected $expected"
  alive "$leader" && fail "$mode left leader executing"
  alive "$child" && fail "$mode left TERM-ignoring child executing"
  [ ! -d "$home/runways/1" ] || fail "$mode kept the slot"
  rm "$dir/leader.pid"
  pass "$mode kills TERM-ignoring descendants before releasing its lane ($code)"
done
