# Watchtower

**Run a whole fleet of coding agents without wrecking your main branch or your usage limits.**

Watchtower is an agent skill that turns one session into an orchestrator. It keeps a few agents active in their own git worktrees, parks the rest, verifies through a shared queue, and lands finished work on your main branch one candidate at a time.

It is written for Claude Code. The method and the scripts work with any agent, since they need only bash and git. Starting sessions differs per tool: see [the harness notes](references/harness.md).

## Why

Starting twenty agents feels fast. Then:

- they queue for the same machine, and one hung test blocks a slot for hours
- every landing makes the others stale, so everyone rebases and retests again
- two agents edit a shared counter the same way, git merges it cleanly, and the number is wrong
- your limit is gone, and half the work is still on branches

Watchtower came out of one such run with more than twenty parallel sessions. What helped most, near the end, was the simplest rule: **few fly at once, and only the tower lands.**

## What you get

| | |
|---|---|
| **Blocks** | Three active areas by default, the others parked with their work committed. |
| **Runways** | `runway.sh` queues heavy checks first come, first served, with a time limit that also stops child processes. |
| **A gate** | `tower-gate.sh` decides who may run. Parked worktrees get a clear message instead of wasting a full test run. |
| **Landing checks** | `land-check.sh` reports commits, deletions, shared infrastructure, possible secrets and a merge simulation before anything lands. |
| **One-screen status** | `tower-status.sh` shows runways, the queue, every worktree and CI. |
| **Takeover** | `tower-overlap.sh` and a recipe for adopting stalled worktrees and a base that is already red. |
| **Escalation rules** | Routine questions get decided. Law, money, publishing, accounts and deletion go to you, as options. |
| **Shift change** | When the orchestrator's own history gets expensive, a fresh one takes over from a handoff file. |
| **Field notes** | [The failure modes](references/failure-modes.md) that cost real hours, and how to avoid them. |

## Install

```bash
git clone https://github.com/noxpublishing/agent-watchtower ~/.claude/skills/watchtower
```

For other agents, clone it wherever they load skills from.

## Use

Just ask:

> Be the orchestrator for this repo. Get the billing, search and onboarding work onto main, three at a time.

> I have twelve stalled worktrees from yesterday. Take over and consolidate them.

> Parallel agents keep breaking main and burning my limit. Fix how we run them.

The state lives in `.git/watchtower`, shared by all worktrees and never committed.

## The scripts on their own

```bash
scripts/tower-init.sh                       # set up shared state
scripts/tower-gate.sh add search billing    # who may fly
scripts/runway.sh full-tests npm test       # run a heavy check in the queue
scripts/tower-status.sh                     # the fleet on one screen
scripts/land-check.sh feature/search        # report before landing
```

| Exit from `runway.sh` | Meaning |
|---|---|
| 75 | Parked, not your turn |
| 124 | Hung past the time limit |
| 143 | Aborted, run it again |
| other | The command's own result |

| Setting | Default | |
|---|---|---|
| `TOWER_RUNWAYS` | 3 | Checks running at once |
| `TOWER_MAX_ACTIVE` | 3 | Areas on the gate |
| `TOWER_TIMEOUT` | 5400 | Seconds before a check counts as hung |
| `TOWER_BASE` | origin's default | Base branch |
| `TOWER_HOME` | `.git/watchtower` | State directory |

## Tests

```bash
bash tests/run.sh
```

## Honest limits

- It comes from one large project and has not been benchmarked. Treat the default of three as a starting point.
- It does not replace your tests or CI. It makes them affordable to run in the right order.
- The orchestration is only as good as the sessions your tool can start. See [the harness notes](references/harness.md) for what works where.

## License

MIT
