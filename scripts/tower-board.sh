#!/usr/bin/env bash
# The fleet at a glance. Every view reads the same state, so all of them agree.
#   tower-board.sh                  flight strips with colour, for a person at a terminal
#   tower-board.sh --watch [secs]   the same, live and full screen. Keys: q quit, l landed, c compact, j/k scroll
#   tower-board.sh --all            list landed areas too
#   tower-board.sh --compact        one line per area
#   tower-board.sh --plain          short and without colour, for the tower or a chat message
#   tower-board.sh --json           the data behind every view
#   tower-board.sh --html [--watch] write a live page next to the state and print its address
# Reading the board changes nothing in the repository.
set -u
here=$(cd "$(dirname "$0")" && pwd)
skill=$(cd "$here/.." && pwd)
. "$here/lib.sh"
home=$(tower_home) || exit 2

# Bash 3.2 counts bytes unless the locale says otherwise, and umlauts would break alignment.
case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
  *UTF-8*|*utf8*) ;;
  *) { if [ "$(uname)" = Darwin ]; then LC_CTYPE=en_US.UTF-8; else LC_CTYPE=C.UTF-8; fi; } 2>/dev/null ;;
esac

mode=term watch=0 interval=2 show_all=0 compact=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --watch) watch=1; case "${2:-}" in [1-9]*) interval=$2; shift ;; esac ;;
    --all) show_all=1 ;;
    --compact) compact=1 ;;
    --plain) mode=plain ;;
    --json) mode=json ;;
    --html) mode=html ;;
    *) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
  esac
  shift
done

SEP=$(printf '\037')
limit_runway_hang=${TOWER_TIMEOUT:-5400}

human_age() {
  local s=$1
  if [ "$s" -ge 3600 ]; then printf '%dh%02d' $((s / 3600)) $((s % 3600 / 60))
  elif [ "$s" -ge 60 ]; then printf '%dm' $((s / 60))
  else printf '%ds' "$s"; fi
}

human_tokens() {
  local n=$1
  if [ "$n" -ge 1000000 ]; then printf '%d.%dM' $((n / 1000000)) $((n % 1000000 / 100000))
  elif [ "$n" -ge 1000 ]; then printf '%dk' $((n / 1000))
  else printf '%d' "$n"; fi
}

# Values were cleaned when read, so only quoting is left to do here.
json_str() {
  local s=${1//\\/\\\\}
  s=${s//\"/\\\"}
  printf '"%s"' "$s"
}

num() {
  case "$1" in ''|*[!0-9]*) printf '0' ;; *) if [ "${#1}" -gt 12 ]; then printf '0'; else printf '%s' "$1"; fi ;; esac
}

# CI lives behind the network, so a board never waits for it: a small cached note, refreshed aside.
ci_refresh() {
  if [ -n "$(find "$home/ci.lock" -maxdepth 0 -mmin +2 2>/dev/null)" ]; then rmdir "$home/ci.lock" 2>/dev/null || true; fi
  mkdir "$home/ci.lock" 2>/dev/null || return 0
  local latest finished
  latest=$(gh run list --branch "$base" --limit 1 --json headSha,status,conclusion \
    -q '.[0] // empty | .headSha[0:7] + " " + .status + " " + .conclusion' 2>/dev/null) || latest=
  finished=$(gh run list --branch "$base" --status completed --limit 1 --json conclusion \
    -q '.[0].conclusion' 2>/dev/null) || finished=
  printf '%s\n%s\n%s\n' "$(date +%s)" "$latest" "$finished" > "$home/ci.cache.$$"
  mv "$home/ci.cache.$$" "$home/ci.cache"
  rmdir "$home/ci.lock"
}

ci_load() {
  ci_latest= ci_finished= ci_state=
  [ -z "${TOWER_NO_CI:-}" ] || return 0
  git remote get-url origin >/dev/null 2>&1 || return 0
  command -v gh >/dev/null 2>&1 || return 0
  local stamp=0
  [ -f "$home/ci.cache" ] && stamp=$(num "$(sed -n 1p "$home/ci.cache")")
  if [ $(( now - ${stamp:-0} )) -gt 60 ]; then
    if [ "$stamp" -eq 0 ] && [ "$mode" != json ]; then
      ci_refresh
    else
      ci_refresh >/dev/null 2>&1 </dev/null &
    fi
  fi
  [ -f "$home/ci.cache" ] || return 0
  ci_latest=$(clean_text "$(sed -n 2p "$home/ci.cache")")
  ci_finished=$(clean_text "$(sed -n 3p "$home/ci.cache")")
  case "$ci_latest" in
    '') ;;
    *completed\ failure|*completed\ cancelled|*completed\ timed_out|*completed\ startup_failure) ci_state=red ;;
    *completed*) ci_state=ok ;;
    *) ci_state=running ;;
  esac
}

