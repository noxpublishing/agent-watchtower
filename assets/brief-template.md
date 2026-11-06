# Fleet brief: <project>

Every session reads this first. Keep it short and current.

## Rules

- You work on a candidate in your own worktree. Only the tower lands on `<base>`.
- Worktree: `<absolute path>`. Owned files/modules: `<scope>`. Others share the filesystem: preserve their edits and coordinate shared interfaces.
- Do not push, deploy, or touch real providers, accounts, payments or production.
- Never revert what is on `<base>`. After a rebase, check that nothing was undone.
- Write the failing test first when fixing a bug, and run checks appropriate to the change. Do not weaken an assertion to get green.
- Message the tower with results only. Progress goes to the board. No "still waiting" messages: every wake-up costs tokens.

## Verification

Run heavy checks only through the runway, so the machine is not overloaded and a hang gets stopped:

`"<absolute skill directory>/scripts/runway.sh" <label> <command>`

| Exit | Meaning | Do |
| --- | --- | --- |
| 75 | Parked, not your turn | Commit your state, end your turn, wait for the tower |
| 124 | Hung past the time limit | Find the cause, do not simply retry |
| 2 | The queue itself is stuck, for example a runway without an owner | Read the message and tell the tower |
| 143 | Aborted by someone | Confirm cleanup and the reason before retrying |
| 137 | Killed, often out of memory | Check before running again |
| other | Your command's result | Read it |

Commands for this project:

- Full tests: `<command>`
- Filtered tests: `<command>`
- Type check: `<command>`
- Builds: `<command>`
- UI check, if the area has a UI: `<how to run it>`
- Only CI can check: `<containers, other platforms, or nothing>`. Say so in your report instead of claiming it passed.

## Reserved ranges

Anything numbered or shared gets a reserved range here, before anyone writes it.

| Area | Reserved |
| --- | --- |
| <area> | <for example migrations 0200-0209> |

## Execution limits

- Available agent slots: `<total, including tower and any other active agents>`.
- Active worker limit: `<what the person chose, or none; within remaining agent capacity>`.
- Concurrent checks: `<runways the person chose, distinct from agent slots>`.
- Budget/usage: `<user-supplied stop line; unavailable metrics marked unavailable>`.
- Tower authorization: `<local integration, remote push and deployment separately>`.

## Delivering a candidate

Commit message states: what it does, what was fixed on the way, what was verified **on which commit**, what was not verified. Write the full report to your report path, then run `"<absolute skill directory>/scripts/tower-area.sh" deliver DONE|CONCERNS|BLOCKED|NEEDS_CONTEXT "<one line>"`. Send the tower only: status, branch, commit, one line of results, open questions, report path.

## Progress

`"<absolute skill directory>/scripts/tower-area.sh" step <done> <total> "<current step>"`. It draws the board, wakes nobody and never fails your work.

## Asking

Routine questions: pick the recommended option and name it in your report. Law, money, publishing, accounts, deleting data, or user-visible product choices: ask the tower with two to four options and your recommendation first, and carry on with what does not depend on the answer.
