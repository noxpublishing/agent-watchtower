<p align="center">
  <img src="docs/img/hero.svg" alt="Watchtower: a lit tower watches agents land on main while the others wait parked" width="100%">
</p>

<p align="center">
  <a href="https://github.com/noxpublishing/agent-watchtower/actions/workflows/test.yml"><img src="https://github.com/noxpublishing/agent-watchtower/actions/workflows/test.yml/badge.svg" alt="Tests"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-3DDC97" alt="MIT license"></a>
  <img src="https://img.shields.io/badge/Claude%20Code-skill-FFB454" alt="Claude Code skill">
  <img src="https://img.shields.io/badge/Codex-skill-3DDC97" alt="Codex skill">
  <img src="https://img.shields.io/badge/needs-bash%20%2B%20git-7C8AA2" alt="Needs bash and git">
</p>

<p align="center">
  <b>One session becomes the tower. As many agents fly as you choose. Finished work lands on main, one at a time, and you watch all of it live.</b>
</p>

```bash
git clone https://github.com/noxpublishing/agent-watchtower ~/.claude/skills/watchtower
```

That one folder is the skill, the flight board and the worker classes for Claude Code. For Codex, or both:

```bash
git clone https://github.com/noxpublishing/agent-watchtower ~/agent-watchtower
```

```bash
~/agent-watchtower/scripts/tower-install.sh codex
```

