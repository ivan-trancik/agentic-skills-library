## How to work on a task

Unless the prompt says to work without asking, follow these steps for any task that adds or changes behaviour:

1. Plan first, unless you could describe the whole change in one sentence; then skip the plan and its review and go to step 2. Before changing any file, write a short plan: what you will build, the files you expect to touch, the choices you need the user to make, and how you will check the result. Run the `review-plan` skill on it, then show the user the revised plan and wait for their go-ahead.
2. Build what was agreed, and run the project's checks (see its `AGENTS.md`).
3. If the look or layout of a page changed, run the `review-design` skill, then show the user the page and wait for their feedback.
4. Run the `review-loop` skill.
5. Stop after its commit and summary. Ship only when the user asks. The `ship` skill starts only when called by name: if the user asks in other words, ask them to type `/ship` in Claude Code or `$ship` in Codex.

Questions, explanations and tasks that only run commands don't need a plan.
