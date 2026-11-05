#!/usr/bin/env bash
# Exercises the scripts in a throwaway repository. No dependencies beyond git and bash.
set -u
root=$(cd "$(dirname "$0")/.." && pwd)
s="$root/scripts"
work=$(mktemp -d)
runners=
cleanup() {
  trap '' INT TERM
  for pid in $runners; do kill -TERM "$pid" 2>/dev/null || true; done
  wait 2>/dev/null || true
  rm -rf "$work"
}
trap cleanup EXIT
trap 'exit 143' INT TERM
fails=0
pass() { printf 'ok   %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; fails=$((fails + 1)); }
check() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 (expected $3, got $2)"; fi; }

export TOWER_POLL=1
cd "$work"
git init -q -b main repo; cd repo
git config user.email t@example.com; git config user.name t
echo one > a.txt; git add a.txt; git commit -qm init
git worktree add -q -b area/one ../one
git worktree add -q -b area/two ../two
git worktree add -q -b area/three ../three
git worktree add -q -b area/four ../four

"$s/tower-init.sh" >/dev/null
home=$(git rev-parse --git-common-dir); home=$(cd "$home" && pwd)/watchtower
[ -f "$home/brief.md" ] && pass "init writes the brief" || fail "init writes the brief"

# Gate
"$s/tower-gate.sh" add one two three >/dev/null
"$s/tower-gate.sh" add four >/dev/null 2>&1; check "gate refuses a fourth" "$?" 1
(cd ../four && "$s/runway.sh" parked true >/dev/null); check "parked worktree gets 75" "$?" 75
(cd ../four && "$s/runway.sh" parked true | grep -q PARKED); check "parked message tells what to do" "$?" 0

# Exit codes
(cd ../one && "$s/runway.sh" ok true >/dev/null); check "success passes through" "$?" 0
(cd ../one && "$s/runway.sh" bad sh -c 'exit 7' >/dev/null); check "failure code passes through" "$?" 7
(cd ../one && TOWER_TIMEOUT=2 "$s/runway.sh" hung sleep 60 >/dev/null); check "timeout gives 124" "$?" 124
# A dead holder does not block forever.
mkdir -p "$home/runways/1"; echo 999999 > "$home/runways/1/pid"
(cd ../one && TOWER_RUNWAYS=1 "$s/runway.sh" stale true >/dev/null); check "stale runway is recovered" "$?" 0

# Priority goes first.
"$s/tower-gate.sh" off >/dev/null
order2="$work/order2"; : > "$order2"
(cd ../one && exec env TOWER_RUNWAYS=1 "$s/runway.sh" holder sleep 3 >/dev/null) &
runners="$runners $!"
sleep 1.5
(cd ../one && exec env TOWER_RUNWAYS=1 "$s/runway.sh" normal sh -c "echo normal >> '$order2'" >/dev/null) &
runners="$runners $!"
sleep 1.1
(cd ../one && exec env TOWER_RUNWAYS=1 "$s/runway.sh" --priority urgent sh -c "echo urgent >> '$order2'" >/dev/null) &
runners="$runners $!"
wait
runners=
check "priority overtakes the queue" "$(tr '\n' ' ' < "$order2")" "urgent normal "

# Concurrent admission, actual overlapping checks and process-tree cleanup.
"$root/tests/runtime.sh"; check "runtime regressions" "$?" 0

# Status and landing report
"$s/tower-status.sh" | grep -q 'area/two' ; check "status lists worktrees" "$?" 0
(cd ../two && echo two > b.txt && git add b.txt && git commit -qm "Add b" )
report=$("$s/land-check.sh" area/two main)
printf '%s' "$report" | grep -q 'fast-forward possible'; check "land-check sees a fast-forward" "$?" 0
printf '%s' "$report" | grep -q 'no textual conflict'; check "land-check simulates the merge" "$?" 0
(cd ../three && echo clash > a.txt && git add a.txt && git commit -qm "Clash one")
echo other > a.txt; git add a.txt; git commit -qm "Clash two"
report=$("$s/land-check.sh" area/three main)
printf '%s' "$report" | grep -q 'CONFLICTS'; check "land-check finds a real conflict" "$?" 0
printf '%s' "$report" | grep -q 'needs a rebase'; check "land-check sees the base moved" "$?" 0
(cd ../four && printf 'token = "%s"\n' "ghp_$(printf 'a%.0s' 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2)" > s.txt && git add s.txt && git commit -qm "Oops")
"$s/land-check.sh" area/four main | grep -q 'possible secret in s.txt'; check "land-check flags a token" "$?" 0

# Stdin reaches the command
in=$(cd ../one && echo data | "$s/runway.sh" stdin sh -c 'cat')
check "stdin reaches the command" "$in" data

# Gate guards
"$s/tower-gate.sh" add typo-folder >/dev/null 2>&1; check "gate refuses an unknown worktree" "$?" 1
"$s/tower-gate.sh" add --force later-folder >/dev/null; check "gate --force allows it" "$?" 0
"$s/tower-gate.sh" rm repo 2>/dev/null >/dev/null; "$s/tower-gate.sh" list | grep -q '  repo'; check "gate keeps the base checkout" "$?" 0
"$s/tower-gate.sh" off >/dev/null

# Secrets are named, not printed
out=$("$s/land-check.sh" area/four main)
printf '%s' "$out" | grep -q 'ghp_'; check "land-check does not print the token" "$?" 1

# Overlap
(cd ../one && echo x > b.txt && git add b.txt && git commit -qm "Also b")
"$s/tower-overlap.sh" main | grep -q 'area/one <> area/two: 1 shared'; check "overlap finds shared files" "$?" 0

# Base guessing without origin or main
git init -q -b trunk ../plain; cd ../plain; git config user.email t@example.com; git config user.name t
echo 1 > a; git add a; git commit -qm i; git checkout -qb side; echo 2 > b; git add b; git commit -qm s; git checkout -q trunk
"$s/land-check.sh" side | grep -q 'base:      trunk'; check "base falls back to the main checkout branch" "$?" 0
"$s/land-check.sh" side nosuch >/dev/null 2>&1; check "unknown base is an error" "$?" 2
git checkout -q --orphan orph; git commit -qm o; git checkout -q trunk
"$s/land-check.sh" orph 2>&1 | grep -q 'no common history'; check "unrelated history is named" "$?" 0

echo
if [ "$fails" -eq 0 ]; then echo "all passed"; else echo "$fails failed"; exit 1; fi
