#!/usr/bin/env bash
# Set up the tower for this repository: shared state, a brief and a shift log.
set -u
here=$(cd "$(dirname "$0")" && pwd)
skill=$(cd "$here/.." && pwd)
. "$here/lib.sh"
home=$(tower_home) || exit 2
mkdir -p "$home/queue" "$home/runways" "$home/status" "$home/areas" "$home/reports" "$home/usage"
for file in brief handoff; do
  [ -f "$home/$file.md" ] || cp "$skill/assets/$file-template.md" "$home/$file.md"
done
base_folder=$(base_checkout_folder)
gate_lock "$home" || exit 2
if [ ! -f "$home/active.list" ]; then
  printf '# Worktree folders allowed on the runways, one per line.\n%s\n' "$base_folder" > "$home/active.list"
fi
cat <<EOF
tower state: $home
brief:       $home/brief.md    fill this in, every session reads it
shift log:   $home/handoff.md  keep this current, the next tower reads it
gate:        $home/active.list  inspect current entries with tower-gate.sh list
next:        tower-capacity.sh shows what this machine carries; the person picks the numbers
EOF
