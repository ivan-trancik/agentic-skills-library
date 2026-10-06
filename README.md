# Agentic skills library

Skills for coding agents, shared by Claude Code and Codex, installed once for every project on this Mac.

The skills here make the two harnesses check each other's work. One builds, the other reviews, and the user sees the result after the review:

| Skill | What it does |
|---|---|
| `review-plan` | One round of review on a plan before any code is written |
| `review-design` | One round of review on the look of a changed page, from screenshots |
| `review-loop` | Code review by the other agent, fixes, and repeat while the findings keep falling; then a commit |
| `save-review` | The reviewer writes its findings to `.local/review.md` for another agent |
| `apply-review` | The builder fixes the findings it agrees with and asks the user about the rest |
| `ship` | Checks, commit, take in the default branch, push, pull request, squash-merge |

`instructions/` holds the default sequence for any task: plan, plan review, the user's go-ahead, build, design review where a page changed, the user's feedback, the code review loop, commit. Shipping only when asked.

## Install

```bash
./install.sh
```

This copies each skill to `~/.agents/skills/<name>`, which Codex reads, links it from `~/.claude/skills/<name>`, which Claude Code reads, and adds the instruction block to `~/.claude/CLAUDE.md` and `~/.codex/AGENTS.md`. Run it again after changing anything here. `./install.sh --uninstall` removes exactly what it installed.

Every installed copy carries a marker. The installer refuses to replace a same-name skill it didn't create, and removes only marked copies. Edit the source here and reinstall; edits made to installed copies are overwritten.

## What a project needs

- An `AGENTS.md` that says how to run its checks, such as tests and a typecheck. The skills refer to "the project's checks" and look there. For Claude Code, a `CLAUDE.md` containing `@AGENTS.md` makes it read the same file.
- A GitHub remote, for `ship`.

Working files go in `.local/` in the project. The scripts add `.local/` to the repo's local git exclude list if the project doesn't ignore it.

## How the reviewer is run

`skills/review-loop/reviewer.sh` runs the other agent from the command line: `codex exec` when Claude Code is the builder, `claude -p` when Codex is. The reviewer may run the project's checks and read-only commands, keeps scratch files in `.local/scratch/`, and is told not to change the work. The builder checks a fingerprint of the work before and after each review to be sure.

The reviewer runs on each harness's own default model, as set in `~/.codex/config.toml` and `~/.claude/settings.json`.

## Adding a skill

Add a folder under `skills/` with a `SKILL.md` that starts with `name` and `description` front matter, and reinstall. Refer to helper scripts by their installed path, `~/.agents/skills/<name>/...`.
