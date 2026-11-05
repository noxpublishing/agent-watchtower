# Taking over

## Survey first

Change nothing until you know what exists.

1. `git fetch`, then `scripts/tower-status.sh`.
2. For each worktree: read the last commits and `git status --short`. Note what is finished, half done, or abandoned.
3. Find the sessions: list them in your tool, or ask the human which belong to what. A session stopped by a usage limit keeps its conversation and can usually be resumed. Sessions stopped long ago are often cheaper to replace with a fresh one and a short brief.
4. `scripts/tower-overlap.sh` shows which branches touch the same files.

## Make it safe

Back up before anyone rebases:

```bash
git update-ref refs/backup/<name> <branch>
```

This does not cover uncommitted work. To save that without changing the worktree:

```bash
snapshot=$(git -C <worktree> stash create)
[ -n "$snapshot" ] && git update-ref refs/backup/<name>-uncommitted "$snapshot"
```

`stash create` skips untracked files, so check those by hand. Do not commit or stash on someone's behalf if a person or a live session may still be working there. Ask first.

## Sort

Put each branch into one of three piles:

- **Nearly done:** needs a rebase and a check. These go first, because each landing is progress and lowers later conflicts.
- **In progress:** gets a block, with a resumed or fresh session.
- **Stale:** already on the base, replaced, or abandoned. Show this list to the human. Leave the backup ref either way.

Pairs with heavy overlap should not fly together.

## The base is already red

Nothing else can be judged while the base is red, so this comes first.

1. Read the failing run: `gh run view <id> --log-failed`. Note what fails and since which commit.
2. Reproduce it in a throwaway worktree. If it does not reproduce and only CI can see it, say so and fix it from the CI log.
3. Fix it as a small candidate, tested with the neighbouring suites, and land it. One session or you, not several.
4. If the fix takes long, the human decides whether unrelated candidates may land meanwhile. Keep a list of the known failures, so you can tell old red from new red, and land only what does not touch that area.

Tell the human it was already red when you arrived. That matters when they read the history later.
