---
name: apply-review
description: Work through a reviewer's findings saved in .local/review.md. Fixes the findings the agent agrees with and asks the user to decide the rest. Use when the user asks to apply, address or handle review findings.
---

A reviewer's findings are in `.local/review.md`. Check each one against the code.

- If you agree with a finding, fix it and add or update a test for it.
- If you disagree, or the finding needs a decision from the user, change nothing for it. Ask the user, one question at a time, and give your recommendation with each question.

When you're done, re-run the project's checks (see `AGENTS.md`) and list what you did for each finding.
