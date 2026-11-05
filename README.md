<p align="center">
  <img src="docs/img/hero.svg" alt="Watchtower: a lit tower watches three agents land on main while the others wait parked" width="100%">
</p>

<p align="center">
  <a href="https://github.com/noxpublishing/agent-watchtower/actions/workflows/test.yml"><img src="https://github.com/noxpublishing/agent-watchtower/actions/workflows/test.yml/badge.svg" alt="Tests"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-3DDC97" alt="MIT license"></a>
  <img src="https://img.shields.io/badge/Claude%20Code-skill-FFB454" alt="Claude Code skill">
  <img src="https://img.shields.io/badge/needs-bash%20%2B%20git-7C8AA2" alt="Needs bash and git">
</p>

<p align="center">
  <b>One session becomes the tower. A few agents fly. Finished work lands on main, one at a time.</b>
</p>

```bash
git clone https://github.com/noxpublishing/agent-watchtower ~/.claude/skills/watchtower
```

Then, in any repository:

> Be the orchestrator for this repo. Get the billing, search and onboarding work onto main, three at a time.

## Twenty agents are not twenty times faster

Starting a pile of agents feels great for about an hour. Then they queue for the same machine, every landing makes the others stale, a hung test holds a slot all afternoon, `main` turns red, and your usage limit is gone with half the work still on branches.

Watchtower came out of exactly that: one real project, more than twenty parallel sessions, and at one point 16 checks waiting on 3 slots for over an hour. What finally worked was almost embarrassingly simple.

<p align="center">
  <img src="docs/img/before-after.svg" alt="Everyone at once compared with three at a time" width="100%">
</p>

## How it works

```mermaid
flowchart LR
    P(["Parked<br/>work committed,<br/>costs nothing"]) -->|tower calls| F(["Flying<br/>max 3"])
    F -->|heavy check| R[["Runway<br/>queue + time limit"]]
    R -->|green| C(["Candidate"])
    R -->|hung, exit 124| F
    C -->|land-check,<br/>rebase, verify| T{"Tower"}
    T -->|fast-forward| M(["main"])
    M -->|check CI,<br/>call the next| P
    T -.->|law, money, accounts,<br/>publishing, deleting| H(["You decide"])

    style M fill:#123326,stroke:#3DDC97,color:#7FE7BB
    style F fill:#3A2B12,stroke:#FFB454,color:#FFC56B
    style P fill:#1B2436,stroke:#54627A,color:#B6C3D6
    style H fill:#1B2436,stroke:#FF8A80,color:#FFB3AC
```

## The six laws

| | |
|---|---|
| **1. Few fly at once** | Three active areas by default, the rest park. Every landing forces everyone still flying to rebase and retest, so fewer flying means less repeated work. |
| **2. Only the tower lands** | One writer on the base branch means one place that knows its state. |
| **3. Heavy checks use the runway** | A shared queue with a time limit, so a hung test stops itself and says so. |
| **4. Check your own landings hardest** | A fix that passes alone can break its neighbours. CI comes before the next landing. |
| **5. Decide routine, ask the rest** | Naming and test approach get decided. Law, money, accounts, publishing and deletion go to you, as options. |
| **6. Waiting is not reporting** | Every wake-up costs tokens. Sessions report results, not "still waiting". |

## What's in the box

<p align="center">
  <img src="docs/img/status.svg" alt="The gate refuses a fourth area and tower-status shows the fleet on one screen" width="88%">
  <br><sub>Output from a demo repository, shortened to fit.</sub>
</p>

| Script | What it does |
|---|---|
| `tower-gate.sh` | Decides who may fly. A fourth area gets refused until one lands. |
| `runway.sh` | Runs heavy checks first come, first served, with a time limit that also stops child processes. `--priority` lets a fix for a red main overtake. |
| `tower-status.sh` | Runways, queue, every worktree and CI, on one screen. |
| `land-check.sh` | Before landing: commits, deletions, shared infrastructure, possible secrets, and a merge simulation. |
| `tower-overlap.sh` | Which branches touch the same files, so they don't fly together. |
| `tower-init.sh` | Sets up shared state in `.git/watchtower`: visible to all worktrees, impossible to commit. |

