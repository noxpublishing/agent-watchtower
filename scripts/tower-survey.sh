#!/usr/bin/env bash
# What a repository can tell before anyone asks. Changes nothing.
set -u
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"

echo "folder:     $(pwd)"
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "repository: none"
  echo "files:      $(ls -A | grep -c . || true)"
  echo
  "$here/tower-capacity.sh" 2>/dev/null | sed 's/^/  /'
  exit 0
fi
root=$(git rev-parse --show-toplevel)
cd "$root" || exit 2
commits=$(git rev-list --count HEAD 2>/dev/null || echo 0)
base=$(base_branch)
echo "repository: $root"
echo "commits:    $commits"
echo "base:       ${base:-unknown} @ $(git rev-parse --short "${base:-HEAD}" 2>/dev/null)"
echo "remote:     $(git remote get-url origin 2>/dev/null | sed -E 's#//[^/@]*@#//#' || true)"
echo "tracked:    $(git ls-files | grep -c . || true) files"
echo "uncommitted: $(git status --porcelain | grep -c . || true) files"
echo "branches:   $(git for-each-ref --format='%(refname:short)' refs/heads | grep -c . || true)"

echo
echo "worktrees:"
git worktree list --porcelain | sed -n 's/^worktree //p' | while IFS= read -r path; do
  if [ -d "$path" ]; then
    printf '  %s  %s  %s uncommitted\n' "$(basename "$path")" "$(git -C "$path" rev-parse --abbrev-ref HEAD 2>/dev/null)" "$(git -C "$path" status --porcelain 2>/dev/null | grep -c . || true)"
  else
    printf '  %s  folder is gone\n' "$(basename "$path")"
  fi
done

echo
echo "unmerged branches:"
git for-each-ref --sort=-committerdate --format='  %(refname:short)  last commit %(committerdate:relative) by %(authorname)' refs/heads --no-merged "${base:-HEAD}" 2>/dev/null | head -20

echo
echo "project rules:"
for file in CLAUDE.md AGENTS.md CONTRIBUTING.md DESIGN.md docs/SPEC.md; do
  [ ! -f "$file" ] || echo "  $file"
done

echo
echo "ci:"
for file in .github/workflows/* .gitlab-ci.yml .circleci/config.yml; do
  [ ! -e "$file" ] || echo "  $file"
done

echo
echo "likely commands:"
if [ -f package.json ]; then
  runner=npm
  [ ! -f pnpm-lock.yaml ] || runner=pnpm
  [ ! -f yarn.lock ] || runner=yarn
  [ ! -f bun.lockb ] && [ ! -f bun.lock ] || runner=bun
  # On one line first, because a minified package.json is still a package.json.
  tr -d '\n' < package.json | sed -n 's/.*"scripts"[[:space:]]*:[[:space:]]*{\([^}]*\)}.*/\1/p' | tr ',' '\n' | sed -n 's/^[[:space:]]*"\([^"]*\)"[[:space:]]*:.*/\1/p' | grep -E '^(test|typecheck|type-check|lint|build|dev|start|e2e)' | sed "s/^/  $runner run /"
fi
[ ! -f Cargo.toml ] || echo "  cargo test"
[ ! -f go.mod ] || echo "  go test ./..."
[ ! -f pyproject.toml ] || echo "  pytest"
if [ -f Makefile ]; then grep -E '^(test|build|lint|check):' Makefile | sed 's/:.*//; s/^/  make /'; fi

echo
"$here/tower-capacity.sh" 2>/dev/null | sed 's/^/  /'
