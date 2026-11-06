---
name: watchtower-setup
description: >-
  Interview the person and prepare a repository for a Watchtower shift. Use before
  the first orchestration in a project, when someone says "set up watchtower",
  "richte Watchtower ein", "bereite die Orchestrierung vor" or "interview me first",
  or when Watchtower is about to start and its brief is still empty.
---

# Watchtower setup

A shift goes wrong in its first ten minutes: unclear goal, unknown limits, no test command, two agents owning the same file. This interview prevents that. You finish with a filled brief, stored limits and a flight plan the person has agreed.

Set `WATCHTOWER_SKILL_DIR` to the Watchtower skill directory, two levels above this file.

## Rules of the interview

- **Read before you ask.** Never ask what the survey or the repository can answer. Say what you found in one line and ask only about what is open.
- **Offer choices.** Use the client's question tool when it has one. Two to four concrete options each, your recommendation first and marked, with what each one leads to. Without a question tool, write the options as a short numbered list.
- **Bundle.** At most three rounds and four questions a round. Fewer is better. Stop as soon as the plan is clear.
- **Their language, their words.** Plain words, no internal terms like gate or runway without saying what they mean.
- **Nothing happens yet.** Until the last step you only read and ask. No worktree, no install, no commit.

## 1. Survey

```bash
"$WATCHTOWER_SKILL_DIR/scripts/tower-survey.sh"
```

It reports read-only: whether this is a repository, its commits and base branch, other worktrees and branches, uncommitted work, CI, project rules, likely test and build commands, and machine capacity. Read the rules files it names.

Sort the situation, and say which one you see:

| What the survey shows | Situation |
| --- | --- |
| No repository, or no real structure | **New project** |
| A working project, few open branches | **Existing project** |
| Several worktrees, stale branches, dirty work, or a red base | **Takeover** |

If it is not clear, make that the first question. For a takeover read `references/takeover.md` now and run `tower-overlap.sh`, which shows the branches touching the same files.

Find out whether the base is green without asking: the CI result if `gh` can read it, otherwise the test command once. Report what you saw.

## 2. Ask what the survey cannot know

**Everyone, first round:**

1. **The goal:** what should be true when this is done? Offer your reading of their request as the first option. This becomes the mission.
2. **What done means:** working in the real app (recommended when people use it), tests green only, or deployed and verified?
3. **What may it do alone?** Options: work locally and show me first (recommended unless they said otherwise), push branches and open pull requests, or land and deploy within agreed limits.
4. **How much at once?** Show the capacity suggestion. Options: the suggestion, one higher tier of your own judgment, no limit.

**New project, second round:**

- Platform and stack, with your suggestion from what they already use.
- Who uses it, and what the first release must include. Ask for what it must *not* include as well.
- Hard constraints: deadline, hosting, existing accounts, compliance.
- Is there a user interface? If yes: are designs or references available, or should you propose some first?

**Existing project, second round:**

- What must not be touched: paths, public interfaces, data, other people's branches.
- Whether a user would see the change, and who decides how it looks. If they would, the design rule of the Watchtower skill applies: show a mockup of open choices before the plan is final.
- Only the commands the survey could not find.
- Only if CI exists: anything it alone can check.

**Takeover, second round:**

- Which sessions or worktrees are still alive, and who owns them.
- Which work matters most, and whether anything may be dropped. Nothing is deleted without a clear yes.
- If the base is red: fix that first, or land unrelated work meanwhile?

**Last round, only if still open:**

- A budget stop line, for example no new building past 80 % of the weekly limit.
- Decisions they want to keep, beyond law, money, accounts, publishing and deleting data.
- Where they want to watch: the side panel in Claude Code, a terminal deck, or the browser board.

## 3. Prepare

Now write, in this order, using their answers:

0. **New project only:** `git init`, a stack-appropriate `.gitignore`, then `docs/SPEC.md`, `docs/PLAN.md`, the short rules file and `filemap.md` as in `references/planning.md`, and a first commit. Nothing else works without one.
1. `tower-init.sh`, then `tower-area.sh mission "<their goal>"`.
2. `tower-capacity.sh set --flying <n>|off --runways <n>|auto`.
3. Fill `brief.md` in the state folder: rules, verification commands, what only CI checks, reserved ranges, limits and what the tower may do alone. Where something does not apply, write "none". No `<placeholder>` may stay.
4. Write the mandate into `handoff.md`, in their words.
5. For a project with installs, add `setup=<command>` to the state folder's `config`.
6. Write the flight plan as in `references/planning.md`, then run `tower-area.sh check` and fix what it finds with `tower-area.sh edit` or `remove`. For a new project the first area is the foundation. In a takeover, add existing work with `--worktree <folder> --branch <branch>`.

## 4. Confirm

Show one short summary: situation, goal, areas with their class and order, what flies first, what you may do alone, what stays with them, what you assumed. Ask whether to start, with two options: start now (recommended) or change something.

When they say start, continue with the Watchtower skill at "Flying a block". Offer the board now: in Claude Code the panel opens by itself, elsewhere run `tower-deck.sh` or `tower-board.sh --html --watch`.
