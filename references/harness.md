# Working with your tool

The tower needs six things: start a session in its own worktree, message it, hear when it finishes, list what is running, see usage, and show the human the board. Tools name these differently. Look at what you actually have before you plan, and never assume a tool exists.

## Codex

Start with the tools exposed in the current session. Codex clients differ; a missing tool is an unavailable capability, not a reason to invent its name or work around a limit.

### In-session subagents

When the session exposes collaboration tools, use their actual schemas. Common capabilities in this environment are:

| Need | Available capability |
| --- | --- |
| Start a worker | `spawn_agent` with a scoped task; supply its absolute worktree path in the task text |
| Send context | `send_message` to an existing running worker |
| Give an idle worker more work | `followup_task`, when exposed |
| Completion | Delivered results; `wait_agent` for a pending result |
| Inventory | `list_agents` |
| Stop current work | `interrupt_agent`; interruption alone does not prove subprocesses stopped |

These are capabilities observed in this environment, not a mandatory Codex API. Use only the names and schemas actually listed by the client. The [official hosted multi-agent reference](https://developers.openai.com/api/docs/guides/responses-multi-agent) documents these collaboration primitives; a client can expose a different interface. Do not assume that Claude's `get_usage`, `start_session` or `detach_session` exists.

The client's own limit stays in force: `agents.max_concurrent_threads_per_session` excludes the primary, while a limit counting total agents includes the tower, so read how yours counts and do not subtract twice. Reduce capacity for other active agents and use serial areas if delegation is unavailable. The person's flying limit controls gate entries and runways control checks: neither creates agent capacity or stops a worker from editing. If they want more than the client allows, tell them which setting it is. Do not change it yourself.

**Classes:** `tower-install.sh codex` installs `~/.codex/agents/tower-*.toml`. They keep the user's model and set effort only. Spawn by name when the tool lists them.

**Board:** Start `python3 "$WATCHTOWER_SKILL_DIR/scripts/tower-codex.py" board` from the target repository. Open its printed loopback URL in the desktop app's built-in browser when that capability is available. The board works in an ordinary browser too. Start it before the work you want to observe and stop it at the end of the shift. Mirror the block in the plan tool when exposed, and include `tower-board.sh --plain` in a progress message at real milestones.

**Live activity setup:** The user opts in with `tower-install.sh codex-live` and reviews the new entries in **Settings → Hooks** (`/hooks` in the CLI). Do not auto-trust or change hook permissions. The hooks record lifecycle metadata only in repositories where the local board has been started. A worker's normal `tower-area.sh step` associates its reported Codex thread with its assigned worktree. Session state and flight-plan state are separate: an idle subagent has finished a turn, and the worktree still needs its usual delivery and review.

Watchtower's progress commands need write access to its shared state. If the workspace sandbox protects the common Git directory, use an absolute `TOWER_HOME` in a user-approved writable directory and pass it to the Codex runtime and board process so the hooks and workers see the same state.

Subagents share the filesystem. Create each worktree explicitly before dispatching:

```bash
"$WATCHTOWER_SKILL_DIR/scripts/tower-area.sh" launch search
```

In the task text give the resolved absolute worktree path and require shell calls to set that working directory. Do not add a nonexistent `workdir` argument to an agent-spawn tool. Specify file or module ownership, acceptance checks, the shared brief, and the absolute skill path. State that other workers share the repository: preserve their edits and coordinate shared contracts. Use unique worktree folder names because the scripts identify worktrees by basename.

Use a worker role for implementation and a read-only explorer for a narrow repository question when those roles are exposed. Use an independent evaluator with minimal raw context for behavioral tests. Preserve the user's model and execution preferences; do not override models or permissions to make a dispatch work.

On completion, verify the worker's branch tip, working tree and logs yourself. A report is not proof of a commit or authorization. Give follow-up edits to the owning worker; avoid repeatedly creating replacements. Follow required user-facing progress updates while waiting, without repeatedly polling a parked worker.

### Standalone Codex tasks and missing capabilities

Tools that create or fork UI tasks are not interchangeable with in-session subagents. Use standalone-task creation only when the user explicitly requests a new task and the tool's contract allows it. For ordinary area dispatch use available subagents, or proceed sequentially. Never change Codex settings, enable permissions or connect accounts as a side effect of adopting Watchtower.

If no usage API exists, record usage as unavailable and follow any supplied task budget. If there is no detach or resume capability, keep session IDs, worktree paths, exact SHAs and remaining work in `handoff.md`. Continue the current conversation after compaction; start a replacement only within the user's mandate.

If the user asks for local work, omit pushes and remote CI triggers. Verify locally and report CI-dependent checks as pending. A local integration branch is a reviewable result even when publication has not been authorized.

## Claude Code desktop app

Tool names change between versions. Check what your session actually lists.

| Need | Tool |
| --- | --- |
| Start a session | `start_session` with `use_worktree: true`, a short `name`, a `model`, a `source_branch` when it builds on another branch. Run `tower-area.sh launch <id> --native` first; the worker runs `bind` |
| Start a subagent | `tower-area.sh launch <id>`, then the Agent tool with `subagent_type` = the class as listed, `description` = the area id, and the absolute worktree path in the brief. No `isolation`, since the worktree exists. A subagent reports back when it finishes; with no way to message it, a return means a new one with the defects in its brief |
| Message | `SendMessage` with the session ID |
| Hear when done | Notes arrive by themselves for sessions you started; `notify_when_idle` for others |
| List | `list_sessions` with `linked: true` |
| Usage | `get_usage` |
| Hand over | `detach_session`, so old sessions stop waking the old tower |

A tower works in the base checkout because it lands there, so start a replacement with `use_worktree: false`.

**Board:** the plugin draws a bar above the prompt and opens the Fleet panel beside the chat by itself once a plan exists. `/tower-board` toggles it, and the `show_board` tool opens it and reports what it can see. It lists subagents that fly no area, and writes each worker's context fill, tokens and estimated cost to its worktree block. Costs are list prices times reported tokens, so they are estimates. Only one plugin can draw that row at a time: while another plugin's bar is active, for example from a workflow with its own subagents, Watchtower's stays hidden until that one is dismissed.

## Claude Code in a terminal

Use the Agent tool with `isolation: "worktree"` for work that returns in this conversation. For long-lived independent sessions, use `tower-area.sh launch`, fill in `assets/session-prompt.md`, and start one interactive `claude` per terminal or tmux pane. In fullscreen rendering the Fleet panel docks beside the transcript; otherwise `tower-deck.sh` opens the live deck in a pane or window. `claude -p` also works for a job with one result, but you cannot talk to it afterwards.

```bash
"$WATCHTOWER_SKILL_DIR/scripts/tower-area.sh" launch search
tmux new-window -c ../project-search -n search claude
```

Terminal sessions cannot reach each other without a shared channel. Use the `status/` folder that `tower-init.sh` creates in the tower state directory: each session writes `status/<name>.md` when it has a result, and resuming a stopped session works with `claude --continue` in its worktree.

## Other agents (Cursor and others)

The scripts are plain bash and git, so they work anywhere. Point `AGENTS.md` or the equivalent at the brief. Use whichever way that tool has to run separate sessions, one worktree each. The board's terminal and browser views work the same.

## No background sessions at all

You can still run the method alone: work through one area per worktree in sequence, and let the human start parallel windows. The gate, runway and landing rules still pay off, since slots and rebases do not depend on who is typing.

## When a session cannot be reached

Some tools limit how many messages sessions may receive per human message, or pause sessions that ran out of usage. Do not try to get around a limit. Prioritise who gets the message, and tell the human briefly what you need from them.

## Environment gaps

- Without `setsid` (default macOS), `runway.sh` falls back to perl, then python3.
- `land-check.sh` needs git 2.38 or newer for the merge simulation, and works without it.
- The board shows CI only if `gh` is installed and logged in, from a note refreshed at most once a minute.
- If the state directory must be shared beyond one clone, set `TOWER_HOME`.
