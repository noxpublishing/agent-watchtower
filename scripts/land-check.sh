#!/usr/bin/env bash
# Report before landing: does not alter branches or worktrees.
# The merge-tree simulation may write Git objects.
#   land-check.sh <candidate-branch> [base]
set -u
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"
[ "$#" -ge 1 ] || { sed -n '2,3p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }
candidate=$1
base=${2:-$(base_branch)}
git rev-parse --verify --quiet "$candidate" >/dev/null || { echo "unknown branch: $candidate" >&2; exit 2; }
git rev-parse --verify --quiet "$base" >/dev/null || { echo "unknown base: '$base'. Pass it as the second argument or set TOWER_BASE." >&2; exit 2; }
if ! git merge-base "$base" "$candidate" >/dev/null 2>&1; then
  echo "no common history between $candidate and $base: this is not a normal candidate" >&2
  exit 2
fi

counts=$(git rev-list --left-right --count "$candidate...$base" | tr '\t' ' ')
ahead=${counts%% *}
behind=${counts##* }
echo "candidate: $candidate @ $(git rev-parse --short "$candidate")"
echo "base:      $base @ $(git rev-parse --short "$base")"
echo "ahead $ahead, behind $behind"
if [ "$ahead" -eq 0 ]; then echo "nothing to land"
elif [ "$behind" -eq 0 ]; then echo "fast-forward possible"
else echo "needs a rebase first"; fi

echo
echo "commits:"
git log --format='  %h %s' "$base..$candidate" | head -20

echo
echo "last commit message:"
git log -1 --format='%B' "$candidate" | sed 's/^/  /' | head -40

echo
git diff --stat "$base...$candidate" | tail -1

deleted=$(git diff --name-only --diff-filter=D "$base...$candidate")
if [ -n "$deleted" ]; then
  echo
  echo "DELETED files, make sure none is someone else's work:"
  printf '%s\n' "$deleted" | sed 's/^/  /' | head -20
fi

sensitive=$(git diff --name-only "$base...$candidate" | grep -Ei '(^|/)(package-lock\.json|yarn\.lock|pnpm-lock\.yaml|poetry\.lock|uv\.lock|pipfile\.lock|requirements[^/]*\.txt|cargo\.lock|go\.sum|dockerfile[^/]*|compose[^/]*\.ya?ml|docker-compose[^/]*\.ya?ml)$|(^|/)migrations?/|(^|/)versions/[^/]*\.py$|\.github/workflows/' || true)
if [ -n "$sensitive" ]; then
  echo
  echo "Shared infrastructure touched, check for silent clashes:"
  printf '%s\n' "$sensitive" | sed 's/^/  /' | head -20
fi

# Names the file and the kind of hit, never the matched text: reports end up in transcripts.
added=$(git diff "$base...$candidate" | awk '/^\+\+\+ b\// { file = substr($0, 7); next } /^\+/ { print file "\t" $0 }')
secret=$(printf '%s\n' "$added" | grep -E 'BEGIN (RSA |OPENSSH |EC )?PRIVATE KEY|AKIA[0-9A-Z]{16}|sk-[A-Za-z0-9_-]{20,}|ghp_[A-Za-z0-9]{20,}|xox[bp]-[A-Za-z0-9-]{10,}' | cut -f1 | sort -u | sed 's/^/  possible secret in /')
debug=$(printf '%s\n' "$added" | grep -E 'console\.log\(|debugger;|pdb\.set_trace\(|breakpoint\(\)' | cut -f1 | sort -u | sed 's/^/  debug output in /')
smell=$(printf '%s\n%s\n' "$secret" "$debug" | grep . | head -15)
if [ -n "$smell" ]; then
  echo
  echo "Read before landing:"
  printf '%s\n' "$smell"
fi

echo
tree=$(git merge-tree --write-tree --name-only "$base" "$candidate" 2>/dev/null)
code=$?
if [ "$code" -eq 0 ]; then
  echo "merge simulation: no textual conflict. Identical edits to shared counters would not show here."
elif [ "$code" -eq 1 ]; then
  echo "merge simulation: CONFLICTS"
  printf '%s\n' "$tree" | sed -n '2,/^$/p' | sed 's/^/  /' | head -20
else
  echo "merge simulation failed (it needs git 2.38 or newer): $(git --version)"
fi