And for the agent itself:

- **[Takeover](references/takeover.md):** adopt yesterday's stalled worktrees and sessions, including a `main` that is already red.
- **[Landing](references/landing.md):** when a rebase is yours and when it goes back to the session, and how several candidates share one full test run.
- **Shift change:** a very long orchestrator conversation pays for its history on every message, so a fresh one takes over from a handoff file.
- **Budget:** a stop line agreed with you. Near the limit, landing goes before building.

## The traps it knows about

All of these really happened. [The full list](references/failure-modes.md) has what each looks like and what to do.

> **Counters that merge wrong.** Two branches change `tables: 84` to `tables: 88`. Git sees the same edit and merges it without a word. The truth was 92.

> **The lock file that lost Linux.** A local install dropped entries for other platforms. Green on the laptop, `npm ci` fails in CI.

> **The hotfix that passed alone.** It fixed the hanging suite and broke every suite after it, which only showed in a full run.

> **Failures that move around.** Different tests fail each run, each green alone. One suite left a job behind, and 30 minutes later a timer revived it inside someone else's test.

> **The pre-check that checked nothing.** A clever shell loop reported "no conflicts". It never split its list. The real cherry-pick had twelve.

## Try it

> I have twelve stalled worktrees from yesterday and CI on main is red. Take over and consolidate them.

> Parallel agents keep breaking main and burning my limit. Fix how we run them.

> Limits are back. Resume the sessions that stopped, most important first.

The scripts also work without any agent:

```bash
scripts/tower-init.sh
scripts/tower-gate.sh add search billing
scripts/runway.sh full-tests npm test
scripts/tower-status.sh
scripts/land-check.sh feature/search
```

<details>
<summary><b>Exit codes and settings</b></summary>

| Exit from `runway.sh` | Meaning |
|---|---|
| 75 | Parked, not your turn. Commit and wait. |
| 124 | Hung past the time limit. Find the cause. |
| 143 | Aborted. Run it again. |
| other | The command's own result |

| Setting | Default | |
|---|---|---|
| `TOWER_RUNWAYS` | 3 | Checks running at once |
| `TOWER_MAX_ACTIVE` | 3 | Areas on the gate |
| `TOWER_TIMEOUT` | 5400 | Seconds before a check counts as hung |
| `TOWER_BASE` | origin's default | Base branch |
| `TOWER_HOME` | `.git/watchtower` | State directory |

</details>

<details>
<summary><b>Which tools does it work with?</b></summary>

| | Sessions | Scripts and method |
|---|---|---|
| Claude Code desktop app | Starts, messages and hands over sessions directly. This is where it was developed. | Yes |
| Claude Code in a terminal | Subagents, or one session per tmux pane | Yes |
| Codex, Cursor and others | Use that tool's own way of running sessions. Not tested yet. | Yes |

Tests run on Linux and macOS. See [the harness notes](references/harness.md).

</details>

<details>
<summary><b>Why three?</b></summary>

Three is what worked in the run this came from, on one laptop. It's a starting point. If your checks are fast or you have more machines, raise `TOWER_MAX_ACTIVE` and `TOWER_RUNWAYS`. The thing to watch is how many candidates need another rebase after each landing.

</details>

<details>
<summary><b>Isn't this just <code>git worktree</code>?</b></summary>

Worktrees give each agent its own folder. They don't decide who runs, who lands, what to do with a hung test, or when to ask you. Watchtower is that part.

</details>

## Honest limits

- It comes from one large project and has not been benchmarked. The numbers above describe that run, not a promise.
- It doesn't replace your tests or CI. It runs them in an order you can afford.
- An agent following a skill can still make mistakes. The tower's own hotfix is on the list of traps for a reason.

## Contributing

Bring your own failure modes: if parallel agents burned you in a way that isn't [on the list](references/failure-modes.md), open an issue or a pull request. Run `bash tests/run.sh` before you do.

If Watchtower saves your main branch, a star helps others find it.

## License

[MIT](LICENSE)