# One record per area, fields separated by \037 so empty ones survive `read`.
collect() {
  now=$(date +%s)
  base=$(base_branch)
  base_sha=$(git rev-parse --short "$base" 2>/dev/null)
  base_folder=$(base_checkout_folder)
  flying_max=$(flying_limit "$home")
  runway_max=$(runway_limit "$home")
  mission=$(clean_text "$(cat "$home/mission" 2>/dev/null)")
  has_gate=0
  active=
  if [ -f "$home/active.list" ]; then has_gate=1; active=$(active_entries "$home"); fi
  all_worktrees=$(git worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p')
  ci_load

  lanes=
  runway_busy=0
  local lane
  for lane in "$home"/runways/*; do
    [ -d "$lane" ] || continue
    runway_busy=$((runway_busy + 1))
    lanes="$lanes$(clean_text "$(cat "$lane/worktree" 2>/dev/null)")$SEP$(clean_text "$(cat "$lane/label" 2>/dev/null)")$SEP$(num "$(cat "$lane/started" 2>/dev/null)")
"
  done
  runway_waiting=$(ls "$home/queue" 2>/dev/null | grep -c . || true)

  rows=
  local file
  for file in "$home"/areas/*; do
    [ -f "$file" ] || continue
    rows="$rows$(area_record "$file")
"
  done
  rows=$(printf '%s' "$rows" | sort -n -t"$SEP" -k1,1)
}

area_record() {
  local file=$1 id seq title class state folder branch after note round status steps total started base_name
  id=$(basename "$file")
  # Whoever wrote the file, nothing in it can shift a field or reach a shell as code.
  local cleaned key value landed_at=0
  cleaned=$(LC_ALL=C tr -d '\000-\011\013-\037\177' < "$file")
  while IFS='=' read -r key value; do
    case "$key" in
      seq) seq=$value ;; title) title=$value ;; class) class=$value ;; state) state=$value ;;
      worktree) folder=$value ;; branch) branch=$value ;; after) after=$value ;; note) note=$value ;;
      round) round=$value ;; status) status=$value ;; step_done) steps=$value ;; step_total) total=$value ;;
      started) started=$value ;; landed_at) landed_at=$value ;; base) base_name=$value ;;
    esac
  done <<CLEANED
$cleaned
CLEANED
  : "${title:=$id}" "${class:=liner}" "${state:=planned}" "${folder:=}" "${branch:=}" \
    "${after:=}" "${note:=}" "${status:=}" "${base_name:=}"
  seq=$(num "${seq:-0}"); round=$(num "${round:-1}"); steps=$(num "${steps:-0}"); total=$(num "${total:-0}")
  started=$(num "${started:-0}"); landed_at=$(num "$landed_at")
  [ "$total" -eq 0 ] || [ "$steps" -le "$total" ] || steps=$total
  [ "$total" -gt 0 ] || steps=0
  local against=${base_name:-$base}

  if [ "$state" = flying ] && [ "$has_gate" -eq 1 ]; then
    if [ -n "$folder" ]; then
      printf '%s\n' "$active" | grep -qxF "$folder" || state=parked
    else
      printf '%s\n' "$active" | grep -qxF "@$id" || state=parked
    fi
  fi

  local ahead=0 behind=0 dirty=0 missing=0 check= check_age=0 path=
  if [ -n "$folder" ] && [ "$state" != landed ] && [ "$state" != dropped ] && [ "$state" != planned ]; then
    path=$(printf '%s\n' "$all_worktrees" | while IFS= read -r p; do
      if [ "${p##*/}" = "$folder" ]; then printf '%s' "$p"; break; fi
    done)
    if [ -n "$path" ] && [ -d "$path" ]; then
      local counts
      counts=$(git -C "$path" rev-list --left-right --count "HEAD...$against" 2>/dev/null) && {
        ahead=${counts%%	*}
        behind=${counts##*	}
      }
      dirty=$(git -C "$path" status --short 2>/dev/null | grep -c . || true)
    else
      missing=1
    fi
    local lane_folder lane_label lane_started
    while IFS="$SEP" read -r lane_folder lane_label lane_started; do
      if [ "$lane_folder" = "$folder" ]; then
        check=$lane_label
        check_age=$(( now - lane_started ))
        break
      fi
    done <<LANES
$lanes
LANES
  fi

  local tokens=0 ctx=0 ctx_max=0 model= effort= cost=0
  if [ -f "$home/usage/$id" ]; then
    tokens=$(num "$(area_get "$home/usage/$id" tokens)")
    ctx=$(num "$(area_get "$home/usage/$id" ctx)")
    ctx_max=$(num "$(area_get "$home/usage/$id" ctx_max)")
    model=$(clean_text "$(area_get "$home/usage/$id" model)")
    effort=$(clean_text "$(area_get "$home/usage/$id" effort)")
    cost=$(area_get "$home/usage/$id" cost)
    case "$cost" in ''|*[!0-9.]*) cost=0 ;; esac
  fi

  local age=0
  if [ "$started" -gt 0 ]; then
    age=$(( now - started ))
    [ "$landed_at" -eq 0 ] || age=$(( landed_at - started ))
  fi
  printf '%s' "$seq$SEP$id$SEP$title$SEP$class$SEP$state$SEP$folder$SEP$branch$SEP$after$SEP$steps$SEP$total$SEP$note$SEP$round$SEP$status$SEP$ahead$SEP$behind$SEP$dirty$SEP$missing$SEP$check$SEP$check_age$SEP${tokens:-0}$SEP${ctx:-0}$SEP${ctx_max:-0}$SEP$model$SEP$effort$SEP$age$SEP$cost"
}

