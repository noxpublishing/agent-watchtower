# Reviewing a candidate

A worker's report is a claim. So is an inspector's. The commit, the diff and the output are the evidence.

## What counts as proof

| Claim | Needs | Not enough |
| --- | --- | --- |
| Tests pass | The command's output on this commit | An earlier run, "should pass" |
| The bug is fixed | The original symptom now passes, and the new test failed without the fix | Code changed, test written |
| Build works | The build command exited 0 | Linter passed |
| Requirements met | Each line of the brief checked | Tests pass |
| Agent finished | The diff shows it | The agent says so |

`deliver` already refuses a dirty tree and a branch with no commits, and `mark land` refuses work that is not on the base. Those catch false claims about state, not about behaviour.

## Who reads it

Read it yourself when the diff is small and you know the area. Otherwise start a `tower-inspector`, because what enters your context stays there and gets paid for on every later wake-up. Scale the inspector to the risk: a small mechanical diff does not need your best model, a concurrency change does.

Give the inspector paths, not paste: the brief, the report path, base and head commits. Do not tell it what you expect it to find, and do not relay the worker's confidence.

You decide on each finding. An inspector can be wrong too: check a finding against the code before acting on it, and push back with reasons when it does not hold. Silently dropping a finding is not allowed: fix it, or record why not with `tower-area.sh rule`.

## After the verdict

- **Clear:** `mark <id> clear`. It records the commit you reviewed, and landing a different one gets called out.
- **Return:** `mark <id> return "<defects>"`, naming defects, not re-explaining the task. Resume the same worker, since it has the context. The next review only checks that those defects are fixed and that nothing new broke; new findings about untouched code go in the log instead of restarting the loop.
- **Two returns and still wrong:** the problem is structural. Re-plan, move it up a class with a fresh worker, or ask the human.

When a worker delivers CONCERNS, read the concern first. It is often the most useful line in the report.

## The whole picture

Reviews one by one do not see how the pieces fit. Before the last landing of a larger plan, have an inspector read the whole change against the original goal, with the most capable model available. One round of fixes, one scoped re-check. What remains goes to the human as findings, not as another wave.
