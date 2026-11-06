**Task:** <one sentence: what a user or the project can do afterwards>

**First read:** <path to brief.md>, then <the documents and code that matter for this area>.

**Area:** <id>. **Class:** <class>. **Worktree:** <absolute path; use it as the working directory for every shell call>. **Skill:** <absolute installed skill directory; its scripts are not the project's scripts>. **Report file:** <state folder>/reports/<id>.md.

**Scope:** <what is in>. **Not in scope:** <what is out and who owns it>.

**Others nearby:** <session name and ID, what they own, what to agree with them directly>. You share the filesystem with other workers. Preserve their edits; coordinate shared contracts instead of reverting their work.

**Done means:** <acceptance checks and any reserved ranges>. Write the failing test first for fixes and run checks appropriate to the change; expensive verification goes through `<absolute skill directory>/scripts/runway.sh`. Verify the real interface when relevant, then audit your changes.

**Board:** after reading this run `<skill>/scripts/tower-area.sh step 0 <total steps> "<first step>"`, and again as each step finishes. If your client made your worktree, run `tower-area.sh bind <id>` first.

**Deliver:** clean commits, the full report in the report file, then `<skill>/scripts/tower-area.sh deliver DONE|CONCERNS|BLOCKED|NEEDS_CONTEXT "<one line>"`. Tell the tower at <address> only: status, branch, tested commit, one line of results, open questions, report path.

If the gate returns 75, stop further editing and checking, preserve your current work and wait for the tower. A timeout (124) requires investigation before retrying. If a worker tool is interrupted, explicitly clean up its owned subprocesses before declaring it stopped.

Do not land, push, deploy or start subagents. Message the tower with results only.
