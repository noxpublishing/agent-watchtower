# Fleet brief: <project>

Every session reads this first. Keep it short and current.

## Rules

- You work on a candidate in your own worktree. Only the tower lands on `<base>`.
- Do not push, deploy, or touch real providers, accounts, payments or production.
- Never revert what is on `<base>`. After a rebase, check that nothing was undone.
- Write the failing test first when fixing a bug. Do not weaken an assertion to get green.
- Report results, not progress. No "still waiting" messages: every wake-up costs tokens.

## Verification

Run heavy checks only through the runway, so the machine is not overloaded and a hang gets stopped:

`<skill>/scripts/runway.sh <label> <command>`

| Exit | Meaning | Do |
| --- | --- | --- |
| 75 | Parked, not your turn | Commit your state, end your turn, wait for the tower |
| 124 | Hung past the time limit | Find the cause, do not simply retry |
| 143 | Aborted by someone | Run it again |
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

## Delivering a candidate

Commit message states: what it does, what was fixed on the way, what was verified **on which commit**, what was not verified. Then send the tower: branch, commit, base, result, open questions.

## Asking

Routine questions: pick the recommended option and name it in your report. Law, money, publishing, accounts, deleting data, or user-visible product choices: ask the tower with two to four options and your recommendation first, and carry on with what does not depend on the answer.
