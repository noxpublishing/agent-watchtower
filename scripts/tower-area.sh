#!/usr/bin/env bash
# The flight plan: one record per area, written only through here, read by every board.
#
# Tower:
#   tower-area.sh mission "<title>"
#   tower-area.sh add <id> "<title>" [--class ace|scout|freighter|liner|prop] [--after a,b]
#                 [--owns "src/api,docs/api.md"] [--worktree <folder>] [--branch <name>]
#   tower-area.sh edit <id> [--title <text>] [--class <class>] [--after a,b] [--owns x,y]
#   tower-area.sh remove <id>                only while planned; drop it once it has flown
#   tower-area.sh check                      preflight: dependencies, ownership, placeholders
#   tower-area.sh launch <id>... [--native] [--base <branch>] [--force]
#                 creates worktree and branch, opens the gate. --native: the client's own
#                 tool makes the worktree; the worker then runs `bind`
#   tower-area.sh mark <id> review|return|clear|land|park|resume|drop [--sha <commit>] [note]
#   tower-area.sh rule "<what>" "<why>" "<cost if wrong>"
#   tower-area.sh rulings | list | archive
#
# Worker, from inside its worktree:
#   tower-area.sh bind <id>
#   tower-area.sh step <done> [total] [note]    never fails, never prints, never wakes anyone
#   tower-area.sh deliver DONE|CONCERNS|BLOCKED|NEEDS_CONTEXT [note]
set -u
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"
# A progress report must never cost a worker its turn: silent and successful, whatever happens.
is_step=0
if [ "${1:-}" = step ]; then is_step=1; exec >/dev/null 2>&1; fi
home=$(tower_home) || { [ "$is_step" -eq 1 ] && exit 0; exit 2; }
areas="$home/areas"
mkdir -p "$areas" "$home/reports" "$home/usage" "$home/locks" || { [ "$is_step" -eq 1 ] && exit 0; exit 2; }
gate="$here/tower-gate.sh"
classes=" ace scout freighter liner prop "

usage() { sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }

valid_id() {
  printf '%s' "$1" | LC_ALL=C grep -Eq '^[a-z0-9][a-z0-9._-]*$' && return 0
  echo "invalid area id '$1': use lowercase letters, digits, . _ -" >&2
  return 1
}

# A flag with no value is a usage error, not a hang in `shift 2`.
need_value() { [ "$1" -ge 2 ] || usage; }

need_area() {
  valid_id "$1" || exit 2
  [ -f "$areas/$1" ] || { echo "no area named $1. See tower-area.sh list." >&2; exit 2; }
}

put() {
  local id=$1
  shift
  lock_take "$home/locks/$id" expire || return 2
  area_put "$areas/$id" "$@"
  lock_release
}

cmd_add() {
  local id=${1:-} title=${2:-} class=liner after= owns= worktree= branch=
  [ "$#" -ge 2 ] || usage
  shift 2
  valid_id "$id" || exit 2
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --class) need_value "$#"; class=$2; shift 2 ;;
      --after) need_value "$#"; after="$after${after:+,}$2"; shift 2 ;;
      --owns) need_value "$#"; owns="$owns${owns:+,}$2"; shift 2 ;;
      --worktree) need_value "$#"; worktree=${2%/}; worktree=${worktree##*/}; shift 2 ;;
      --branch) need_value "$#"; branch=$2; shift 2 ;;
      *) usage ;;
    esac
  done
  case "$classes" in *" $class "*) ;; *) echo "unknown class '$class'. Use one of:$classes" >&2; exit 2 ;; esac
  local seq state=planned
  [ -z "$worktree" ] || state=flying
  # Checked inside the lock, so two people adding the same id cannot both succeed.
  lock_take "$home/locks/$id" expire || exit 2
  [ ! -f "$areas/$id" ] || { echo "area $id already exists" >&2; exit 2; }
  seq=$(( $(ls "$areas" | grep -c .) + 1 ))
  area_put "$areas/$id" "seq=$seq" "title=$title" "class=$class" "after=$after" "owns=$owns" \
    "worktree=$worktree" "branch=$branch" "state=$state" "round=1" "step_done=0" "step_total=0"
  lock_release
  echo "planned: $id ($class)"
}

