# Handoff: watchtower for <project>

Updated: <date>. Keep this current during the shift, so a crash or limit stop loses nothing.

## Mandate

<What the human asked, in their words. What you may decide alone. What goes to them. Their language and how they like reports.>

## Rules and limits

- Active areas at once: <what the person chose with tower-capacity.sh, within client capacity after reserving the tower>
- Stop line: <user-supplied limit; mark usage unavailable if the client cannot measure it>
- Allowed without asking: <existing authorization for local integration, push and deployment separately>
- Never: <deploy, real providers, ...>

## Flight plan

The plan and each area's state are on the board: `tower-board.sh --plain`. Trust it and `git log` over any memory. Rulings so far: `tower-area.sh rulings`.

Order constraints the plan does not show: <...>.

## Sessions

| Name | ID | Worktree | State |
| --- | --- | --- | --- |
| <name> | <id> | <folder> | <flying, parked at commit, landed> |

Client capabilities: <available spawn/message/wait/inventory tools; missing resume, usage or detach capabilities>. Record exact branch tips and tested SHAs with the sessions.

## Base branch and CI

<Commit, CI state, what is unconfirmed.>

## Decisions already made

<So that nobody asks again.>

## Waiting on the human

<Questions, with the recommendation.>

## Field notes for this project

<Commands, traps, flaky tests with what is known and unknown.>
