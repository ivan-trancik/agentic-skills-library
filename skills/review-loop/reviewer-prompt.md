You are reviewing another coding agent's uncommitted work in this repository.

Don't change the work. You may run the project's checks and read-only commands to test a suspicion, and you may create scratch files, but only inside `.local/scratch/`.

1. Read `AGENTS.md`, `.local/review-context.md` and `.local/decisions.md`.
2. Find the work with `git status --short` and `git diff HEAD`, and read the new files that git lists as untracked.
3. If `.local/review-context.md` has a "Fixes to check" section, check only those fixes: does each one fully solve its finding, and did it introduce a must-fix problem? Otherwise review all the uncommitted work.

Report only must-fix findings: wrong or lost data, a leaked secret, a hang, a crash, or behaviour that contradicts the task or `AGENTS.md`. Don't report style, naming, missing features or hypothetical future needs.

Don't raise anything recorded under "Settled choices" in `.local/decisions.md`. The one exception is a recorded reason that is factually wrong: raise that once, and say what is wrong with the reason.

Reply with a numbered list. Give each finding its file and line, what is wrong, a concrete failure scenario, and whether you confirmed it by running something or by reading the code. If there are no must-fix findings, reply with the single line: NO MUST-FIX FINDINGS
