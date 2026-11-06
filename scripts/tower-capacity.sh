#!/usr/bin/env bash
# What this machine can carry. The numbers are advice; the limit is the person's call.
#   tower-capacity.sh                                 machine, current limits, a suggestion
#   tower-capacity.sh set [--flying <n>|off] [--runways <n>|auto]
# Stored per repository. TOWER_MAX_ACTIVE and TOWER_RUNWAYS override it for one process.
set -u
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"
# Reading the machine needs no repository; storing a limit does.
home=$(tower_home 2>/dev/null) || home=

if [ "${1:-}" = "set" ]; then
  [ -n "$home" ] || { echo "watchtower: limits are stored per repository, and this is not one" >&2; exit 2; }
  shift
  [ "$#" -gt 0 ] || { sed -n '2,5p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }
  gate_lock "$home" || exit 2
  while [ "$#" -gt 0 ]; do
    case "$1:${2:-}" in
      --flying:off) config_set "$home" flying off ;;
      --runways:auto) config_set "$home" runways auto ;;
      --flying:*) is_count "${2:-}" || { echo "--flying needs a number or off, got: ${2:-}" >&2; exit 2; }; config_set "$home" flying "$2" ;;
      --runways:*) is_count "${2:-}" || { echo "--runways needs a number or auto, got: ${2:-}" >&2; exit 2; }; config_set "$home" runways "$2" ;;
      *) echo "expected --flying <n>|off or --runways <n>|auto, got: $1 ${2:-}" >&2; exit 2 ;;
    esac
    shift 2
  done
fi

cores=$(machine_cores)
if [ "$(uname)" = Darwin ]; then
  total_mb=$(( $(sysctl -n hw.memsize) / 1048576 ))
  free_mb=$(vm_stat | awk -v size="$(sysctl -n hw.pagesize)" '/Pages (free|inactive|speculative)/ { gsub(/\./, "", $NF); n += $NF } END { printf "%d", n * size / 1048576 }')
else
  total_mb=$(awk '/^MemTotal:/ { printf "%d", $2 / 1024 }' /proc/meminfo)
  free_mb=$(awk '/^MemAvailable:/ { printf "%d", $2 / 1024 }' /proc/meminfo)
fi
load=$(uptime | sed 's/.*load averages*: *//' | tr -s ', ' ' ' | cut -d' ' -f1)

# Assumptions, printed below: 4 GB for the system, 2 GB per heavy check, 1 GB per agent.
spare_mb=$(( total_mb > 4096 ? total_mb - 4096 : 1024 ))
suggest_runways=$(( cores / 4 ))
[ "$suggest_runways" -le $(( spare_mb / 4096 )) ] || suggest_runways=$(( spare_mb / 4096 ))
[ "$suggest_runways" -ge 1 ] || suggest_runways=1
suggest_flying=$(( (spare_mb - suggest_runways * 2048) / 1024 ))
[ "$suggest_flying" -le "$cores" ] || suggest_flying=$cores
[ "$suggest_flying" -ge 1 ] || suggest_flying=1

flying=$(flying_limit "$home")
runways=$(runway_limit "$home")
printf 'machine: %s cores, %s GB RAM, %s GB available, load %s\n' "$cores" "$(( total_mb / 1024 ))" "$(( free_mb / 1024 ))" "$load"
printf 'limits:  flying %s, runways %s\n' "${flying:-no limit}" "$runways"
printf 'suggest: up to %s flying, %s runways\n' "$suggest_flying" "$suggest_runways"
echo "         estimate: 4 GB for the system, 2 GB per heavy check, 1 GB per agent"
if awk -v l="$load" -v c="$cores" 'BEGIN { exit !(l + 0 > c + 0) }'; then
  echo "note:    load is above the core count right now, so something else is busy"
fi
