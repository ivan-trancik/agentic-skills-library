---
name: review-plan
description: Get your plan for a task reviewed by the other coding agent before showing it to the user. Use before presenting a plan, or when the user asks for a plan review.
---

Have the other coding agent review your plan before any code is written. This is one round, with no loop: the user is the final judge of a plan. The reviewer is Codex if you are Claude Code, and Claude Code if you are Codex.

On Windows, run the reviewer script below with `bash` in front, as in `bash ~/.agents/skills/review-loop/reviewer.sh ...`, which works from Git Bash and from PowerShell. If you are Claude Code, run it with the Bash tool.

1. Write the plan to `.local/plan.md`. Start it with the user's request, word for word. Then give what you will build, the files you expect to touch, the choices the user has to make with your recommendation for each, and how you will check the result.
2. Run the reviewer from the repository root, in the foreground with a 10-minute timeout. Pass `codex` if you are Claude Code and `claude` if you are Codex:

   ```
   ~/.agents/skills/review-loop/reviewer.sh <codex|claude> ~/.agents/skills/review-plan/reviewer-prompt.md .local/plan-review.md
   ```

   If the reviewer can't run or writes nothing, tell the user and show them the plan unreviewed. Don't review your own plan instead.
3. Read `.local/plan-review.md` and check each point against the code. Revise `.local/plan.md` where the reviewer is right. Don't send the plan back for a second round.
4. Show the user the revised plan. After it, list the reviewer's points you didn't take, with one line each on why. Then stop and wait for the user's go-ahead.
