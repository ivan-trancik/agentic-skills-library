You are the referee in a disagreement about one finding on the uncommitted work in this repository. Don't change any files.

`.local/referee-input.md` holds the finding, the builder's reason for rejecting it, and the reviewer's reason for raising it again. `.local/review-context.md` says what the work is meant to do.

Check the code yourself rather than taking either side's word for what it does. Reply in the JSON form you were given, with one verdict, for finding 1:

- `stands`: the failure can happen. In `evidence`, quote the code that lets it.
- `refuted`: the code shows it can't. In `evidence`, quote the lines that show it, at most three, with their file and line.
- `unclear`: the code doesn't settle it. In `evidence`, say what would.