# Worktrees nobody planned: a takeover has to see them too.
loose_worktrees() {
  local p folder branch counts ahead behind dirty state known
  known=" $base_folder "
  while IFS="$SEP" read -r _ _ _ _ _ folder _; do known="$known$folder "; done <<ROWS
$rows
ROWS
  printf '%s\n' "$all_worktrees" | while IFS= read -r p; do
    [ -n "$p" ] || continue
    folder=${p##*/}
    case "$known" in *" $folder "*) continue ;; esac
    if [ ! -d "$p" ]; then
      printf '%s\n' "$folder$SEP$SEP""0$SEP""0$SEP""0$SEP""missing"
      continue
    fi
    branch=$(git -C "$p" rev-parse --abbrev-ref HEAD 2>/dev/null)
    counts=$(git -C "$p" rev-list --left-right --count "HEAD...$base" 2>/dev/null)
    ahead=${counts%%	*}
    behind=${counts##*	}
    dirty=$(git -C "$p" status --short 2>/dev/null | grep -c . || true)
    state=open
    if [ "$has_gate" -eq 1 ]; then
      state=flying
      printf '%s\n' "$active" | grep -qxF "$folder" || state=parked
    fi
    printf '%s\n' "$folder$SEP$branch$SEP${ahead:-0}$SEP${behind:-0}$SEP$dirty$SEP$state"
  done
}

group_of() {
  case "$1" in
    blocked) echo attention ;;
    candidate|review|cleared) echo approach ;;
    flying) echo airborne ;;
    parked) echo holding ;;
    planned) echo planned ;;
    landed) echo landed ;;
    *) echo other ;;
  esac
}

tally() {
  n_total=0 n_landed=0 n_flying=0 n_approach=0 n_holding=0 n_planned=0 n_attention=0 sum_tokens=0 max_age=0 sum_cost=0
  local state tokens group age cost costs=
  while IFS="$SEP" read -r _ _ _ _ state _ _ _ _ _ _ _ _ _ _ _ _ _ _ tokens _ _ _ _ age cost; do
    [ -n "$state" ] || continue
    [ "$state" = dropped ] && continue
    n_total=$((n_total + 1))
    sum_tokens=$((sum_tokens + ${tokens:-0}))
    [ "${age:-0}" -le "$max_age" ] || max_age=$age
    costs="$costs ${cost:-0}"
    group=$(group_of "$state")
    case "$group" in
      landed) n_landed=$((n_landed + 1)) ;;
      airborne) n_flying=$((n_flying + 1)) ;;
      approach) n_approach=$((n_approach + 1)) ;;
      holding) n_holding=$((n_holding + 1)) ;;
      planned) n_planned=$((n_planned + 1)) ;;
      attention) n_attention=$((n_attention + 1)) ;;
    esac
  done <<ROWS
$rows
ROWS
  sum_cost=$(printf '%s\n' $costs | LC_ALL=C awk '{ s += $1 } END { printf "%.2f", s + 0 }')
}

