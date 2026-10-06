---
name: save-review
description: Save the findings of a code review to .local/review.md so another agent can work through them. Use after a review, when the user asks to save or hand over the findings.
---

Don't fix anything.

Write all findings from your review to `.local/review.md`, numbered, each with its file, line and failure scenario. Create the `.local/` folder if it doesn't exist; it is gitignored.

If this session has no review findings yet, say so and stop.
