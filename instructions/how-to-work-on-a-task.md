## How to work on a task

Unless the prompt says to work without asking, follow these steps for any task that adds or changes behaviour:

1. Plan first. Before changing any file, write a short plan: what you will build, the files you expect to touch, the choices you need the user to make, and how you will check the result. Run the `review-plan` skill on it, then show the user the revised plan and wait for their go-ahead.
2. Build what was agreed, and run the project's checks (see its `AGENTS.md`).
3. If the look or layout of a page changed, run the `review-design` skill, then show the user the screenshots and wait for their feedback.
4. Run the `review-loop` skill.
5. Stop after its commit and summary. Ship only when the user asks, with the `ship` skill.

Questions, explanations and tasks that only run commands don't need a plan.
