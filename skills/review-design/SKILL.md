---
name: review-design
description: Get the look and layout of a page you changed reviewed by the other coding agent, from screenshots. Use after building a change to the page and before showing it to the user, or when the user asks for a design review.
---

Have the other coding agent review the page you changed, from screenshots. This is one round, with no loop: the user is the final judge of a design. The reviewer is Codex if you are Claude Code, and Claude Code if you are Codex.

1. Start the app the way `AGENTS.md` says, in the background, and make sure it shows realistic data. In a Superset workspace, `./.superset/run.sh` starts it on the workspace's own port.
2. Take screenshots into `.local/design/`:

   ```
   ~/.agents/skills/review-design/screenshot.sh <url> .local/design/desktop.png 1440 900
   ~/.agents/skills/review-design/screenshot.sh <url> .local/design/desktop-full.png 1440 4000
   ~/.agents/skills/review-design/screenshot.sh <url> .local/design/phone.png 390 844
   ```

   Add one for each state the task is about, such as an opened row or an empty page. The script can't click, so use your own browser tools for those.
3. Write `.local/design-context.md`: the user's design goals, word for word; what you changed; and each screenshot's file name with what it shows.
4. Run the reviewer from the repository root, in the foreground with a 10-minute timeout, passing every screenshot. The script keeps the reviewer read-only and stops it if it runs past eight minutes. Pass `codex` if you are Claude Code and `claude` if you are Codex:

   ```
   ~/.agents/skills/review-loop/reviewer.sh <codex|claude> ~/.agents/skills/review-design/reviewer-prompt.md .local/design-review.md .local/design/desktop.png .local/design/desktop-full.png .local/design/phone.png
   ```

   If the reviewer can't run or writes nothing, tell the user and show them the screenshots unreviewed.
5. Read `.local/design-review.md`. Fix the must-fix findings you agree with. Leave the suggestions for the user to choose from.
6. Take the screenshots again and stop the app.
7. Show the user the screenshot files, what you fixed, and the reviewer's suggestions and any findings you didn't take. Then stop and wait for the user's feedback.