emit_json() {
  local first=1 seq id title class state folder branch after steps total note round status ahead behind dirty missing check check_age tokens ctx ctx_max model effort age cost
  printf '{"mission":%s,"base":%s,"sha":%s,"ci":{"latest":%s,"finished":%s,"state":%s},"now":%s,' \
    "$(json_str "$mission")" "$(json_str "$base")" "$(json_str "$base_sha")" "$(json_str "$ci_latest")" "$(json_str "$ci_finished")" "$(json_str "$ci_state")" "$now"
  printf '"limit":%s,"runways":{"limit":%s,"busy":%s,"waiting":%s,"timeout":%s,"items":[' \
    "${flying_max:-null}" "$runway_max" "$runway_busy" "${runway_waiting:-0}" "$limit_runway_hang"
  local lfolder llabel lstarted
  while IFS="$SEP" read -r lfolder llabel lstarted; do
    [ -n "${llabel}${lfolder}" ] || continue
    [ "$first" -eq 1 ] || printf ','
    first=0
    printf '{"worktree":%s,"label":%s,"age":%s}' "$(json_str "$lfolder")" "$(json_str "$llabel")" "$(( now - $(num "$lstarted") ))"
  done <<LANES
$lanes
LANES
  printf ']},"areas":['
  first=1
  while IFS="$SEP" read -r seq id title class state folder branch after steps total note round status ahead behind dirty missing check check_age tokens ctx ctx_max model effort age cost; do
    [ -n "${id:-}" ] || continue
    [ "$first" -eq 1 ] || printf ','
    first=0
    printf '{"seq":%s,"id":%s,"title":%s,"class":%s,"state":%s,"worktree":%s,"branch":%s,"after":%s,"done":%s,"total":%s,"note":%s,"round":%s,"status":%s,"ahead":%s,"behind":%s,"dirty":%s,"missing":%s,"check":%s,"checkAge":%s,"tokens":%s,"ctx":%s,"ctxMax":%s,"model":%s,"effort":%s,"age":%s,"cost":%s}' \
      "$seq" "$(json_str "$id")" "$(json_str "$title")" "$(json_str "$class")" "$(json_str "$state")" "$(json_str "$folder")" "$(json_str "$branch")" "$(json_str "$after")" \
      "$steps" "$total" "$(json_str "$note")" "$round" "$(json_str "$status")" "${ahead:-0}" "${behind:-0}" "${dirty:-0}" "$missing" "$(json_str "$check")" "$check_age" \
      "$tokens" "$ctx" "$ctx_max" "$(json_str "$model")" "$(json_str "$effort")" "$age" "$cost"
  done <<ROWS
$rows
ROWS
  printf '],"loose":['
  first=1
  local lbranch lahead lbehind ldirty lstate
  while IFS="$SEP" read -r lfolder lbranch lahead lbehind ldirty lstate; do
    [ -n "${lfolder:-}" ] || continue
    [ "$first" -eq 1 ] || printf ','
    first=0
    printf '{"worktree":%s,"branch":%s,"ahead":%s,"behind":%s,"dirty":%s,"state":%s}' \
      "$(json_str "$lfolder")" "$(json_str "$lbranch")" "$lahead" "$lbehind" "$ldirty" "$(json_str "$lstate")"
  done <<LOOSE
$(loose_worktrees)
LOOSE
  printf ']}\n'
}

# --- terminal ---------------------------------------------------------------

use_colour() {
  if [ -n "${NO_COLOR:-}" ] || ! [ -t 1 ]; then return 1; fi
  return 0
}

palette() {
  if [ "$watch" -eq 1 ] || use_colour; then
    R=$'\033[0m' B=$'\033[1m' D=$'\033[38;5;245m' L=$'\033[38;5;240m'
    C_flying=$'\033[38;5;75m' C_approach=$'\033[38;5;215m' C_cleared=$'\033[38;5;121m'
    C_landed=$'\033[38;5;78m' C_attention=$'\033[38;5;203m' C_holding=$'\033[38;5;103m' C_planned=$'\033[38;5;243m'
  else
    R= B= D= L= C_flying= C_approach= C_cleared= C_landed= C_attention= C_holding= C_planned=
  fi
}

colour_of() {
  case "$1" in
    flying) printf '%s' "$C_flying" ;;
    candidate|review) printf '%s' "$C_approach" ;;
    cleared) printf '%s' "$C_cleared" ;;
    landed) printf '%s' "$C_landed" ;;
    blocked) printf '%s' "$C_attention" ;;
    parked) printf '%s' "$C_holding" ;;
    *) printf '%s' "$C_planned" ;;
  esac
}

repeat() {
  local out= i=0
  while [ "$i" -lt "$2" ]; do out="$out$1"; i=$((i + 1)); done
  printf '%s' "$out"
}

pad() { printf '%s%s' "$1" "$(repeat ' ' $(( $2 - ${#1} > 0 ? $2 - ${#1} : 0 )))"; }

clip() {
  if [ "${#1}" -le "$2" ]; then printf '%s' "$1"; else printf '%s…' "${1:0:$(( $2 - 1 ))}"; fi
}

# TOWER_LANG wins, also from Claude Code's settings for a deck started in a plain terminal.
board_language=${TOWER_LANG:-$(sed -n 's/.*"TOWER_LANG"[^"]*"\([A-Za-z_-]*\)".*/\1/p' "${CLAUDE_HOME:-$HOME/.claude}/settings.json" 2>/dev/null | head -1)}
board_language=${board_language:-${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}}

is_german() {
  case "$board_language" in de*|DE*) return 0 ;; esac
  return 1
}

