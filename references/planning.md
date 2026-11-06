# Writing the flight plan

The plan lives on the board, not in your head and not in the conversation. It survives compaction, every worktree sees it, and the human reads it live.

## Slicing

An area is one piece a stranger could finish from a brief, in one worktree, with its own way to verify it. Slice so areas touch different files. Put what unblocks others first, what is nearly done before what is new, and an end-to-end pilot and privacy or lifecycle work last, because they need to see everything else.

Small same-shape edits across many files are one area, not twenty. Twenty workers each making one rename costs twenty contexts and twenty reviews.

Split investigation from implementation when the result could change the plan: a `scout` finds out and writes a precise brief, a `freighter` or `liner` carries it out.

## Classes

Pick the cheapest class that gets it right the first time. The two axes are the ceiling of judgment (model) and how much the worker checks itself (effort).

| Class | Claude Code | Codex | For |
| --- | --- | --- | --- |
| `ace` | Fable, high | your model, xhigh | Hardest problems: subtle algorithms, concurrency, many interacting states, bugs that survived a scout. A reserve, not a default. |
| `scout` | Opus, xhigh | your model, xhigh | Finding out: unfamiliar or messy code, unclear root cause, anything where a wrong first approach is expensive. |
| `freighter` | Opus, high | your model, high | Carrying it exactly: the approach is clear but delicate. Multi-file refactors, invariants, migrations. |
| `liner` | Opus, medium | your model, medium | Standard features and fixes with a known cause and clear requirements. |
| `prop` | Sonnet, low | your model, low | Nothing left to figure out: renames, config, boilerplate, complete code in the brief. |

Unsure between two? Take the higher, except `ace`, which needs to clearly qualify. Scout or freighter is about the kind of difficulty: insight needed means scout, thoroughness needed means freighter. A worker that reports BLOCKED on a task beyond it goes up a class; do not retry it unchanged.

Agent types are `tower-<class>`, or `watchtower:tower-<class>` where the client lists plugin agents with a prefix. Use what your client actually lists. Without these agents, say which class you meant and use the client's nearest option; never change the user's settings to get one.

## The plan

```bash
tower-area.sh mission "Checkout rebuild for launch"
tower-area.sh add api  "Order API"     --class scout  --owns "src/api"
tower-area.sh add cart "Cart screen"   --class liner  --owns "src/cart" --after api
tower-area.sh add docs "Runbook"       --class prop   --owns "docs" --after cart
tower-area.sh check
```

Change it with `tower-area.sh edit <id> --owns ...` or `remove <id>` until the area has flown. `--owns` is what makes the preflight useful. `check` fails on placeholder titles, unknown dependencies, cycles, and two areas that own the same path without an order between them. An area that owns nothing gets a warning, because nothing can be checked for it.

Before launching, also read what `check` cannot see: does any task contradict another, does one consume an interface another has not agreed yet? Shared contracts and anything numbered go in `brief.md` before anyone writes them. Decide what you find, and record it with `tower-area.sh rule`.

## A new project

No delegation until the human has agreed the spec. Workers cannot see this conversation, so it has to live in files:

1. `git init` if needed, with a stack-appropriate `.gitignore`.
2. Ask in one batch what cannot be derived: platform and stack, target users, the first release's boundary, non-goals, hard constraints.
3. `docs/SPEC.md`: goals, non-goals, stack with versions, modules and their responsibilities, data model, integrations, key user flows, what done means.
4. `docs/PLAN.md`: the areas, each a paragraph, with class, dependencies and verification. Mirror it on the board with `tower-area.sh add`.
5. A root rules file (`CLAUDE.md` or `AGENTS.md`), as short as possible, 60 lines at most: exact build, test, run and lint commands, the few conventions an agent would otherwise get wrong, pointers to the docs. It loads into every worker, so every line costs that many times over.
6. `filemap.md`: one flat line per directory and significant file, `path: what lives here`. Briefs tell workers to keep it current.
7. If there is a user interface, do the design pass before approval: the main screens as something the human can react to.
8. Show the summary and wait for approval. A vague "sounds fine" on a partial picture is not approval.

Area one is always the foundation: structure, dependencies, test and build commands, CI, shared contracts. Nothing flies beside it. Land it, then fan out by dependency order.
