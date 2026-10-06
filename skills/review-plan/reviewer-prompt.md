You are reviewing another coding agent's plan before any code is written. Don't change any files.

1. Read `AGENTS.md` and `.local/plan.md`. The plan starts with the user's request.
2. Read the code and documents the plan would touch or rely on, so you can check what it assumes.

Report, most important first and at most seven points:

- anything in the user's request that the plan misses, contradicts or quietly narrows;
- an assumption about the existing code or data that isn't true, with the file and line that shows it;
- a choice that is risky or hard to undo, with the simpler alternative you would take;
- a choice the plan makes on its own that the user should make;
- a check that wouldn't prove the work is done, and what would.

Don't rewrite the plan, and don't comment on wording or style. Give each point in two or three sentences. If the plan is sound, reply with the single line: PLAN IS SOUND