# People read this view, so it speaks their language. --plain stays English for the tower.
label_of() {
  if is_german; then
    case "$1" in
      flying) echo "Läuft" ;; candidate) echo "Geliefert" ;; review) echo "Im Review" ;; cleared) echo "Landebereit" ;;
      landed) echo "Gelandet" ;; blocked) echo "Braucht dich" ;; parked) echo "Pausiert" ;; planned) echo "Geplant" ;;
      total) echo "gesamt" ;; worktrees) echo "Worktrees" ;; running) echo "laufen" ;; cost) echo "Kosten" ;; tokens) echo "Tokens" ;; time) echo "Zeit" ;;
      limit) echo "Limit" ;; none) echo "keins" ;; checks) echo "Checks" ;; after) echo "nach" ;; other) echo "Weitere Worktrees" ;;
      nousage) echo "noch keine Nutzung gemeldet" ;; empty) echo "Noch kein Flugplan. tower-area.sh add legt ihn an." ;;
      keys) echo "q beenden  l Gelandete  c kompakt  j/k scrollen" ;; check) echo "Check" ;; concerns) echo "mit Bedenken" ;; round) echo "Runde" ;; gone) echo "Worktree-Ordner fehlt" ;;
      *) echo "$1" ;;
    esac
  else
    case "$1" in
      flying) echo "Running" ;; candidate) echo "Delivered" ;; review) echo "In review" ;; cleared) echo "Ready to land" ;;
      landed) echo "Landed" ;; blocked) echo "Needs you" ;; parked) echo "Paused" ;; planned) echo "Planned" ;;
      total) echo "total" ;; worktrees) echo "Worktrees" ;; running) echo "running" ;; cost) echo "Cost" ;; tokens) echo "Tokens" ;; time) echo "Time" ;;
      limit) echo "limit" ;; none) echo "none" ;; checks) echo "checks" ;; after) echo "after" ;; other) echo "Other worktrees" ;;
      nousage) echo "no usage reported yet" ;; empty) echo "No flight plan yet. tower-area.sh add starts it." ;;
      keys) echo "q quit  l landed  c compact  j/k scroll" ;; check) echo "check" ;; concerns) echo "with concerns" ;; round) echo "round" ;; gone) echo "worktree folder is gone" ;;
      *) echo "$1" ;;
    esac
  fi
}

human_clock() {
  local s=$1
  if [ "$s" -ge 3600 ]; then printf '%d:%02d:%02d' $((s / 3600)) $((s % 3600 / 60)) $((s % 60))
  else printf '%d:%02d' $((s / 60)) $((s % 60)); fi
}

# One slot per area: you read the whole fleet from a single line.
fleet_bar() {
  local width=$1 slots gap state steps total cell colour out= count=0 full
  [ "$n_total" -gt 0 ] || return 0
  gap=1
  slots=$(( (width - (n_total - 1)) / n_total ))
  if [ "$slots" -lt 1 ]; then slots=1; gap=0; fi
  while IFS="$SEP" read -r _ _ _ _ state _ _ _ steps total _; do
    [ -n "$state" ] || continue
    [ "$state" = dropped ] && continue
    colour=$(colour_of "$state")
    case "$state" in
      landed|cleared|candidate|review|blocked) full=$slots ;;
      flying|parked) if [ "${total:-0}" -gt 0 ]; then full=$(( slots * steps / total )); else full=0; fi ;;
      *) full=0 ;;
    esac
    cell=█
    [ "$count" -eq 0 ] || [ "$gap" -eq 0 ] || out="$out "
    count=$((count + 1))
    out="$out$colour$(repeat "$cell" "$full")$R$L$(repeat '░' $(( slots - full )))$R"
  done <<ROWS
$rows
ROWS
  printf '%s\n' "$out"
}

route() {
  local width=$1 steps=$2 total=$3 colour=$4 full
  if [ "$total" -le 0 ]; then
    printf '%s%s%s' "$L" "$(repeat '╌' "$width")" "$R"
    return
  fi
  full=$(( (width - 1) * steps / total ))
  printf '%s%s●%s%s%s%s' "$colour" "$(repeat '━' "$full")" "$R" "$L" "$(repeat '╌' $(( width - 1 - full )))" "$R"
}

# The fleet's faces in text: shell by class, eyes by state, a blink when live.
text_face() {
  local shell eyes
  case "$1" in
    ace) shell='<>' ;; scout) shell='()' ;; freighter) shell='[]' ;; liner) shell='{}' ;; prop) shell='||' ;; *) shell='//' ;;
  esac
  case "$2" in
    flying)
      eyes='••'
      if [ "$watch" -eq 1 ]; then
        case $(( now % 8 )) in 0) eyes='--' ;; 3) eyes='• ' ;; 5) eyes=' •' ;; esac
      fi
      ;;
    planned) eyes='··' ;;
    candidate|review) eyes='°°' ;;
    cleared|landed) eyes='^^' ;;
    parked) eyes='--' ;;
    blocked) eyes='OO' ;;
    *) eyes='··' ;;
  esac
  printf '%s%s%s' "${shell%?}" "$eyes" "${shell#?}"
}

state_label() {
  case "$1" in
    flying) echo airborne ;;
    candidate) echo delivered ;;
    review) echo "in review" ;;
    cleared) echo cleared ;;
    landed) echo landed ;;
    blocked) echo blocked ;;
    parked) echo holding ;;
    planned) echo planned ;;
    *) echo "$1" ;;
  esac
}

