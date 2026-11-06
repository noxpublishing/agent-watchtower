# Landing a candidate

## Before you start

- `git status -sb` in the base checkout. If someone else has uncommitted changes that overlap, wait. Do not stash their work.
- `git fetch`, so you compare against the real base and not a stale local copy.
- `"$WATCHTOWER_SKILL_DIR/scripts/land-check.sh" <branch>`.
- The area is cleared on the board. `references/review.md` covers getting it there.
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

Full verification on a close base, then targeted suites after the last rebase, can be enough when authorized CI will run everything after the push. For local-only integration, verify the actual combined commit locally and disclose checks that require CI. Rerun fully when:

- the base brought changes to the same area
- you resolved real conflicts
- a dependency or migration changed

If a full run fails but the affected suite passes alone, investigate test order, shared state and load. Passing alone does not establish that the candidate is unrelated. Compare base and candidate under the same conditions and preserve the failing logs. Follow the red-base procedure in `takeover.md`: pause normal landings until repaired, unless the user has authorized a documented exception for an independently assessed candidate. Do not label an incomplete verification green.

## Batch landings

When several candidates are ready, a batch saves a lot:

```bash
git worktree add -b integrate/batch-a ../integrate-batch-a <base>
cd ../integrate-batch-a
git cherry-pick <candidate-1> <candidate-2>
```

Resolve the conflicts, then run one full verification. Confirm that candidate workers have stopped before removing them from the gate and adding the batch worktree. `--force` bypasses the gate's active-area limit; it does not stop workers or increase machine capacity. Avoid it while candidates are still running. If the batch is green, fast-forward the agreed local target; push once only when authorized.

Mark each with `tower-area.sh mark <id> land --sha <its commit on the base>`. Afterwards, tell the sessions their work is on the base. Their branches now differ from what landed, so they must start any follow-up from the new base.

## Local preparation or publication

Keep the user's existing authorization explicit in the shared brief. When local-only work is requested or publication has not been authorized, leave a verified integration branch with its exact SHA and pending CI-only checks. Do not create a remote branch or push just to obtain CI evidence. Ask about publication only when the local result is ready for review and publication is actually needed.

If the user already authorized pushing the relevant branches, proceed within that scope without asking again. The instructions below apply to authorized publication.

## After an authorized push

Pushing feature branches can cost a CI run each, so normally only the base gets pushed. If only CI can check something (containers, another platform) and the candidate changes exactly that, push its branch once under a temporary name, wait for the result, then land.

Check CI before the next landing. CI catches what your machine cannot: containers, other platforms, other runtime versions. If it goes red through your landing, that is your top priority, ahead of all new work, and you tell the human.

When fixing a red base:

- Find out whether the fix passes **with its neighbours**, not only alone.
- Do not make other sessions' full runs depend on your guess. Warn them what is broken and from when.
- If a stuck check blocks the fix, let the fix skip the queue with `runway.sh --priority`.

## Cleanup

Confirm the owning session has stopped. Inspect tracked and untracked changes and verify every candidate commit is preserved. Prefer `git worktree remove` without force and `git branch -d`. After a cherry-pick or rebase, keep a backup ref and check that the actual changes survived before deleting the original branch; a failed safe delete is a reason to inspect, not automatically use `-D`. Keep `handoff.md` current.
