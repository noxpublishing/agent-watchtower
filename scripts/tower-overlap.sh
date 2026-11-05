#!/usr/bin/env bash
# Which branches touch the same files? Run this before deciding an order.
#   tower-overlap.sh [base]            all pairs of worktree branches
# A pair sharing many files should land one after the other, not fly together.
set -u
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"
base=${1:-$(base_branch)}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
names=""
for branch in $(git worktree list --porcelain | sed -n 's|^branch refs/heads/||p'); do
  [ "$branch" = "$base" ] && continue
  safe=$(printf '%s' "$branch" | tr '/ ' '__')
  git diff --name-only "$base...$branch" 2>/dev/null | sort > "$work/$safe"
  printf '%s\t%s\n' "$safe" "$branch" >> "$work/.names"
  names="$names $safe"
done
found=0
for a in $names; do
  for b in $names; do
    case "$a" in "$b") continue ;; esac
    [ "$a" \< "$b" ] || continue
    shared=$(comm -12 "$work/$a" "$work/$b")
    [ -n "$shared" ] || continue
    found=1
    count=$(printf '%s\n' "$shared" | grep -c .)
    echo "$(grep -F "$a	" "$work/.names" | cut -f2) <> $(grep -F "$b	" "$work/.names" | cut -f2): $count shared"
    printf '%s\n' "$shared" | head -"${TOWER_OVERLAP_FILES:-5}" | sed 's/^/  /'
  done
done
[ "$found" -eq 1 ] || echo "no shared files"
