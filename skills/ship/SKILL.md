---
name: ship
description: Commit the current work, push the branch, open a pull request against the default branch and squash-merge it. Use only when the user explicitly asks to ship; never on your own initiative.
---

Ship the work in this checkout. Stop and report at the first step that fails; never force a push or a merge.

"The default branch" below is what `gh repo view --json defaultBranchRef --jq .defaultBranchRef.name` prints, usually `main`.

1. Run the project's checks (see `AGENTS.md`). If any fail, stop.
2. If the current branch is the default branch, create a branch for the change first.
3. Stage everything with `git add -A`, then read the staged file list. Unstage and report anything that should not be committed, such as env files, databases or `.local/`.
4. Commit with a message that says what changed and why.
5. Take in the latest default branch: run `git fetch origin`, then `git merge origin/<default branch>`. If the merge brought in changes, re-run the checks. If it conflicts, keep both sides wherever each side only added something, such as script entries, table rows, list items or documentation sections, then re-run the checks. If a conflict needs a real choice between two versions of the same code, stop and report.
6. Push the branch to `origin`.
7. Open a pull request against the default branch with `gh pr create`. Give it a short description of the change and how it was checked.
8. Squash-merge it with `gh pr merge --squash`. If GitHub refuses because the default branch moved in the meantime, repeat step 5 once and try again. Leave the local branch in place; the user deletes the workspace afterwards.
9. If the main checkout (the first entry of `git worktree list`) is on the default branch with no local changes, fast-forward it with `git pull --ff-only origin <default branch>`, so new workspaces start from the merged work.

Finish by giving the pull request's URL and the merge commit on the default branch.
