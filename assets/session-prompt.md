**Task:** <one sentence: what a user or the project can do afterwards>

**First read:** <path to brief.md>, then <the documents and code that matter for this area>.

**Worktree:** <absolute path; use it as the working directory for every shell call>. **Skill:** <absolute installed skill directory; its scripts are not the project's scripts>.

**Scope:** <what is in>. **Not in scope:** <what is out and who owns it>.

**Others nearby:** <session name and ID, what they own, what to agree with them directly>. You share the filesystem with other workers. Preserve their edits; coordinate shared contracts instead of reverting their work.

**Done means:** <acceptance checks and any reserved ranges>. Run checks appropriate to the change; expensive verification goes through `<absolute skill directory>/scripts/runway.sh`. Verify the real interface when relevant, then audit your changes. Deliver clean commits and report the branch, tested commit SHA, commands and results, known gaps, and any uncommitted files to the tower at <address>.

If the gate returns 75, stop further editing and checking, preserve your current work and wait for the tower. A timeout (124) requires investigation before retrying. If a worker tool is interrupted, explicitly clean up its owned subprocesses before declaring it stopped.

Do not land, push or deploy. Report results, not progress.
