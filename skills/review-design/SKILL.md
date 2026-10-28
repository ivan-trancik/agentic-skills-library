---
name: review-design
description: Get the look and layout of a page you changed reviewed by the other coding agent, from screenshots. Use after building a change to the page and before showing it to the user, or when the user asks for a design review.
---

Have the other coding agent review the page you changed, from screenshots, then open the page itself for the user. This is one round, with no loop: the user is the final judge of a design. The reviewer is Codex if you are Claude Code, and Claude Code if you are Codex.

`${CLAUDE_SKILL_DIR}` in the commands below stands for this skill's folder, the one that holds this file.

1. Start the app the way `AGENTS.md` says, and make sure it shows realistic data. It has to keep running after your turn ends, so that the user can try the page. In a Superset workspace, which sets `$SUPERSET_WORKSPACE_ID`, run it in a terminal of the workspace: the terminal outlives your turn, and the user can watch its log. There `./.superset/run.sh` starts the app on the workspace's own port. Note the `terminalId` the first command prints; the second shows the terminal's screen, with the address the app serves:

   ```
   superset terminals create --local --workspace "$SUPERSET_WORKSPACE_ID" --command ./.superset/run.sh
   superset terminals read --local --workspace "$SUPERSET_WORKSPACE_ID" --terminal <terminalId>
   ```

   Elsewhere, start it in the background.
2. Take the screenshots the reviewer will look at, and run the accessibility audit. Each script fetches its tool through `npx` on its first run.

   ```
   ${CLAUDE_SKILL_DIR}/scripts/screenshot.sh <url> .local/design
   ${CLAUDE_SKILL_DIR}/scripts/a11y.sh <url> .local/design/a11y.txt
   ```

   `screenshot.sh` writes a canary image, the desktop view, the whole page in tiles, tablet, phone, dark mode and the page after one Tab press, and lists them with what each shows in `.local/design/shots.txt`. If it says part of a long page has no tile and the change is in that part, capture that part with your own browser tools. Do the same for each state the task is about that needs a click, such as an opened row or an empty page. Add each image you take to `shots.txt`.
3. Write `.local/design-context.md`: the user's design goals, word for word; what you changed; the counts the screenshots should show, such as "8 rows" or "3 tabs"; and the states the screenshots don't show, so that the reviewer doesn't report them missing.
4. Run the reviewer from the repository root, in the foreground with a 10-minute timeout, passing every image in the order `shots.txt` lists them, `canary.png` first. The script keeps the reviewer read-only and stops it if it runs past eight minutes. Pass `codex` if you are Claude Code and `claude` if you are Codex:

   ```
   ${CLAUDE_SKILL_DIR}/scripts/reviewer.sh <codex|claude> ${CLAUDE_SKILL_DIR}/reviewer-prompt.md .local/design-review.md .local/design/canary.png .local/design/desktop.png ...
   ```

   If the reviewer can't run or writes nothing, tell the user, and go on to step 7 to show them the page unreviewed.
5. Check that the reviewer saw the images:

   ```
   ${CLAUDE_SKILL_DIR}/scripts/screenshot.sh --check .local/design .local/design-review.md
   ```

   If the check fails, the review describes images the reviewer didn't see: don't use it. Tell the user, and go on to step 7 to show them the page unreviewed.
6. Read `.local/design-review.md`. Fix the must-fix findings you agree with. Leave the suggestions for the user to choose from. Then make sure the running app shows your fixes, and restart it if it doesn't reload changes by itself.
7. Open the page for the user in a new tab, without bringing it to the front. In a Superset workspace, that is a tab of the workspace's browser pane:

   ```
   superset browser open --workspace "$SUPERSET_WORKSPACE_ID" --url <url> --target new-tab
   ```

   Superset can open the pane only while the workspace is on screen; if the command fails, the user opens the URL from your reply instead. Elsewhere, `open -g <url>` opens it in the default browser.
8. Give the user the URL of each page you changed, how to reach each state the task is about that needs a click, what you fixed, and the reviewer's suggestions and any findings you didn't take. Then stop and wait for the user's feedback.
9. Leave the app running while the user tries the page and you make the changes they ask for. Once they are done with the design, stop it. In Superset, close its terminal:

   ```
   superset terminals close --local --workspace "$SUPERSET_WORKSPACE_ID" --terminal <terminalId>
   ```
