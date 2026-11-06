# Failure modes

All of these happened in real runs. Each cost hours, or a red main branch.

## More flying than this machine carries

**Looks like:** Everyone reports "waiting for a slot". Limits drain fast while little lands. The board shows high numbers behind the base.
**Why:** Machine slots stay fixed, and each landing makes all other candidates stale. Twenty sessions are not four times faster than five. They rebase more.
**Do:** Show the human the numbers and `tower-capacity.sh`. Suggest parking down and landing before starting anything new. How many is their call.

## A hung check holds a slot

**Looks like:** A slot is busy for hours at almost no CPU. Other sessions pile up.
**Why:** A test waits forever on something. It looks exactly like a slow test.
**Do:** Look at age and CPU in `tower-status.sh` and `ps`. The runway's time limit is the backstop. Exit 124 means find the cause, not retry.

## Silently wrong counters

**Looks like:** Two candidates each change "tables: 84" to "tables: 88". Git merges them cleanly, since both made the same edit. The true value is 92. Tests fail later and far away, or worse, pass.
**Do:** After every merge, recount shared totals by hand: fixed counts in tests, version numbers, registries. Merge tools cannot see this.

## Lock files losing platform entries

**Looks like:** Everything is green locally. CI on another platform fails on install with "lock file out of sync".
**Why:** A local install can rewrite the lock file and drop entries for other platforms. A batch merge can quietly take over that version.
**Do:** Solve lock conflicts as a union of both sides. Do not commit a lock file rewritten by a plain install. Dry-run a clean install with a recent package manager before pushing.

## The hotfix that passed alone

**Looks like:** You fix a hanging suite, it passes alone, you push. CI goes red in the next suites.
**Why:** Shared test state. Your fix changed something the neighbours relied on.
**Do:** Run a test-helper change together with the suites before and after it. If you broke it, say so to the human and to sessions now working on top of it.

## Test pollution that moves around

**Looks like:** Different suites fail each run, each green alone, usually only in long runs, and sometimes only under load.
**Why:** One suite leaves state behind, such as open jobs, leases or queue items, and a timer revives it later in someone else's test.
**Do:** Stop retrying and stop patching each victim. Have one session find the source, and isolate at the boundary, for example by closing leftovers before each test file. Warn the others that this is a known cause. Several sessions will otherwise fix it three different ways at once.

## Duplicate work between sessions

**Looks like:** Two sessions, started by different people or towers, build the same step. Or a block of reserved numbers gets handed out twice.
**Do:** Reserved numbers and ownership live in one brief. Read the list of running sessions before starting one. On finding an overlap, split it explicitly and tell both.

## Rebases that undo finished work

**Looks like:** A rebase "resolves" conflicts by taking its own side, and something already landed disappears.
**Do:** After a rebase, compare the file list and read deletions. Tell the session what must survive. Never let anything revert the base.

## A false all-clear from your own tooling

**Looks like:** A pre-check says no conflicts, then a real cherry-pick has twelve. In this case a shell loop did not split its list, so it compared nothing.
**Do:** Trust the real operation in a throwaway worktree over a clever pre-check. Test your check against a pair you know conflicts.

## A tower that forgot what is done

**Looks like:** After a compaction the tower starts an area again that already landed, or re-reviews finished work.
**Why:** Conversation memory does not survive compaction, and a confident summary can be wrong.
**Do:** After any compaction read the board and `git log` first. Landed and cleared are facts on the board. The commits exist even if you no longer remember them.

## Editing a script that is running

**Looks like:** Shared scripts behave strangely after an edit, because a shell may read a running script as it goes. Or a bad edit breaks every session's queue at once.
**Do:** Write to a new file, test it, then move it over the old one atomically. Running instances keep the old file.

## Sessions chattering while they wait

**Looks like:** A stream of "still waiting" notes, each waking the tower with its whole history.
**Do:** Tell sessions to report results only. Read notes in batches. Do not answer waiting notes.

## Believing a session's report

**Looks like:** "All green", but the base moved since, or the run was on another commit.
**Do:** Read the commit message and the log. Ask on which commit it ran. Reports are claims. The log is evidence.

## The tower itself getting expensive

**Looks like:** Limits drain although little is running.
**Why:** A very long conversation pays for its history every time it wakes.
**Do:** Hand over early. See "Shift change" in the skill.