# Plans change before anything flies. Afterwards the record is history: drop it instead.
cmd_edit() {
  local id=${1:-}
  [ "$#" -ge 3 ] || usage
  shift
  need_area "$id"
  require_state "$id" edit planned
  while [ "$#" -gt 0 ]; do
    need_value "$#"
    case "$1" in
      --title) put "$id" "title=$2" || exit 2 ;;
      --class)
        case "$classes" in *" $2 "*) ;; *) echo "unknown class '$2'. Use one of:$classes" >&2; exit 2 ;; esac
        put "$id" "class=$2" || exit 2
        ;;
      --after) put "$id" "after=$2" || exit 2 ;;
      --owns) put "$id" "owns=$2" || exit 2 ;;
      *) usage ;;
    esac
    shift 2
  done
  echo "$id: edited"
}

# Moved aside, not deleted: a plan entry may hold thought worth finding again.
cmd_remove() {
  [ "$#" -eq 1 ] || usage
  need_area "$1"
  require_state "$1" remove planned
  mkdir -p "$home/removed"
  mv "$areas/$1" "$home/removed/$1.$(date +%s)"
  echo "$1: removed"
}

# Normalised path prefix of an ownership entry: src/api/** and src/api both mean src/api.
owns_prefix() {
  printf '%s' "$1" | sed -e 's/^\.\///' -e 's/\/\*\*$//' -e 's/\/\*$//' -e 's/\/$//'
}

