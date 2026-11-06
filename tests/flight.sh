#!/usr/bin/env bash
# The flight plan, the boards that read it and the limits the person sets.
set -u
s="$(cd "$(dirname "$0")/.." && pwd)/scripts"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fails=0
pass() { printf 'ok   %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; fails=$((fails + 1)); }
check() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 (expected $3, got $2)"; fi; }
has() { if printf '%s' "$2" | grep -qF -- "$3"; then pass "$1"; else fail "$1 (no '$3' in: $2)"; fi; }
lacks() { if printf '%s' "$2" | grep -qF -- "$3"; then fail "$1 (found '$3')"; else pass "$1"; fi; }
area="$s/tower-area.sh"
board="$s/tower-board.sh"
gate="$s/tower-gate.sh"
export TOWER_NO_CI=1 LANG=en_US.UTF-8 LC_ALL= TOWER_LANG=en
unset LC_ALL

cd "$work"
git init -q -b main shop; cd shop
git config user.email t@example.com; git config user.name t
echo one > a.txt; git add a.txt; git commit -qm init
"$s/tower-init.sh" >/dev/null
home=$(cd "$(git rev-parse --git-common-dir)" && pwd)/watchtower

# Limits are the person's: none is built in, and any number holds.
has "capacity shows no limit by default" "$("$s/tower-capacity.sh")" "flying no limit"
has "capacity suggests a number" "$("$s/tower-capacity.sh")" "suggest: up to"
"$s/tower-capacity.sh" set --flying 2 --runways 5 >/dev/null
has "limits persist" "$("$s/tower-capacity.sh")" "limits:  flying 2, runways 5"
check "flying limit overrides per process" "$(TOWER_MAX_ACTIVE=7 "$gate" list | sed -n 1p)" "active (0/7):"
"$s/tower-capacity.sh" set --flying nonsense >/dev/null 2>&1; check "a bad limit is refused" "$?" 2
"$s/tower-capacity.sh" set --flying off --runways auto >/dev/null
for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
  git worktree add -q -b "wide/$i" "../wide-$i"
  "$gate" add "wide-$i" >/dev/null || fail "gate refused worktree $i with no limit"
done
check "twelve fly at once without a limit" "$("$gate" list | sed -n 1p)" "active (12/no limit):"
for i in 1 2 3 4 5 6 7 8 9 10 11 12; do "$gate" rm "wide-$i" >/dev/null; git worktree remove "../wide-$i"; git branch -qD "wide/$i"; done

# Preflight
"$area" mission "Launch für Märkte" 
"$area" add api "Build the API" --class scout --owns "src/api/**" >/dev/null
"$area" add app "Build the app" --class liner --owns "src/app,docs/app.md" --after api >/dev/null
"$area" add docs "Write the docs" --class prop --owns docs >/dev/null
out=$("$area" check); code=$?
check "overlap without an order fails preflight" "$code" 1
has "preflight names the pair" "$out" "app <> docs own the same files"
"$area" add bad "TODO decide" >/dev/null
"$area" add loop-a "One" --after loop-b --owns x >/dev/null
"$area" add loop-b "Two" --after loop-a --owns y >/dev/null
"$area" add lost "Three" --after nowhere --owns z >/dev/null
out=$("$area" check)
has "placeholder titles fail preflight" "$out" "bad: the title is a placeholder"
has "dependency cycles fail preflight" "$out" "loop-a: part of a dependency cycle"
has "unknown dependencies fail preflight" "$out" "lost: waits for unknown area nowhere"
rm -f "$home"/areas/bad "$home"/areas/loop-a "$home"/areas/loop-b "$home"/areas/lost "$home"/areas/docs
"$area" add docs "Write the docs" --class prop --owns docs --after app >/dev/null
out=$("$area" check); check "ordered overlap passes preflight" "$?" 0
has "ordered overlap is listed" "$out" "ordered"
mkdir -p "$work/globtest/src/api"; touch "$work/globtest/src/api/new.ts"
"$area" add glob-a "A" --owns 'src/api/*' >/dev/null; "$area" add glob-b "B" --owns 'src/api/new.ts' >/dev/null
has "ownership is compared, not expanded" "$(cd "$work/globtest" && git -C "$work/shop" rev-parse --git-common-dir >/dev/null; TOWER_HOME="$home" "$area" check 2>&1 || true)" "glob-a <> glob-b"
rm -f "$home/areas/glob-a" "$home/areas/glob-b"
"$area" add many "Many" --after api --after app --owns one --owns two >/dev/null
check "repeated flags add up" "$(sed -n 's/^after=//p' "$home/areas/many")/$(sed -n 's/^owns=//p' "$home/areas/many")" "api,app/one,two"
rm -f "$home/areas/many"
"$gate" list >/dev/null; "$gate" add --force x-marker >/dev/null; has "the gate names the base checkout" "$("$gate" list)" "shop (base checkout, not counted)"; "$gate" rm x-marker >/dev/null
"$area" add later "Later" --owns one >/dev/null
"$area" edit later --owns two --class prop --title "Later still" >/dev/null; check "edit changes a planned area" "$(sed -n 's/^owns=//p' "$home/areas/later")/$(sed -n 's/^class=//p' "$home/areas/later")/$(sed -n 's/^title=//p' "$home/areas/later")" "two/prop/Later still"
"$area" remove later >/dev/null; [ -f "$home/areas/later" ] && fail "remove takes a planned area off the plan" || pass "remove takes a planned area off the plan"
has "preflight notices an unfilled brief" "$("$area" check)" "brief.md still has"
"$area" add x "X" --class nosuch >/dev/null 2>&1; check "an unknown class is refused" "$?" 2
"$area" add "Bad Name" "X" >/dev/null 2>&1; check "an unsafe id is refused" "$?" 2
"$area" add api "Again" >/dev/null 2>&1; check "a duplicate id is refused" "$?" 2

# Launch honours dependencies and creates the worktree.
"$area" launch app >/dev/null 2>&1; check "launch waits for dependencies" "$?" 1
"$area" launch api >/dev/null; check "launch succeeds" "$?" 0
[ -d ../shop-api ] && pass "launch creates the worktree" || fail "launch creates the worktree"
"$gate" list | grep -qx '  shop-api' && pass "launch opens the gate" || fail "launch opens the gate"
"$area" launch api >/dev/null; check "launching twice is harmless" "$?" 0

# Worker reports never fail and never print.
cd ../shop-api
out=$("$area" step 2 5 "Tests für Größe"); check "step prints nothing" "$out" ""
out=$(cd "$work/shop" && "$area" step 1 2 "the base checkout is no area"); check "step outside an area is silent" "$?" 0
"$area" step notanumber; check "a bad step never fails the worker" "$?" 0
"$area" deliver DONE "nothing yet" >/dev/null 2>&1; check "a candidate needs commits" "$?" 1
echo code > api.txt
"$area" deliver DONE >/dev/null 2>&1; check "a candidate needs a clean tree" "$?" 1
git add api.txt; git commit -qm "Add api"
"$area" deliver DONE "built" >/dev/null; check "deliver accepts commits" "$?" 0
json=$("$board" --json)
has "umlauts reach the board" "$json" 'Launch für Märkte'
has "state is delivered" "$json" '"state":"candidate"'
has "delivering completes the steps" "$json" '"done":5,"total":5'
has "ahead is counted" "$json" '"ahead":1'
cd "$work/shop"

# The tower owns the rest, and landing takes evidence.
"$area" mark api land >/dev/null 2>&1; check "only a cleared area lands" "$?" 1
"$area" mark api review >/dev/null
"$area" mark api clear >/dev/null; "$area" mark api return "Missing the error path" >/dev/null
has "a return counts a round" "$("$board" --json)" '"round":2'
(cd ../shop-api && echo fix >> api.txt && git add api.txt && git commit -qm "Fix error path" && "$area" deliver DONE "fixed" >/dev/null)
(cd ../shop-api && git commit -q --allow-empty -m "Later"); "$area" mark api clear >/dev/null 2>&1; check "clear refuses a branch that moved after delivery" "$?" 1
(cd ../shop-api && "$area" deliver DONE "again" >/dev/null 2>&1); check "a delivered area cannot deliver twice" "$?" 1
"$area" mark api clear --sha area/api >/dev/null; check "clear accepts a commit you name" "$?" 0
"$area" mark api land >/dev/null 2>&1; check "landing refuses work not on the base" "$?" 1
has "the refusal leaves it cleared" "$("$board" --plain)" "cleared"
git merge -q --ff-only area/api
"$area" mark api land >/dev/null; check "landing accepts work on the base" "$?" 0
"$gate" list | grep -q shop-api && fail "landing closes the gate" || pass "landing closes the gate"
"$area" launch app --native >/dev/null; check "native launch reserves a slot" "$?" 0
"$gate" list | grep -qx '  @app' && pass "the reservation counts" || fail "the reservation counts"
git worktree add -q -b my/app ../somewhere-app
(cd ../somewhere-app && "$area" bind app >/dev/null); check "bind from a native worktree" "$?" 0
has "bind records the worktree" "$("$board" --json)" '"worktree":"somewhere-app"'
"$gate" list | grep -q '@app' && fail "bind replaces the reservation" || pass "bind replaces the reservation"
(cd ../somewhere-app && "$area" deliver BLOCKED "Which provider?" >/dev/null)
has "blocked surfaces" "$("$board" --plain)" "[BLOCKED] Which provider?"

# Parking is the gate's truth, not a claim of the area.
"$area" add idle "Idle" --owns idle >/dev/null
"$area" launch idle >/dev/null
"$gate" rm shop-idle >/dev/null
has "off the gate means holding" "$("$board" --plain)" "holding"

# Moves that make no sense are refused, and bad input cannot reach a shell.
"$area" launch api >/dev/null 2>&1; check "a landed area does not launch again" "$?" 1
"$area" mark api return >/dev/null 2>&1; check "a landed area does not come back" "$?" 1
(cd ../shop-api && "$area" deliver DONE >/dev/null 2>&1); check "a landed area takes no late delivery" "$?" 2
"$area" add plain "Plain" --owns plain >/dev/null
"$area" mark plain clear >/dev/null 2>&1; check "nothing clears without a delivery" "$?" 1
"$area" launch plain --base >/dev/null 2>&1; check "a flag without a value is a usage error" "$?" 2
"$area" launch plain >/dev/null
(cd ../shop-plain && git checkout -q --detach && "$area" bind plain >/dev/null 2>&1); check "bind refuses a detached worktree" "$?" 1
(cd ../shop-plain && git checkout -q area/plain && "$area" step 1 2 "$(printf 'n\0371\037\0370\0370\0370\0370\037\0370\037now[$(touch "%s")]' "$work/pwned")")
"$board" --plain >/dev/null; "$board" --json >/dev/null
[ -e "$work/pwned" ] && fail "a worker's note cannot run a command" || pass "a worker's note cannot run a command"
(cd ../shop-plain && "$area" step 1 2 "$(printf 'esc\033[31m\nnew\tline')")
if command -v jq >/dev/null 2>&1; then "$board" --json | jq -e . >/dev/null; check "control characters keep the JSON valid" "$?" 0; fi
lacks "control characters never reach the terminal" "$("$board")" "$(printf '\033')"
"$area" mission "$(printf 'two\nlines')"
if command -v jq >/dev/null 2>&1; then "$board" --json | jq -e . >/dev/null; check "a mission with a newline keeps the JSON valid" "$?" 0; fi
"$area" mission "Launch für Märkte"
(cd ../shop-plain && "$area" step 999 2 "too far"; "$area" step 99999999 2 "far too far")
out=$("$board" --plain >/dev/null; echo $?); check "a step past the total does not hurt the board" "$out" 0
"$s/tower-capacity.sh" set --flying 3x >/dev/null 2>&1; check "a limit must be a number" "$?" 2
mkdir -p "$home/locks/nobody"; touch -t 202001010000 "$home/locks/nobody"
"$area" add nobody "Nobody" --owns nobody >/dev/null; check "an old ownerless area lock is freed" "$?" 0
"$area" edit plain --owns elsewhere >/dev/null 2>&1; check "a flown area cannot be edited" "$?" 1
"$area" remove plain >/dev/null 2>&1; check "a flown area cannot be removed" "$?" 1
"$area" mark plain drop >/dev/null; "$area" add dep "Dep" --after plain --owns dep >/dev/null
has "preflight notices a dropped dependency" "$("$area" check)" "waits for dropped area plain"; "$area" remove dep >/dev/null
"$area" add abs "Abs" --worktree "$work/shop-plain/" --branch area/plain --owns abs >/dev/null
check "an absolute worktree path becomes its folder" "$(sed -n 's/^worktree=//p' "$home/areas/abs")" shop-plain; "$area" mark abs drop >/dev/null
"$area" add reuse "Reuse" --worktree shop-plain --branch area/plain --owns reuse >/dev/null
(cd ../shop-plain && "$area" step 3 4 "for reuse"); has "a dropped area does not swallow reports" "$(sed -n 's/^note=//p' "$home/areas/reuse")" "for reuse"
"$area" mark reuse drop >/dev/null; rm -f "$home/areas/reuse" "$home/areas/nobody" "$home/areas/plain"

# Limits still hold through launch.
"$s/tower-capacity.sh" set --flying 1 >/dev/null
"$area" add full "Full" --owns full >/dev/null
"$area" launch full >/dev/null 2>&1; check "launch respects your limit" "$?" 1
[ -d ../shop-full ] && fail "a refused launch leaves no worktree" || pass "a refused launch leaves no worktree"
"$area" launch full --native >/dev/null 2>&1; check "native launch respects your limit" "$?" 1
"$s/tower-capacity.sh" set --flying off >/dev/null

# Board views
plain=$("$board" --plain)
term=$("$board")
has "terminal board has the mission" "$term" "Launch für Märkte"
has "terminal board groups by worktree" "$term" "Worktrees"
has "a blocked area looks up with wide eyes" "$term" "{OO} tower-liner"
lacks "piped terminal board has no colour codes" "$term" "$(printf '\033')"
lacks "plain board has no colour codes" "$plain" "$(printf '\033')"
has "landed stays out of the way" "$term" "Landed · 1"
has "the deck speaks the chosen language" "$(TOWER_LANG=de "$board")" "Gelandet"
has "--all lists landed" "$("$board" --all)" "Build the API"
git worktree add -q -b takeover/old ../old-work
has "unplanned worktrees are visible" "$("$board")" "old-work"
has "unplanned worktrees are in the data" "$("$board" --json)" '"worktree":"old-work"'
if command -v jq >/dev/null 2>&1; then
  "$area" add quote 'He said "go" \ now' --owns q >/dev/null
  "$board" --json | jq -e '.areas | length > 0' >/dev/null; check "JSON parses, including quotes" "$?" 0
fi
url=$("$board" --html)
has "html prints an address" "$url" "file://"
[ -f "$home/board-page/index.html" ] && [ -f "$home/board-page/data.js" ] && [ -f "$home/board-page/avatars.js" ] && [ -f "$home/board-page/avatars.css" ] && pass "html writes the page" || fail "html writes the page"
git status --porcelain | grep -q . && fail "the board leaves the repository clean" || pass "the board leaves the repository clean"

# Rulings and the end of a shift
"$area" rule "Use Stripe" "Already in use" "One provider swap"
has "rulings are kept" "$("$area" rulings)" "Ruling: Use Stripe. Why: Already in use. If wrong: One provider swap"
"$area" archive >/dev/null
check "archive clears the board" "$(ls "$home/areas" | grep -c .)" 0
[ -n "$(ls "$home/archive")" ] && pass "archive keeps the old plan" || fail "archive keeps the old plan"

# Concurrent reporters do not lose or corrupt a record.
"$area" add busy "Busy" --owns busy >/dev/null
"$area" launch busy >/dev/null
pids=
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16; do
  (cd ../shop-busy && exec "$area" step "$i" 16 "note $i") &
  pids="$pids $!"
done
wait $pids
check "concurrent reports leave one record" "$(grep -c '^step_done=' "$home/areas/busy")" 1
check "concurrent reports keep the title" "$(sed -n 's/^title=//p' "$home/areas/busy")" "Busy"

# The live deck keeps running until it is told to stop.
(COLUMNS=70 exec "$board" --watch </dev/null >"$work/deck.out" 2>"$work/deck.err") &
deck=$!
sleep 3
if kill -0 "$deck" 2>/dev/null; then pass "the live deck keeps running"; else fail "the live deck keeps running: $(tail -1 "$work/deck.err")"; fi
kill -TERM "$deck" 2>/dev/null; wait "$deck" 2>/dev/null
has "the live deck draws worktree boxes" "$(cat "$work/deck.out")" "Worktrees"

# The survey reads and changes nothing; the deck says what it would do.
before=$(git status --porcelain)
out=$("$s/tower-survey.sh"); check "survey succeeds" "$?" 0
has "survey names the base" "$out" "base:       main"
has "survey lists worktrees" "$out" "worktrees:"
check "survey leaves the repository alone" "$(git status --porcelain)" "$before"
out=$(cd "$work" && mkdir -p bare-folder && cd bare-folder && "$s/tower-survey.sh"); has "survey handles a folder with no repository" "$out" "repository: none"
has "survey still reads the machine there" "$out" "suggest: up to"
out=$(cd "$work" && mkdir -p mini && cd mini && git init -q && printf '{"name":"x","scripts":{"test":"vitest","build":"tsc"}}' > package.json && "$s/tower-survey.sh"); has "survey reads a minified package.json" "$out" "npm run test"
has "deck says what it would do" "$("$s/tower-deck.sh" --print)" "--watch"

# Installing never overwrites, and Codex gets valid worker classes.
fake=$work/home
CLAUDE_HOME=$fake/claude CODEX_HOME=$fake/codex "$s/tower-install.sh" all >/dev/null; check "install succeeds" "$?" 0
[ -L "$fake/claude/skills/watchtower" ] && [ -L "$fake/codex/skills/watchtower" ] && pass "install links the skill" || fail "install links the skill"
CLAUDE_HOME=$fake/claude CODEX_HOME=$fake/codex "$s/tower-install.sh" all >/dev/null; check "installing twice is harmless" "$?" 0
mkdir -p "$fake/other/skills/watchtower"
CLAUDE_HOME=$fake/other "$s/tower-install.sh" claude >/dev/null; check "install leaves a foreign folder alone" "$?" 1
[ -L "$fake/codex/skills/watchtower-setup" ] && pass "codex gets the setup skill" || fail "codex gets the setup skill"
check "codex gets every class" "$(ls "$fake/codex/agents" | grep -c 'tower-.*toml')" 6
if ! grep -q '<skill>' "$fake/codex/agents/tower-scout.toml"; then pass "codex agents name the real skill path"; else fail "codex agents name the real skill path"; fi
if python3 -c 'import tomllib' 2>/dev/null; then
  python3 -c 'import sys, tomllib, glob; [tomllib.load(open(f, "rb")) for f in glob.glob(sys.argv[1] + "/*.toml")]' "$fake/codex/agents"
  check "codex agents parse as TOML" "$?" 0
fi

[ "$fails" -eq 0 ]
