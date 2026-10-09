---
name: review-loop
description: Get the uncommitted work reviewed by the other coding agent, fix its must-fix findings and repeat while the findings keep falling, then commit. Use when the user asks for a review loop, or to have the work reviewed and fixed without supervision.
---

Run a build-and-review loop on the uncommitted work in this checkout, without asking the user anything until the end. You are the builder. The reviewer is the other coding agent: Codex if you are Claude Code, Claude Code if you are Codex. Where a command below says `<codex|claude>`, pass `codex` if you are Claude Code and `claude` if you are Codex.

The user asking for this skill is permission to commit when the loop ends clean, even if the task said earlier not to commit. It is never permission to push.

`${CLAUDE_SKILL_DIR}` in the commands below stands for this skill's folder, the one that holds this file. Run every command from the repository root.

## Before the first round

1. Run the project's checks (see `AGENTS.md`) and fix any failure.
2. Create `.local/` if needed. Write `.local/review-context.md`: a few lines on what the work is meant to do and where the task is described.
3. Write each check command you ran to `.local/review-checks`, one per line, exactly as you ran it; split a chain joined with `&&` into its commands. The reviewer may run these as written. A command with a `*` can't be allowed exactly, so put it in a script and list the script.
4. Create `.local/decisions.md` if it doesn't exist, with three sections. "Settled choices" records what the user has already decided in this session, one line each. "Findings" is the ledger described below. "Rounds" is where you log each round.
5. Run `${CLAUDE_SKILL_DIR}/scripts/state.sh` and record its `lines` value under "Rounds" as the starting size.

## The ledger

Every finding gets one entry under "Findings", kept for the whole loop:

    F3 · round 2 · fixed · src/export.py:41
    Behaviour: an empty table crashes the export. Cause: the loop reads the first row without checking.
    Fixed by: returning early when there are no rows.

- The status is `open`, `fixed`, `rejected`, `deferred` (real, but outside this task, so left for the user), `settled` (a choice you made) or `disputed`.
- A rejected entry gives one reason, `wrong`, `not worth fixing`, `already handled`, `style` or `duplicate`, and a sentence on why.
- A choice is written as `Ruling: <what you decided> — <why> — <what it costs if wrong>`.
- A finding that describes the same behaviour as an entry is that entry, however it is worded: update the entry instead of adding one.

## Each round

1. Run `${CLAUDE_SKILL_DIR}/scripts/state.sh` and note the fingerprint.
2. Run the reviewer, replacing N with the round number:

   ```
   ${CLAUDE_SKILL_DIR}/scripts/reviewer.sh --run-checks --schema ${CLAUDE_SKILL_DIR}/findings.schema.json <codex|claude> ${CLAUDE_SKILL_DIR}/reviewer-prompt.md .local/review-round-N.json
   ```

   Run it in the foreground with a 10-minute timeout and wait for it. The script stops a reviewer that runs past eight minutes, so it returns in time. If the reviewer can't run or writes nothing, the loop ends: go to "Finish". Don't review your own work instead.

3. Run `state.sh` again. If the fingerprint changed, the reviewer, or a check it ran, changed the work, and the loop ends: go to "Finish".
4. Read `.local/review-round-N.json`. If its `verdict` is `PASS` and it lists no findings, the loop ends clean: go to "Finish".
5. Have a fresh reviewer try to disprove the findings that weren't confirmed by running:

   ```
   ${CLAUDE_SKILL_DIR}/scripts/refute.sh <codex|claude> .local/review-round-N.json
   ```

   Run it like the reviewer. It writes the findings that survive to `.local/review-round-N.kept.json`, and the disproved ones, with the evidence, to `.local/review-round-N.refuted.json`. Enter each disproved finding in the ledger as rejected (`wrong`), with its evidence. If none survive, the loop ends clean: go to "Finish".
6. Check each surviving finding against the code, sort it, and record it in the ledger:
   - Real: accept it (`open`).
   - Real, but outside the task: defer it.
   - Not real: reject it, with a reason.
   - Needs a choice: take the option you would recommend and record a ruling (`settled`). Stop and ask the user only if the choice deletes data or can't be undone.

   If the reviewer raises a rejected finding again and gives a reason, reconsider it once. If you still disagree, ask a referee: write the finding, your reason and the reviewer's reason to `.local/referee-input.md`, and run this, with the finding's ledger id in place of ID:

   ```
   ${CLAUDE_SKILL_DIR}/scripts/reviewer.sh --schema ${CLAUDE_SKILL_DIR}/verdicts.schema.json <codex|claude> ${CLAUDE_SKILL_DIR}/referee-prompt.md .local/review-round-N.referee-ID.json
   ```

   If the referee says the finding stands, accept it. If it is refuted, keep it rejected and add the referee's evidence. If it is unclear, mark it `disputed` and leave it for the user.
7. Under "Rounds", log how many findings were reported, refuted, accepted, rejected and disputed, with one line for each.
8. Decide whether to continue, using "When to stop". If you stop, leave the accepted findings unfixed and go to "Finish".
9. Fix the accepted findings.
   - Round 1: fix each one and add or update a test.
   - Later rounds: every finding means an earlier fix didn't hold. Don't add a special case on top of it. Replace that piece with a simpler rule that covers the original finding and the new one, and test both.
10. Re-run the project's checks, then run `state.sh`, log the new `lines` value, and mark each fixed entry `fixed`, with what fixed it.
11. Replace the "Fixes to check" section of `.local/review-context.md` with the fixes you just made, and name the fingerprints from steps 1 and 10 as the snapshots from before and after them, so the next round checks those fixes and nothing else.

If `state.sh` fails at any step, the loop ends: go to "Finish" and report its error.

Log each round in the review log, which outlives the workspace, as soon as you know how the round ends: after step 8, or at the step that ends the loop.

```
${CLAUDE_SKILL_DIR}/scripts/log-round.sh --round N --reported R --refuted F --accepted A --rejected J --disputed D [--before <fingerprint> --after <fingerprint>] [--exit <name>]
```

From round 2, pass `--before` and `--after` with the two snapshots that "Fixes to check" names, so the log counts the findings that lie in lines those fixes changed. At that point the section still describes the fixes this round checked; step 11 replaces it later. Pass `--exit` with the name of the exit when the loop ends in this round.

## When to stop

The loop runs at most three rounds, and continues only while it is converging, which you judge from the number of findings you accepted in each round:

- Round 1: continue.
- Round 2: continue if you accepted no more findings than in round 1; stop if you accepted more.
- Round 3: stop, and leave its findings for the user.

Also stop when the fixes outgrow the work: when `lines` has passed the starting size by more than half, or by more than 200 lines if that is the larger allowance. By then the review is turning the task into a bigger one, and the user should decide.

## Finish

If the loop ended clean, in a round whose verdict was `PASS` or whose findings were all disproved:

1. Run the project's checks one last time.
2. Stage everything with `git add -A` and read the staged list. Unstage anything that shouldn't be committed, such as env files, databases or `.local/`.
3. Commit with a message that says what changed and why. Don't push; the user ships.

If the loop stopped for any other reason, don't commit. Leave the work as it is.

Either way, summarise for the user:

- how the loop ended, named as one of: clean, count rose, round cap, diff budget, reviewer failed, reviewer changed the work, or snapshot failed; after how many rounds; and the accepted count for each round;
- what you fixed;
- the findings still open or deferred, each with the simpler design you would use;
- the findings you rejected or disputed, and why, including those the refute step disproved;
- the choices you made on the user's behalf;
- the reviewer's below-threshold notes and what it declined to judge, if any;
- where the work differs from `.local/plan.md`, if there is one.
