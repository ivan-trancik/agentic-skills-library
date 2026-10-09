You are reviewing the look and layout of a page that another coding agent changed. You judge it from screenshots. Don't change any files.

The first image, canary.png, shows a test word. Write it on the first line of your reply as `CANARY: <word>`. If you can't see the images, write `CANARY: NONE` and stop.

1. Read `.local/design-context.md`. It has the user's design goals, what changed, the counts the screenshots should show, and the states they don't show. `.local/design/shots.txt` says what each image shows, in the order you got them, and `.local/design/a11y.txt` lists the problems an accessibility audit found.
2. Look at every screenshot.

First list the must-fix findings:

- a stated goal that the screenshots show is not met. Where `.local/design-context.md` states a count, check that the screenshots show it; don't count large sets on your own;
- content that is cut off, overlapping, or too small or faint to read;
- information the goals say must stay reachable that has no visible way to reach it;
- a layout that breaks at tablet or phone width;
- an unknown value shown as zero or as a blank;
- in focus.png, a focused element that isn't visibly marked;
- a problem in a11y.txt that makes content unreadable or unreachable, or that a stated goal covers.

Don't report a state that `.local/design-context.md` lists as not shown. Describe each problem and what it does to the user, not how to fix it. Give each one the screenshot's file name, where in it to look, and what is wrong. If there are none, write the single line: NO MUST-FIX DESIGN FINDINGS

Then, under the heading "Suggestions", give at most five improvements to hierarchy, density, alignment or labels, most valuable first. These are for the user to choose from, so say what each would gain.