# A worktree is one box: its name and state on the rim, progress inside, its agent at the bottom.
worktree_box() {
  local id=$1 title=$2 class=$3 state=$4 folder=$5 branch=$6 steps=$7 total=$8 note=$9
  shift 9
  local round=$1 status=$2 ahead=$3 behind=$4 dirty=$5 missing=$6 check=$7 check_age=$8 tokens=$9
  shift 9
  local ctx=$1 ctx_max=$2 age=$3 model=$4 effort=$5 cost=$6
  local c inner name label rule meta flags= usage progress routeW
  c=$(colour_of "$state")
  inner=$(( box_width - 4 ))
  name=$(clip "${folder:-$id}" $(( inner - 20 )))
  label=$(label_of "$state")
  rule=$(repeat '─' $(( box_width - ${#name} - ${#label} - 10 )))
  printf '%s╭─%s %s%s%s %s%s%s ● %s%s%s ─╮%s\n' "$L" "$R" "$B" "$name" "$R" "$L" "$rule" "$c" "$R" "$label" "$L" "$R"
  box_line "$(clip "$title" "$inner")"
  if [ "$compact" -eq 1 ]; then
    box_close
    return
  fi
  if [ "$state" = blocked ]; then
    box_line "$(clip "${note:-$label}" "$inner")" "$c"
  else
    progress=
    [ "$total" -eq 0 ] || progress=" $steps/$total"
    routeW=$(( inner - ${#progress} ))
    printf '%s│%s %s%s %s│%s\n' "$L" "$R" "$(route "$routeW" "$steps" "$total" "$c")" "$progress" "$L" "$R"
    [ -z "$note" ] || box_line "$(clip "$note" "$inner")" "$D"
  fi
  [ "$status" != CONCERNS ] || flags="$flags · $(label_of concerns)"
  [ "${round:-1}" -le 1 ] || flags="$flags · $(label_of round) $round"
  [ "$missing" -eq 0 ] || flags="$flags · $(label_of gone)"
  [ -z "$check" ] || flags="$flags · $(label_of check): $check $(human_age "$check_age")"
  meta="$branch ↑$ahead ↓$behind"
  [ "$dirty" -eq 0 ] || meta="$meta ✎$dirty"
  box_line "$(clip "$meta$flags" "$inner")" "$D"
  if [ "$tokens" -gt 0 ] || [ -n "$model" ]; then
    usage=
    [ -z "$model" ] || usage="$(printf '%s' "$model" | sed -E 's/^claude-//; s/-([0-9]+)-([0-9]+)$/ \1.\2/; s/-([0-9]+)$/ \1/')"
    [ -z "$effort" ] || usage="$usage · $effort"
    if [ "$ctx_max" -gt 0 ]; then usage="$usage · ctx $(( ctx * 100 / ctx_max ))%"; fi
    [ "$tokens" -eq 0 ] || usage="$usage · $(human_tokens "$tokens")"
    case "$cost" in 0|0.0000|'') ;; *) usage="$usage · ≈\$$(LC_ALL=C printf '%.2f' "$cost")" ;; esac
    [ "$age" -eq 0 ] || usage="$usage · $(human_age "$age")"
  else
    usage=$(label_of nousage)
  fi
  local face line
  face=$(text_face "$class" "$state")
  line="tower-$class  $usage"
  printf '%s│%s %s%s%s %s %s│%s\n' "$L" "$R" "$c" "$face" "$R" "$(pad "$(clip "$line" $(( inner - 5 )))" $(( inner - 5 )))" "$L" "$R"
  box_close
}

box_line() {
  printf '%s│%s %s%s%s %s│%s\n' "$L" "$R" "${2:-}" "$(pad "$1" $(( box_width - 4 )))" "$R" "$L" "$R"
}

box_close() {
  printf '%s╰%s╯%s\n' "$L" "$(repeat '─' $(( box_width - 2 )))" "$R"
}

# Worktrees in the order that needs the person first.
draw_worktrees() {
  local wanted seq id title class state folder branch after steps total note round status ahead behind dirty missing check check_age tokens ctx ctx_max model effort age cost
  for wanted in blocked candidate review cleared flying parked; do
    while IFS="$SEP" read -r seq id title class state folder branch after steps total note round status ahead behind dirty missing check check_age tokens ctx ctx_max model effort age cost; do
      [ "${state:-}" = "$wanted" ] || continue
      worktree_box "$id" "$title" "$class" "$state" "$folder" "$branch" "$steps" "$total" "$note" "$round" "$status" "$ahead" "$behind" "$dirty" "$missing" "$check" "$check_age" "$tokens" "$ctx" "$ctx_max" "$age" "$model" "$effort" "$cost"
    done <<ROWS
$rows
ROWS
  done
}

draw_quiet() {
  local wanted=$1 _s id title class state _f _b after _r
  while IFS="$SEP" read -r _s id title class state _f _b after _r; do
    [ "${state:-}" = "$wanted" ] || continue
    printf ' %s%s%s %s' "$(colour_of "$state")" "$(text_face "$class" "$state")" "$R" "$(clip "$title" $(( box_width - 8 )))"
    if [ -n "$after" ] && [ "$wanted" = planned ]; then printf ' %s%s %s%s' "$D" "$(label_of after)" "$after" "$R"; fi
    printf '\n'
  done <<ROWS
$rows
ROWS
}

draw_term() {
  cols=${COLUMNS:-$(tput cols 2>/dev/null || echo 100)}
  [ "$cols" -ge 44 ] || cols=44
  box_width=$cols
  [ "$box_width" -le 100 ] || box_width=100
  palette
  tally
  local ci=
  case "$ci_state" in
    ok) ci="  ${C_landed}CI ok$R" ;;
    red) ci="  ${C_attention}CI red$R" ;;
    running) ci="  ${C_approach}CI …$R" ;;
  esac
  printf '%s%s%s\n' "$B" "$(clip "${mission:-Watchtower}" "$box_width")" "$R"
  printf '%s%s @ %s%s%s\n' "$D" "$base" "$base_sha" "$R" "$ci"
  printf '\n%s%s%s %s  %s%s%s %s  %s%s%s %s\n' "$D" "$(label_of cost)" "$R" "≈\$$sum_cost" "$D" "$(label_of tokens)" "$R" "$(human_tokens "$sum_tokens")" "$D" "$(label_of time)" "$R" "$(human_clock "$max_age")"
  fleet_bar "$box_width"
  printf '%s%s/%s %s · %s %s · %s %s · %s %s/%s%s' "$D" "$n_landed" "$n_total" "$(label_of landed | tr '[:upper:]' '[:lower:]')" "$n_flying" "$(label_of running)" "$(label_of limit)" "${flying_max:-$(label_of none)}" "$(label_of checks)" "$runway_busy" "$runway_max" "$R"
  [ "${runway_waiting:-0}" -eq 0 ] || printf ' %s+%s%s' "$C_approach" "$runway_waiting" "$R"
  printf '\n'
  local open=$(( n_attention + n_approach + n_flying + n_holding ))
  [ "$n_total" -gt 0 ] || printf '\n%s%s%s\n' "$D" "$(label_of empty)" "$R"
  if [ "$open" -gt 0 ]; then
    printf '\n%s%s%s %s· %s %s%s\n' "$B" "$(label_of worktrees)" "$R" "$D" "$open" "$(label_of total)" "$R"
    draw_worktrees
  fi
  if [ "$n_planned" -gt 0 ]; then
    printf '\n%s%s%s %s· %s%s\n' "$B" "$(label_of planned)" "$R" "$D" "$n_planned" "$R"
    draw_quiet planned
  fi
  if [ "$n_landed" -gt 0 ]; then
    if [ "$show_all" -eq 1 ]; then
      printf '\n%s%s%s %s· %s%s\n' "$B" "$(label_of landed)" "$R" "$D" "$n_landed" "$R"
      draw_quiet landed
    else
      printf '\n%s%s · %s%s\n' "$D" "$(label_of landed)" "$n_landed" "$R"
    fi
  fi
  local loose
  loose=$(loose_worktrees)
  if [ -n "$loose" ]; then
    printf '\n%s%s%s\n' "$B" "$(label_of other)" "$R"
    printf '%s\n' "$loose" | while IFS="$SEP" read -r folder branch ahead behind dirty state; do
      if [ "$state" = missing ]; then
        printf ' %s  %s%s%s\n' "$folder" "$C_attention" "$(label_of gone)" "$R"
      else
        printf ' %s %s%s ↑%s ↓%s ✎%s%s\n' "$folder" "$D" "$branch" "$ahead" "$behind" "$dirty" "$R"
      fi
    done
  fi
}

# Full screen without flicker: repaint in place, keys on the side.
watch_term() {
  local rows_on_screen frame key offset=0 count
  palette
  trap 'printf "\033[?25h\033[?1049l"; exit 0' INT TERM EXIT
  printf '\033[?1049h\033[?25l'
  while :; do
    collect
    frame=$(draw_term)
    rows_on_screen=$(tput lines 2>/dev/null || echo 40)
    count=$(printf '%s\n' "$frame" | wc -l | tr -d ' ')
    [ "$offset" -le $(( count - rows_on_screen + 1 > 0 ? count - rows_on_screen + 1 : 0 )) ] || offset=0
    printf '\033[H'
    printf '%s\n' "$frame" | tail -n +$(( offset + 1 )) | head -n $(( rows_on_screen - 1 )) | while IFS= read -r line; do printf '%s\033[K\n' "$line"; done
    printf '\033[J%s%s%s' "$D" "$(label_of keys)" "$R"
    key=
    if [ -t 0 ]; then read -rsn1 -t "$interval" key 2>/dev/null || true; else sleep "$interval"; fi
    case "$key" in
      q|Q) exit 0 ;;
      l|L) show_all=$(( 1 - show_all )) ;;
      c|C) compact=$(( 1 - compact )) ;;
      j) offset=$(( offset + 3 )) ;;
      k) offset=$(( offset > 3 ? offset - 3 : 0 )) ;;
    esac
  done
}

