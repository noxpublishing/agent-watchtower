# Codex adaptation: 2026-11-05

The original skill was developed in Claude Code. This evaluation checked its instructions against the actual tools of the current Codex session and exercised the shell helpers in disposable repositories on Linux. All changes were prepared locally; nothing was pushed or deployed.

Source baseline: `9dca63b598a89ae86b43eba6531cd4b76ec7c9fa`.
Combined code and skill checked: `98abbf83ca521a8dca9c5e2fa8c575d705e75895`. Subsequent evaluation-record and README changes do not alter that tested runtime or skill entrypoint.

## Observations and changes

| Baseline observation | Change | Evidence |
| --- | --- | --- |
| The skill-creator validator rejected the description's unquoted colon | YAML folded description, shorter discovery text | Validator passes |
| Codex was routed to a generic paragraph about other agents | Explicit tool discovery, worktree ownership, capacity accounting and serial fallback | Two independent decision-evaluation passes; actual implementation worker used a separate worktree |
| Push/CI and shift changes assumed Claude capabilities | Local integration and current-task continuation are valid outcomes; unavailable usage and detach capabilities stay unavailable | New evaluator handles local-only takeover and no-agent compaction continuation without inventing tools or authorization |
| Full-suite failure guidance conflicted with the red-base procedure | Passing alone is evidence to investigate, not permission to land | Evaluator keeps ordinary landings paused and requests comparable evidence |
| Six simultaneous gate updates with max=1 admitted up to six workers; 6 of 10 baseline trials exceeded one | Serialize gate writers and initialization | Five synchronized rounds of six writers each admit exactly one |
| Existing capacity test observed only peak=1 despite a limit of two | Barrier-based competing checks | Six checks reach actual peak=2 and do not exceed it |
| Abort returned 143 and freed its slot while a TERM-ignoring child remained alive | Synchronous process-group shutdown before slot cleanup | Abort=143 and timeout=124; stubborn children stop before lane release |
| A PID-less lane waited indefinitely | Bounded diagnostic failure; no automatic deletion of potentially live state | Exit 2 with inspection hint for PID-less lane and orphaned gate lock |

The fresh decision evaluator also found ambiguous intake ordering and a misleading init message when preserving an existing gate. Both were corrected. `land-check.sh` now accurately describes its effects: it leaves branches and worktrees alone, but Git merge simulation can create internal objects.

## Checks completed

- Full Linux suite on the integrated code: exit 0, including the original functional checks and the new runtime regressions.
- Skill-creator `quick_validate.py`: passed using isolated PyYAML, without changing global Python dependencies.
- Bash syntax checks and `git diff --check`: passed.
- Decision evaluations: one baseline scenario and a fresh pass covering two Codex scenarios. These inspect decisions; they do not execute six product branches end to end.
- Local implementation pilot: one worker in its own gated worktree, scoped ownership, committed candidate, tower review and local integration, followed by the combined test suite.

Reproduce the full suite from this repository:

```bash
TOWER_TIMEOUT=180 TOWER_KILL_GRACE=1 \
  ./scripts/runway.sh codex-integration bash tests/run.sh
```

This requires the checkout to be active if a gate is configured. The regression fixtures use their own temporary tower state and clean up only their own processes.

## What this does not establish

- macOS was not available locally. The existing Linux/macOS CI matrix is retained, but the new code has not been pushed to trigger it.
- There is no production-scale A/B benchmark or measured token/cost reduction. Use the [execution pilot](../references/evaluation.md#a-small-execution-pilot) before making performance claims.
- Cleanup covers the launched process group. A process that deliberately creates another session, or SIGKILL against the wrapper itself, can bypass orderly cleanup.
- Orphaned locks and PID-less lanes require inspection; they deliberately fail closed instead of deleting ambiguous state.
- Portable completion polling can add up to roughly one second to a fast command. The helper is intended for expensive checks. `TOWER_KILL_GRACE` defaults to 20 seconds; regressions use one second to keep tests bounded.
