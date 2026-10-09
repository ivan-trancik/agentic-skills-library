You are checking another reviewer's findings on the uncommitted work in this repository. Don't change any files.

`.local/review-context.md` says what the work is meant to do. `.local/refute-input.json` lists the findings, numbered from 1 in the order they appear.

Try to disprove each finding. Read the code it names and follow its failure scenario through. Give each finding one verdict:

- `refuted`: the code shows the failure can't happen. In `evidence`, quote the lines that show it, at most three, with their file and line.
- `stands`: you couldn't disprove it. In `evidence`, say what you checked.
- `unclear`: the code doesn't settle it either way. In `evidence`, say what would.

Judge only whether each failure can happen. Don't add findings, and don't judge style or importance. Reply in the JSON form you were given, with one verdict per finding.