# --- plain, for the tower's own context ------------------------------------

draw_plain() {
  tally
  [ -z "$mission" ] || echo "mission: $mission"
  echo "base: $base @ $base_sha"
  [ -z "$ci_latest" ] || echo "ci:   $ci_latest"
  case "$ci_finished" in
    success|"") ;;
    *) echo "ci:   WARNING, last finished run is not green: $ci_finished" ;;
  esac
  printf 'fleet: %s/%s landed, %s airborne, %s approach, %s holding, %s blocked, %s planned. limit %s\n' \
    "$n_landed" "$n_total" "$n_flying" "$n_approach" "$n_holding" "$n_attention" "$n_planned" "${flying_max:-none}"
  echo
  echo "runways ($runway_busy/$runway_max, waiting $runway_waiting):"
  if [ "$runway_busy" -eq 0 ]; then
    echo "  all free"
  else
    printf '%s' "$lanes" | while IFS="$SEP" read -r folder label started; do
      local_age=$(( now - ${started:-$now} ))
      flag=
      [ "$local_age" -le $(( limit_runway_hang * 3 / 4 )) ] || flag="  <- close to the time limit, check for a hang"
      printf '  %-22s %-30s %4dm%s\n' "$label" "$folder" $(( local_age / 60 )) "$flag"
    done
  fi
  if [ "$n_total" -gt 0 ]; then
    echo
    echo "areas (state id class steps ahead/behind dirty branch: note):"
    printf '%s\n' "$rows" | while IFS="$SEP" read -r _ id title class state folder branch after steps total note round status ahead behind dirty missing check check_age tokens ctx ctx_max _ _ age _; do
      [ -n "${id:-}" ] || continue
      extra=
      [ -z "$status" ] || extra=" [$status]"
      [ "${round:-1}" -le 1 ] || extra="$extra [round $round]"
      [ "$missing" -eq 0 ] || extra="$extra [worktree folder is gone]"
      [ -z "$check" ] || extra="$extra [check: $check $(human_age "$check_age")]"
      if [ "$ctx_max" -gt 0 ]; then extra="$extra [ctx $(( ctx * 100 / ctx_max ))%]"; fi
      [ -z "$after" ] || [ "$state" != planned ] || extra="$extra [after $after]"
      printf '  %-9s %-20s %-9s %5s %5s %3s  %s:%s %s\n' "$(state_label "$state" | cut -c1-9)" "$id" "$class" "$steps/$total" "$ahead/$behind" "$dirty" "$branch" "$extra" "${note:-$title}"
    done
  fi
  local loose
  loose=$(loose_worktrees)
  if [ -n "$loose" ]; then
    echo
    echo "other worktrees (ahead/behind $base, uncommitted files, state):"
    printf '%s\n' "$loose" | while IFS="$SEP" read -r folder branch ahead behind dirty state; do
      if [ "$state" = missing ]; then
        printf '  %-34s MISSING, folder is gone (git worktree prune removes the entry)\n' "$folder"
      else
        printf '  %-34s %-34s %-7s %3s  %s\n' "$folder" "$branch" "$ahead/$behind" "$dirty" "$state"
      fi
    done
  fi
  if [ -f "$home/runway.log" ]; then
    echo
    echo "recent runs:"
    tail -"${TOWER_LOG_LINES:-6}" "$home/runway.log" | sed 's/^/  /'
  fi
}

# --- browser page, for clients with no drawing surface of their own ---------

write_page() {
  local target="$home/board-page"
  mkdir -p "$target"
  cp "$skill/assets/board.html" "$target/index.html.$$" && mv "$target/index.html.$$" "$target/index.html"
  cp "$skill/assets/avatars.css" "$target/avatars.css.$$" && mv "$target/avatars.css.$$" "$target/avatars.css"
  { printf 'window.__avatars='; cat "$skill/assets/avatars.json"; printf ';\n'; } > "$target/avatars.js.$$" && mv "$target/avatars.js.$$" "$target/avatars.js"
}

write_data() {
  local target="$home/board-page"
  { printf 'window.__fleet='; emit_json; printf ';\n'; } > "$target/data.js.$$" && mv "$target/data.js.$$" "$target/data.js"
}

case "$mode" in
  json) collect; emit_json ;;
  plain) collect; draw_plain ;;
  html)
    write_page
    collect
    write_data
    echo "file://$home/board-page/index.html"
    if [ "$watch" -eq 1 ]; then
      while :; do sleep "$interval"; collect; write_data; done
    fi
    ;;
  term)
    if [ "$watch" -eq 1 ]; then
      watch_term
    else
      collect
      draw_term
    fi
    ;;
esac
