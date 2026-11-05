# Working with your tool

The tower needs five things: start a session in its own worktree, message it, hear when it finishes, list what is running, and see usage. Tools name these differently. Look at what you actually have before you plan, and never assume a tool exists.

## Claude Code desktop app

Tool names change between versions. Check what your session actually lists.

| Need | Tool |
| --- | --- |
| Start a session | `start_session` with `use_worktree: true`, a short `name`, a `source_branch` when it builds on another branch |
| Message | `SendMessage` with the session ID |
| Hear when done | Notes arrive by themselves for sessions you started; `notify_when_idle` for others |
| List | `list_sessions` with `linked: true` |
| Usage | `get_usage` |
| Hand over | `detach_session`, so old sessions stop waking the old tower |

A tower works in the base checkout because it lands there, so start a replacement with `use_worktree: false`.

## Claude Code in a terminal

Use the Agent tool with `isolation: "worktree"` for work that returns in this conversation. For long-lived independent sessions, create the worktree yourself, fill in `assets/session-prompt.md`, and start one interactive `claude` per terminal or tmux pane. `claude -p` also works for a job with one result, but you cannot talk to it afterwards.

```bash
git worktree add -b area/search ../search main
tmux new-window -c ../search -n search claude
```

Terminal sessions cannot reach each other without a shared channel. Use the `status/` folder that `tower-init.sh` creates in the tower state directory: each session writes `status/<name>.md` when it has a result, and resuming a stopped session works with `claude --continue` in its worktree.

## Other agents (Codex, Cursor and others)

The scripts are plain bash and git, so they work anywhere. Point `AGENTS.md` or the equivalent at the brief. Use whichever way that tool has to run separate sessions, one worktree each.

## No background sessions at all

You can still run the method alone: work through one area per worktree in sequence, and let the human start parallel windows. The gate, runway and landing rules still pay off, since slots and rebases do not depend on who is typing.

## When a session cannot be reached

Some tools limit how many messages sessions may receive per human message, or pause sessions that ran out of usage. Do not try to get around a limit. Prioritise who gets the message, and tell the human briefly what you need from them.

## Environment gaps

- Without `setsid` (default macOS), `runway.sh` falls back to perl, then python3.
- `land-check.sh` needs git 2.38 or newer for the merge simulation, and works without it.
- `tower-status.sh` shows CI only if `gh` is installed and logged in.
- If the state directory must be shared beyond one clone, set `TOWER_HOME`.
