---
name: review-loop
description: Get the uncommitted work reviewed by the other coding agent, fix its must-fix findings and repeat while the findings keep falling, then commit. Use when the user asks for a review loop, or to have the work reviewed and fixed without supervision.
---

Run a build-and-review loop on the uncommitted work in this checkout, without asking the user anything until the end. You are the builder. The reviewer is the other coding agent: Codex if you are Claude Code, Claude Code if you are Codex.

The user asking for this skill is permission to commit when the loop ends clean, even if the task said earlier not to commit. It is never permission to push.

`${CLAUDE_SKILL_DIR}` in the commands below stands for this skill's folder, the one that holds this file.

## Before the first round

1. Run the project's checks (see `AGENTS.md`) and fix any failure.
2. Create `.local/` if needed. Write `.local/review-context.md`: a few lines on what the work is meant to do and where the task is described.
3. Write each check command you ran to `.local/review-checks`, one per line, exactly as you ran it; split a chain joined with `&&` into its commands. The reviewer may run these as written. A command with a `*` can't be allowed exactly, so put it in a script and list the script.
4. Create `.local/decisions.md` if it doesn't exist, with two sections. "Settled choices" records what the user has already decided in this session, one line each. "Rounds" is where you log each round.
5. Run `${CLAUDE_SKILL_DIR}/scripts/state.sh` and record its `lines` value under "Rounds" as the starting size.

## Each round

1. Run `${CLAUDE_SKILL_DIR}/scripts/state.sh` and note the fingerprint.
2. Run the reviewer from the repository root, replacing N with the round number. Pass `codex` if you are Claude Code and `claude` if you are Codex:

   ```
   ${CLAUDE_SKILL_DIR}/scripts/reviewer.sh --run-checks <codex|claude> ${CLAUDE_SKILL_DIR}/reviewer-prompt.md .local/review-round-N.md
   ```

   Run it in the foreground with a 10-minute timeout and wait for it. The script stops a reviewer that runs past eight minutes, so it returns in time. If the reviewer can't run or writes no findings, stop and go to "Finish"; don't review your own work instead.

3. Run `state.sh` again. If the fingerprint changed, the reviewer, or a check it ran, changed the work: stop and go to "Finish".
4. Read `.local/review-round-N.md`. If it has the line `NO MUST-FIX FINDINGS` and lists no findings, go to "Finish".
5. Check each finding against the code and sort it:
   - Real: accept it.
   - Not real: reject it and record why under "Settled choices", so it isn't raised again. If the reviewer raises a rejected finding again and gives a reason, reconsider it once. If you still disagree, mark it as disputed and leave it for the user.
   - Needs a choice: take the option you would recommend and record it under "Settled choices". Stop and ask the user only if the choice deletes data or can't be undone.
6. Log the round under "Rounds": how many findings were reported, accepted, rejected and disputed, with one line for each.
7. Decide whether to continue, using "When to stop". If you stop, leave the accepted findings unfixed and go to "Finish".
8. Fix the accepted findings.
   - Round 1: fix each one and add or update a test.
   - Later rounds: every finding means an earlier fix didn't hold. Don't add a special case on top of it. Replace that piece with a simpler rule that covers the original finding and the new one, and test both.
9. Re-run the project's checks, then run `state.sh` and log the new `lines` value.
10. Replace the "Fixes to check" section of `.local/review-context.md` with the fixes you just made, so the next round checks those and nothing else.

## When to stop

The loop runs at most three rounds, and continues only while it is converging, which you judge from the number of findings you accepted in each round:

- Round 1: continue.
- Round 2: continue if you accepted no more findings than in round 1; stop if you accepted more.
- Round 3: stop, and leave its findings for the user.

Also stop when the fixes outgrow the work: when `lines` has passed the starting size by more than half, or by more than 200 lines if that is the larger allowance. By then the review is turning the task into a bigger one, and the user should decide.

## Finish

If the loop ended clean, with `NO MUST-FIX FINDINGS`:

1. Run the project's checks one last time.
2. Stage everything with `git add -A` and read the staged list. Unstage anything that shouldn't be committed, such as env files, databases or `.local/`.
3. Commit with a message that says what changed and why. Don't push; the user ships.

If the loop stopped for any other reason, don't commit. Leave the work as it is.

Either way, summarise for the user:

- how the loop ended, named as one of: clean, count rose, round cap, diff budget, reviewer failed, or reviewer changed the work; after how many rounds; and the accepted count for each round;
- what you fixed;
- the findings still open, each with the simpler design you would use;
- the findings you rejected or disputed, and why;
- the choices you made on the user's behalf.
