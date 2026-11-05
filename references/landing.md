# Landing a candidate

## Before you start

- `git status -sb` in the base checkout. If someone else has uncommitted changes that overlap, wait. Do not stash their work.
- `git fetch`, so you compare against the real base and not a stale local copy.
- `scripts/land-check.sh <branch>`.
- Check that CI on the current base is green or that you know why not. A red base hides new failures.

## What "ready" means

The candidate is one commit or a few clean ones, on or near the current base, and its message says what was verified, on which commit, and what was not checked. If it only says "tests pass", ask. If the session's report and the commit disagree, believe the commit and the logs.

Not checked is allowed. Hidden is not. Pass the honest gaps on to the human.

## Rebasing

| Conflict | Who solves it |
| --- | --- |
| Lists, navigation, imports, docs tables, counters, lock files | You, in a throwaway worktree |
| Behaviour, security rules, two features touching the same logic | The session that knows the area, with a precise note on what must survive from both sides |

Tell the session exactly what it must not turn back. A rebase is where finished work gets silently undone. After every rebase, read the file list for anything unexpectedly deleted.

## How much to verify

Full verification on a close base, then targeted suites after the last rebase, is usually enough, as long as CI runs everything after the push. Rerun fully when:

- the base brought changes to the same area
- you resolved real conflicts
- a dependency or migration changed

If a full run has a failure that is not in the candidate's area, run that suite alone. If it passes alone, it is probably load or test pollution. Land if the area is unrelated, write it down, and do not call it fixed.

## Batch landings

When several candidates are ready, a batch saves a lot:

```bash
git worktree add -b integrate/batch-a ../integrate-batch-a <base>
cd ../integrate-batch-a
git cherry-pick <candidate-1> <candidate-2>
```

Resolve the conflicts, then run one full verification. The candidates have stopped running by now, so remove them from the gate and add the batch worktree. If they are still busy, use `tower-gate.sh add --force` for this one run. If it is green, fast-forward the base and push once.

Afterwards, tell the sessions their work is on the base. Their branches now differ from what landed, so they must start any follow-up from the new base.

## After the push

Pushing feature branches can cost a CI run each, so normally only the base gets pushed. If only CI can check something (containers, another platform) and the candidate changes exactly that, push its branch once under a temporary name, wait for the result, then land.

Check CI before the next landing. CI catches what your machine cannot: containers, other platforms, other runtime versions. If it goes red through your landing, that is your top priority, ahead of all new work, and you tell the human.

When fixing a red base:

- Find out whether the fix passes **with its neighbours**, not only alone.
- Do not make other sessions' full runs depend on your guess. Warn them what is broken and from when.
- If a stuck check blocks the fix, let the fix skip the queue with `runway.sh --priority`.

## Cleanup

`git worktree remove`, `git branch -D`, and update `active.list`. Add a line to the project's journal if it has one. Keep `handoff.md` current.