prefixes_clash() {
  case "$1" in "$2"|"$2"/*) return 0 ;; esac
  case "$2" in "$1"/*) return 0 ;; esac
  return 1
}

cmd_check() {
  local problems=0 warnings=0 file id dep title list seen pass changed
  local ids
  ids=
  for file in "$areas"/*; do
    [ -f "$file" ] || continue
    case "$(area_get "$file" state)" in dropped) ;; *) ids="$ids $(basename "$file")" ;; esac
  done
  ids=${ids# }
  [ -n "$ids" ] || { echo "no areas planned"; return 0; }
  # Ownership entries are patterns to compare, never to expand against the current folder.
  set -f
  for id in $ids; do
    file="$areas/$id"
    title=$(area_get "$file" title)
    case "$title" in
      *TBD*|*TODO*|*FIXME*|*'<'*'>'*) echo "PROBLEM $id: the title is a placeholder: $title"; problems=$((problems + 1)) ;;
    esac
    list=$(area_get "$file" after | tr ',' ' ')
    for dep in $list; do
      [ -f "$areas/$dep" ] || { echo "PROBLEM $id: waits for unknown area $dep"; problems=$((problems + 1)); continue; }
      [ "$(area_get "$areas/$dep" state)" != dropped ] || { echo "PROBLEM $id: waits for dropped area $dep"; problems=$((problems + 1)); }
    done
    [ -n "$(area_get "$file" owns)" ] || { echo "warning $id: owns nothing yet, so overlaps cannot be checked"; warnings=$((warnings + 1)); }
  done

  # A dependency cycle never takes off: peel areas whose dependencies are all resolved.
  seen=" "
  pass=1
  while [ "$pass" -eq 1 ]; do
    pass=0
    for id in $ids; do
      case "$seen" in *" $id "*) continue ;; esac
      changed=1
      for dep in $(area_get "$areas/$id" after | tr ',' ' '); do
        [ -f "$areas/$dep" ] || continue
        case "$seen" in *" $dep "*) ;; *) changed=0 ;; esac
      done
      if [ "$changed" -eq 1 ]; then seen="$seen$id "; pass=1; fi
    done
  done
  for id in $ids; do
    case "$seen" in *" $id "*) ;; *) echo "PROBLEM $id: part of a dependency cycle"; problems=$((problems + 1)) ;; esac
  done

  # Two areas owning the same path may only fly in order.
  local a b pa pb ownsa ownsb clashes
  for a in $ids; do
    ownsa=$(area_get "$areas/$a" owns | tr ',' ' ')
    for b in $ids; do
      [ "$a" \< "$b" ] || continue
      ownsb=$(area_get "$areas/$b" owns | tr ',' ' ')
      clashes=
      for pa in $ownsa; do
        for pb in $ownsb; do
          if prefixes_clash "$(owns_prefix "$pa")" "$(owns_prefix "$pb")"; then clashes="$clashes $pa<>$pb"; fi
        done
      done
      [ -n "$clashes" ] || continue
      if depends_on "$a" "$b" || depends_on "$b" "$a"; then
        echo "ordered  $a -> $b share:$clashes"
      else
        echo "PROBLEM $a <> $b own the same files and may fly together:$clashes. Split ownership or add --after."
        problems=$((problems + 1))
      fi
    done
  done

  set +f
  local blanks
  blanks=$(grep -c '<[a-z]' "$home/brief.md" 2>/dev/null || true)
  if [ "${blanks:-0}" -gt 0 ]; then
    echo "warning: brief.md still has $blanks line(s) with <placeholders>. Workers read it, so fill them or write none."
    warnings=$((warnings + 1))
  fi
  if [ "$problems" -gt 0 ]; then
    echo "preflight: $problems problem(s), $warnings warning(s)"
    return 1
  fi
  echo "preflight: clear, $warnings warning(s)"
}

# Does area $1 wait for $2, directly or through others?
depends_on() {
  local target=$2 dep next frontier seen=" "
  frontier=$(area_get "$areas/$1" after | tr ',' ' ')
  while [ -n "${frontier// /}" ]; do
    next=
    for dep in $frontier; do
      [ "$dep" != "$target" ] || return 0
      case "$seen" in *" $dep "*) continue ;; esac
      seen="$seen$dep "
      [ ! -f "$areas/$dep" ] || next="$next $(area_get "$areas/$dep" after | tr ',' ' ')"
    done
    frontier=$next
  done
  return 1
}

cmd_launch() {
  local native=0 force=0 base= ids= id
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --native) native=1; shift ;;
      --force) force=1; shift ;;
      --base) need_value "$#"; base=$2; shift 2 ;;
      -*) usage ;;
      *) ids="$ids $1"; shift ;;
    esac
  done
  [ -n "$ids" ] || usage
  [ -n "$base" ] || base=$(base_branch)
  local root parent repo folder branch dep setup path state base_sha
  root=$(git worktree list --porcelain | sed -n '1s/^worktree //p')
  parent=${TOWER_WORKTREES:-$(config_get "$home" worktrees)}
  [ -n "$parent" ] || parent=$(dirname "$root")
  repo=$(basename "$root")
  setup=$(config_get "$home" setup)
  base_sha=$(git rev-parse "$base" 2>/dev/null) || { echo "unknown base: $base" >&2; exit 2; }
  for id in $ids; do
    need_area "$id"
    state=$(area_get "$areas/$id" state)
    case "$state" in
      planned|flying|blocked) ;;
      *) echo "refused: $id is $state. Only planned or stopped areas launch." >&2; exit 1 ;;
    esac
    if [ "$force" -eq 0 ]; then
      for dep in $(area_get "$areas/$id" after | tr ',' ' '); do
        if [ "$(area_get "$areas/$dep" state)" != landed ]; then
          echo "refused: $id waits for $dep, which has not landed. Use --force only if you know why." >&2
          exit 1
        fi
      done
    fi
    if [ "$native" -eq 1 ]; then
      "$gate" room || exit 1
      "$gate" add --force "@$id" >/dev/null || exit 1
      put "$id" state=flying "started=$(date +%s)" "base=$base" "base_sha=$base_sha" || exit 2
      echo "flying: $id. Have the worker run: tower-area.sh bind $id"
      continue
    fi
    folder=$(area_get "$areas/$id" worktree)
    [ -n "$folder" ] || folder="$repo-$id"
    branch=$(area_get "$areas/$id" branch)
    [ -n "$branch" ] || branch="area/$id"
    path=$(worktree_path "$folder")
    # Check before creating anything, so a refusal leaves no worktree behind.
    "$gate" list | grep -qx "  $folder" || "$gate" room || exit 1
    if [ -z "$path" ]; then
      path="$parent/$folder"
      if git show-ref --verify --quiet "refs/heads/$branch"; then
        git worktree add -q "$path" "$branch" || exit 1
      else
        git worktree add -q -b "$branch" "$path" "$base" || exit 1
      fi
    fi
    "$gate" add "$folder" >/dev/null || exit 1
    put "$id" state=flying "worktree=$folder" "branch=$branch" "base=$base" "base_sha=$base_sha" "started=$(date +%s)" || exit 2
    if [ -n "$setup" ]; then
      if ! (cd "$path" && sh -c "$setup"); then
        put "$id" state=blocked "note=worktree setup failed: $setup"
        echo "setup failed in $path: $setup" >&2
        exit 1
      fi
    fi
    printf 'flying: %s  %s  %s\n' "$id" "$branch" "$path"
  done
}

cmd_bind() {
  local id=${1:-} folder branch
  [ -n "$id" ] || usage
  need_area "$id"
  folder=$(worktree_name)
  branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
  if [ "$branch" = HEAD ] || [ -z "$branch" ]; then
    echo "not bound: this worktree is on no branch. Create one with git switch -c first." >&2
    exit 1
  fi
  "$gate" add --force "$folder" >/dev/null || exit 1
  "$gate" rm "@$id" >/dev/null 2>&1 || true
  put "$id" "worktree=$folder" "branch=$branch" || exit 2
  echo "bound: $id to $folder"
}

cmd_step() {
  local id done_=${1:-0} total=${2:-} note=${3:-}
  id=$(area_of_worktree "$home" "$(worktree_name)") || return 0
  case "$done_" in ''|*[!0-9]*) return 0 ;; esac
  [ "${#done_}" -le 6 ] || return 0
  set -- "step_done=$done_" "note=$note"
  if is_count "$total"; then set -- "$@" "step_total=$total"; fi
  put "$id" "$@" >/dev/null 2>&1 || true
}

cmd_deliver() {
  local status=${1:-} note=${2:-} id base tip ahead dirty state
  case "$status" in DONE|CONCERNS|BLOCKED|NEEDS_CONTEXT) ;; *) usage ;; esac
  id=$(area_of_worktree "$home" "$(worktree_name)") || { echo "this worktree is not bound to an open area. Run tower-area.sh bind <id> first." >&2; exit 2; }
  state=$(area_get "$areas/$id" state)
  case "$state" in
    flying|blocked) ;;
    *) echo "not delivered: $id is $state. Wait for the tower to return it." >&2; exit 1 ;;
  esac
  case "$status" in
    BLOCKED|NEEDS_CONTEXT)
      put "$id" state=blocked "status=$status" "note=$note" || exit 2
      echo "$id: $status, the tower has been told through the board"
      return 0
      ;;
  esac
  base=$(area_get "$areas/$id" base)
  [ -n "$base" ] || base=$(base_branch)
  dirty=$(git status --porcelain --untracked-files=normal | grep -c . || true)
  if [ "$dirty" -gt 0 ]; then
    echo "not delivered: $dirty uncommitted file(s). A candidate is commits, so commit or remove them first." >&2
    exit 1
  fi
  ahead=$(git rev-list --count "$base..HEAD" 2>/dev/null || echo 0)
  if [ "$ahead" -eq 0 ]; then
    echo "not delivered: no commits ahead of $base, so there is nothing to land." >&2
    exit 1
  fi
  tip=$(git rev-parse --short HEAD)
  put "$id" state=candidate "status=$status" "tip=$tip" "note=$note" "step_done=$(area_get "$areas/$id" step_total)" || exit 2
  echo "$id: candidate at $tip"
}

# Only these moves exist. Everything else is a mistake worth refusing, not a state to record.
require_state() {
  local id=$1 action=$2 state
  shift 2
  state=$(area_get "$areas/$id" state)
  case " $* " in *" $state "*) return 0 ;; esac
  echo "refused: cannot $action $id while it is $state." >&2
  exit 1
}

cmd_mark() {
  local id=${1:-} action=${2:-} sha= note=
  [ "$#" -ge 2 ] || usage
  shift 2
  need_area "$id"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --sha) need_value "$#"; sha=$2; shift 2 ;;
      *) note="$note${note:+ }$1"; shift ;;
    esac
  done
  local file="$areas/$id" folder branch round base tip reviewed moved base_sha
  folder=$(area_get "$file" worktree)
  branch=$(area_get "$file" branch)
  case "$action" in
    review)
      require_state "$id" review candidate
      put "$id" state=review "note=$note" || exit 2
      ;;
    return)
      require_state "$id" return candidate review cleared blocked
      round=$(( $(area_get "$file" round) + 1 ))
      put "$id" state=flying "round=$round" "note=$note" status= cleared_sha= || exit 2
      [ -z "$folder" ] || "$gate" add --force "$folder" >/dev/null
      if [ "$round" -ge 3 ]; then
        echo "$id has come back $((round - 1)) times. Do not return it again: re-plan, change its class, or ask the person."
      fi
      ;;
    clear)
      require_state "$id" clear candidate review
      tip=$(area_get "$file" tip)
      if [ -n "$sha" ]; then
        tip=$(git rev-parse --short "$sha" 2>/dev/null) || { echo "cannot resolve $sha" >&2; exit 2; }
      else
        moved=$(git rev-parse --short "$branch" 2>/dev/null)
        if [ -n "$moved" ] && [ "$moved" != "$tip" ]; then
          echo "refused: $branch is at $moved, but $tip was delivered. Have the worker deliver again, or pass --sha after reading it." >&2
          exit 1
        fi
      fi
      [ -n "$tip" ] || { echo "refused: $id has no delivered commit." >&2; exit 1; }
      put "$id" state=cleared "cleared_sha=$tip" "note=$note" || exit 2
      ;;
    land)
      if [ "$(area_get "$file" state)" != cleared ]; then
        echo "refused: $id is $(area_get "$file" state), not cleared. Review it, then mark it clear." >&2
        exit 1
      fi
      base=$(area_get "$file" base)
      [ -n "$base" ] || base=$(base_branch)
      reviewed=$(area_get "$file" cleared_sha)
      tip=$(git rev-parse --short "${sha:-$reviewed}" 2>/dev/null) || { echo "cannot resolve ${sha:-$reviewed}" >&2; exit 2; }
      if ! git merge-base --is-ancestor "$tip" "$base" 2>/dev/null; then
        echo "refused: $tip is not on $base, so $id has not landed. After a rebase or batch, pass --sha <the commit on $base>." >&2
        exit 1
      fi
      base_sha=$(area_get "$file" base_sha)
      if [ -n "$base_sha" ]; then
        # The base as it was at launch is on the base too, and proves nothing.
        if [ "$(git rev-parse "$tip")" = "$(git rev-parse "$base_sha" 2>/dev/null)" ] || ! git merge-base --is-ancestor "$base_sha" "$tip" 2>/dev/null; then
          echo "refused: $tip is not newer than where $id started, so it cannot be its work." >&2
          exit 1
        fi
      fi
      put "$id" state=landed "landed_sha=$tip" "landed_at=$(date +%s)" "note=$note" || exit 2
      close_gate "$id" "$folder"
      ;;
    park)
      require_state "$id" park flying blocked
      close_gate "$id" "$folder"
      ;;
    resume)
      require_state "$id" resume flying blocked
      [ -z "$folder" ] || "$gate" add "$folder" >/dev/null || exit 1
      ;;
    drop)
      require_state "$id" drop planned flying blocked candidate review cleared
      put "$id" state=dropped "note=$note" || exit 2
      close_gate "$id" "$folder"
      ;;
    *) usage ;;
  esac
  echo "$id: $action"
}

close_gate() {
  "$gate" rm "@$1" >/dev/null 2>&1 || true
  [ -z "$2" ] || "$gate" rm "$2" >/dev/null
}

cmd_list() {
  local file id
  for file in "$areas"/*; do
    [ -f "$file" ] || continue
    id=$(basename "$file")
    printf '%s\t%s\t%s\t%s\n' "$(area_get "$file" seq)" "$id" "$(area_get "$file" state)" "$(area_get "$file" title)"
  done | sort -n | cut -f2-
}

cmd_rule() {
  [ "$#" -eq 3 ] || usage
  printf 'Ruling: %s. Why: %s. If wrong: %s\n' "$(clean_text "$1")" "$(clean_text "$2")" "$(clean_text "$3")" >> "$home/rulings.log"
}

cmd_archive() {
  local stamp target
  stamp=$(date +%Y%m%d-%H%M%S)
  target="$home/archive/$stamp"
  mkdir -p "$target"
  for item in areas usage reports rulings.log mission; do
    [ -e "$home/$item" ] && mv "$home/$item" "$target/"
  done
  mkdir -p "$areas" "$home/reports" "$home/usage"
  # Reservations and open slots belonged to that plan; the base checkout stays.
  if [ -f "$home/active.list" ]; then
    gate_lock "$home" || exit 2
    printf '# Worktree folders allowed on the runways, one per line.\n%s\n' "$(base_checkout_folder)" > "$home/active.list"
    lock_release
  fi
  echo "archived: $target"
}

verb=${1:-}
[ "$#" -eq 0 ] || shift
case "$verb" in
  mission) [ "$#" -eq 1 ] || usage; clean_text "$1" > "$home/mission" ;;
  add) cmd_add "$@" ;;
  edit) cmd_edit "$@" ;;
  remove) cmd_remove "$@" ;;
  check) cmd_check ;;
  launch) cmd_launch "$@" ;;
  bind) cmd_bind "$@" ;;
  step) cmd_step "$@"; exit 0 ;;
  deliver) cmd_deliver "$@" ;;
  mark) cmd_mark "$@" ;;
  list) cmd_list ;;
  rule) cmd_rule "$@" ;;
  rulings) [ ! -f "$home/rulings.log" ] || cat "$home/rulings.log" ;;
  archive) cmd_archive ;;
  *) usage ;;
esac