Use `all` instead of `codex` for both. Installing links, so `git pull` updates it. In the next Codex turn, invoke `$watchtower`. See [client capabilities](references/harness.md#codex) and [how to evaluate it](references/evaluation.md).

<p align="center">
  <img src="docs/img/board.png" alt="The board: cost, tokens and time, a bar with one slot per worktree, then each worktree as a block with its progress and its agent, most urgent first" width="100%">
  <br><sub>The browser view, from a demo repository. Claude Code shows the same worktrees in its side panel.</sub>
</p>

## Start it

Install once, open your agent in any repository or empty folder, and say what you want. Mention *watchtower*, or type `/watchtower` if your tool has slash commands.

<table>
<tr><th width="50%">Starting something new</th><th width="50%">Already have a project</th></tr>
<tr>
<td>

> Use watchtower. I want to build `<your idea or plan>`. Set up the foundation first, split the rest into areas, and show me the order before you start.

The tower has one session lay the foundation: structure, test command, CI and shared contracts. Parallel agents on an empty repository would each invent their own. Then the areas fly in blocks.

</td>
<td>

> Use watchtower on this repo. Goal: `<what should be true at the end>`. Look at what's here, including open branches, and propose the order.

The tower reads your rules, CI and branches, backs up what isn't merged, and asks only what is really yours to decide. Then it starts the first block.

</td>
</tr>
</table>

### What it's for

Anything too big for one agent that can be split and verified:

| You have | Say something like |
|---|---|
| **A product idea or spec** | *Build this spec with watchtower. Foundation first, then the areas in blocks.* |
| **A big feature across the stack** | *Add `<feature>` across API, app and docs. You orchestrate.* |
| **A backlog** | *Work through these 15 issues. Group the ones that touch the same files.* |
| **A migration or large refactor** | *Move all modules from `<old>` to `<new>`, in batches, with main green the whole time.* |
| **Quality work in many places** | *Raise test coverage in the weakest modules, one area per agent.* |
| **Stalled agents and old branches** | *Take over these worktrees and get what's worth keeping onto main.* |
| **A red main and a pile of work** | *CI is red and six branches are waiting. Sort this out.* |
| **Sessions stopped by a limit** | *Limits are back. Resume the stopped sessions, most important first.* |
| **Limits draining too fast** | *We're burning through usage. Fix how the agents run.* |

Not worth it for one small change a single agent can finish. Just ask that agent.

## Twenty agents are not twenty times faster

Starting a pile of agents feels great for about an hour. Then they queue for the same machine, every landing makes the others stale, a hung test holds a slot all afternoon, `main` turns red, and your usage limit is gone with half the work still on branches.

Watchtower came out of exactly that: one real project, more than twenty parallel sessions, and at one point 16 checks waiting on 3 slots for over an hour. How many agents your machine and your limits carry is yours to decide. What has to be right is who may run, who lands, and whether you can see it.

<p align="center">
  <img src="docs/img/before-after.svg" alt="Everyone at once with nobody in charge, compared with a tower in charge" width="100%">
</p>

## How it works

<p align="center">
  <img src="docs/img/flow.svg" alt="Parked, flying, runway, candidate, tower, main. Hung checks go back. Decisions that are yours come to you. After each landing the next session is called." width="100%">
</p>

## See the whole fleet

Every view reads the same state, and the scripts write that state as a side effect. Workers report progress with one silent command that wakes nobody, so watching costs no tokens and the board cannot drift from what happened.

| Where | What you get |
|---|---|
| **Claude Code** | A bar above the prompt and the Fleet panel beside the chat, with cost, tokens and time, and every worktree as a block holding its agents. It opens by itself once there is a plan. `/tower-board` toggles it. |
| **Any terminal, Codex** | `tower-deck.sh` opens a full-screen live deck: a tmux pane on the right, or a window of its own on macOS. Keys: `q` quit, `l` landed, `c` compact, `j`/`k` scroll. |
| **Any browser** | `tower-board.sh --html --watch` keeps a live page current, with no server. |
| **The tower itself** | `tower-board.sh --plain`, short on purpose, because it pays for every line. |

The fleet bar has one slot per area, so you read the whole plan from one line. Every worker has a face: the body shape is its class, and what it does is its state. A `liner` types, a `scout` searches, a `freighter` lifts, a `prop` hovers. Paused workers sleep, a worker that needs you waves, and landed ones cheer. In a terminal they are small text faces like `{••}`. A worktree block shows its branch, ahead and behind, uncommitted files, steps, a running check, and each agent with model, context fill, tokens and estimated cost. Worktrees nobody planned show up too, which is what a takeover needs.

## The seven laws

1. **You set the fleet size.** No number is built in. `tower-capacity.sh` reads your machine and suggests one; you pick, or pick no limit.
2. **Only the tower lands.** One writer on the base branch means one place that knows its state.
3. **Heavy checks use the runway.** A shared queue with a time limit, so a hung test stops itself and says so.
4. **Reports are claims, evidence decides.** The tower reads the diff and the log. "Landed" on the board means the commit is on the base, because the script checks.
5. **Check your own landings hardest.** A fix that passes alone can break its neighbours. CI comes before the next landing.
6. **Decide routine, record it, ask the rest.** Naming and test approach get decided and logged. Law, money, accounts, publishing and deletion go to you, as options.
7. **Waiting is not reporting.** Every wake-up costs tokens. Progress goes to the board, messages carry results.

## Start with an interview

Say *set up watchtower*. `watchtower-setup` reads the repository first, works out whether this is a new project, an existing one or a takeover, and asks only what it could not find: the goal, what done means, what it may do alone, and how many should fly. Then it fills the brief and writes a flight plan you confirm before anything starts.

## The right worker for each area

Each area gets the cheapest class that should get it right the first time. On Claude Code a class sets model and effort; on Codex it keeps your model and sets effort.

| Class | Claude Code | For |
|---|---|---|
| `ace` | Fable, high | The hardest problems. A reserve, not a default. |
| `scout` | Opus, xhigh | Finding out: unfamiliar code, unclear root cause. |
| `freighter` | Opus, high | Carrying it exactly: delicate multi-file work, migrations. |
| `liner` | Opus, medium | Standard features and fixes with clear requirements. |
| `prop` | Sonnet, low | Nothing left to figure out: renames, config, boilerplate. |

A separate read-only `tower-inspector` reads a candidate cold before it lands, so the tower's own context stays small. Design stays with the tower: workers never invent what a user will see.

## What's in the box

| Script | What it does |
|---|---|
| `tower-capacity.sh` | Reads cores, memory and load, suggests numbers, stores your choice per repository. |
| `tower-area.sh` | The flight plan. Preflight for ownership clashes, dependency cycles and placeholders; launch with worktree and branch; `step` and `deliver` for workers; a landing that needs evidence; a log of the tower's rulings. |
| `tower-board.sh` | The fleet at a glance: terminal, live page, plain text or JSON. |
| `tower-deck.sh` | Opens the live board beside your agents: a tmux pane or a window of its own. |
| `tower-survey.sh` | What a repository can tell before anyone asks. Changes nothing. |
| `tower-gate.sh` | Who may fly. Refuses past a limit only if you set one. |
| `runway.sh` | Runs heavy checks first come, first served, with a time limit that also stops child processes. `--priority` lets a fix for a red main overtake. |
| `land-check.sh` | Before landing: commits, deletions, shared infrastructure, possible secrets, and a merge simulation. |
| `tower-overlap.sh` | Which branches touch the same files, so they don't fly together. |
| `tower-init.sh` | Sets up shared state in `.git/watchtower`: visible to all worktrees, impossible to commit. |
| `tower-install.sh` | Links the skill and writes the Codex worker classes. |

And for the agent itself:

- **[Planning](references/planning.md):** slicing, classes, a preflight before anything flies, and specs in files for a new project.
- **[Review](references/review.md):** what counts as proof, when a cold reader takes over, and when to stop returning work.
- **[Takeover](references/takeover.md):** adopt yesterday's stalled worktrees and sessions, including a `main` that is already red.
- **[Landing](references/landing.md):** when a rebase is yours and when it goes back to the session, and how several candidates share one full test run.
- **Shift change:** a very long orchestrator conversation pays for its history on every message, so a fresh one takes over from a handoff file, and after a compaction the board says what is already done.
- **Budget:** a stop line agreed with you. Near the limit, landing goes before building.

## The traps it knows about

All of these really happened. [The full list](references/failure-modes.md) has what each looks like and what to do.

> **Counters that merge wrong.** Two branches change `tables: 84` to `tables: 88`. Git sees the same edit and merges it without a word. The truth was 92.

> **The lock file that lost Linux.** A local install dropped entries for other platforms. Green on the laptop, `npm ci` fails in CI.

> **The hotfix that passed alone.** It fixed the hanging suite and broke every suite after it, which only showed in a full run.

> **Failures that move around.** Different tests fail each run, each green alone. One suite left a job behind, and 30 minutes later a timer revived it inside someone else's test.

> **The pre-check that checked nothing.** A clever shell loop reported "no conflicts". It never split its list. The real cherry-pick had twelve.

## The scripts on their own

They work without any agent, in any git repository:

```bash
scripts/tower-init.sh
scripts/tower-capacity.sh
scripts/tower-area.sh add search "Product search" --owns src/search
scripts/tower-area.sh launch search
scripts/runway.sh full-tests npm test
scripts/tower-board.sh --watch
scripts/land-check.sh area/search
```

<details>
<summary><b>Exit codes and settings</b></summary>

| Exit from `runway.sh` | Meaning |
|---|---|
| 75 | Parked, not your turn. Commit and wait. |
| 124 | Hung past the time limit. Find the cause. |
| 143 | Aborted. Run it again. |
| 2 | Usage error, or a runway without an owner. Inspect it. |
| other | The command's own result |

| Setting | Default | |
|---|---|---|
| `TOWER_RUNWAYS` | one per four cores | Checks running at once. Better: `tower-capacity.sh set --runways <n>` |
| `TOWER_MAX_ACTIVE` | no limit | Areas on the gate. Better: `tower-capacity.sh set --flying <n>` |
| `TOWER_WORKTREES` | next to the repository | Where `launch` creates worktrees |
| `TOWER_LANG` | system language | `de` or `en` for the panel and the deck |
| `TOWER_TIMEOUT` | 5400 | Seconds before a check counts as hung |
| `TOWER_KILL_GRACE` | 20 | Seconds between TERM and KILL before releasing a check's slot |
| `TOWER_BASE` | origin's default | Base branch |
| `TOWER_HOME` | `.git/watchtower` | State directory |

</details>

<details>
<summary><b>Which tools does it work with?</b></summary>

| | Sessions | Scripts and method |
|---|---|---|
| Claude Code desktop app | Starts, messages and hands over sessions directly, with bar and side panel. This is where it was developed. | Yes |
| Claude Code in a terminal | Subagents, or one session per tmux pane. The panel docks beside the transcript in fullscreen rendering. | Yes |
| Codex | Explicit worktree dispatch, worker classes, a live page or terminal board, local-only integration, and handoff when usage/detach APIs are absent. See [evaluation scope](references/evaluation.md). | Yes |
| Cursor and others | Use that tool's own way of running sessions. Agent behavior not tested. | Yes |

Tests run on Linux and macOS. See [the harness notes](references/harness.md).

</details>

<details>
<summary><b>How many should I fly?</b></summary>

As many as your machine and your limits carry. `tower-capacity.sh` gives a starting point from your cores and memory, and you can set any number or none. The number to watch is how many candidates need another rebase after each landing: when that climbs, more agents have stopped making you faster. Your client's own agent limit still applies; the tower names it rather than working around it.

</details>

<details>
<summary><b>Isn't this just <code>git worktree</code>?</b></summary>

Worktrees give each agent its own folder. They don't decide who runs, who lands, what to do with a hung test, or when to ask you, and they don't show you any of it. Watchtower is that part.

</details>

## Honest limits

- It comes from one large project and has not been benchmarked. The numbers above describe that run, not a promise.
- The side panel uses Claude Code's early-access plugin hooks, which can change between releases. The terminal and browser boards do not depend on them.
- Codex and other clients have no drawing surface of their own, so the board lives beside them, not inside. Usage shows only where a client reports it.
- The gate and the worker classes depend on the agent following the brief. A worker that ignores them is not physically stopped from editing.
- It doesn't replace your tests or CI. It runs them in an order you can afford.
- An agent following a skill can still make mistakes. The tower's own hotfix is on the list of traps for a reason.
- An orphaned gate lock or runway directory without an owner PID fails with exit 2 and an inspection hint. It is not deleted automatically. Process cleanup covers the launched process group; a command that deliberately creates a separate session can escape it.

## Contributing

Bring your own failure modes: if parallel agents burned you in a way that isn't [on the list](references/failure-modes.md), open an issue or a pull request. Run `bash tests/run.sh` before you do, and `claude plugin test .` if you touch the plugin.

If Watchtower saves your main branch, a star helps others find it.

## License

[MIT](LICENSE)
