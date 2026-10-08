# Agentic skills library

Skills for coding agents, shared by Claude Code and OpenAI Codex, installed once for every project on this Mac.

## Goal

An agent should not grade its own work. The skills here make the two harnesses check each other: whichever one builds, the other reviews the plan before any code is written, the screenshots after a page changes, and the diff before the commit. The reviewer runs headless from the command line, reports only must-fix findings, and may not change the work. The user stays the judge of plans and designs. The code review loop runs without supervision and ends in a commit, never a push.

The library stays small on purpose: six skills, one installer, one instruction block, all readable in one sitting.

## Status

First version, October 2026. Installed on this Mac with Codex CLI 0.160 and Claude Code 2.1.29x. No automated checks yet.

The first [research cycle](research/README.md), in October 2026, compared the library with about twenty comparable libraries, both CLIs' built-in review commands, and the published evidence on cross-model review. It confirmed the design and found these gaps, each with a fix in the [implementation plan](research/2026-10-07-cross-agent-review-landscape/plan.md):

- The Claude reviewer is told not to edit; it is not prevented from editing.
- The Codex reviewer's reasoning effort is forced to `high`, which can be below the user's configured default.
- The review loop has no hard round cap.
- The full-page screenshot is downscaled by the vision model until its text is unreadable.
- `ship` can be chosen by the model; it should be explicit-only.
- Helper scripts are referenced by their installed path rather than relative to the skill.
- This repository has no `AGENTS.md` with checks of its own.

None of the plan is implemented yet.

## The skills

| Skill | What it does |
|---|---|
| `review-plan` | One round of review on a plan before any code is written |
| `review-design` | One round of review on the look of a changed page, from screenshots |
| `review-loop` | Code review by the other agent, fixes, and repeat while the findings keep falling; then a commit |
| `save-review` | The reviewer writes its findings to `.local/review.md` for another agent |
| `apply-review` | The builder fixes the findings it agrees with and asks the user about the rest |
| `ship` | Checks, commit, take in the default branch, push, pull request, squash-merge; only when the user asks |

`instructions/` holds the default sequence for any task that adds or changes behaviour: plan, plan review, the user's go-ahead, build and the project's checks, design review where a page changed, the user's feedback, the code review loop, commit. Shipping only when asked.

What lets the review loop run unsupervised:

- The reviewer reports only must-fix findings, each with a file and line, a failure scenario, and whether it was confirmed by running something or by reading the code.
- The builder sorts each finding into real, rejected with a recorded reason, or disputed and left for the user. Rejected findings are recorded in `.local/decisions.md` so they are not raised again.
- The loop stops when the number of accepted findings stops falling, or when the diff has grown beyond its starting size by more than half, or by more than 200 lines where that allowance is larger.
- A fingerprint of the work is taken before and after each review, so a reviewer that edited anything is caught.

## Install

```bash
./install.sh
```

This copies each skill to `~/.agents/skills/<name>`, which Codex reads, links it from `~/.claude/skills/<name>`, which Claude Code reads (on Windows it copies it there; see below), and adds the instruction block to `~/.claude/CLAUDE.md` and `~/.codex/AGENTS.md`. Run it again after changing anything here. `./install.sh --uninstall` removes exactly what it installed.

`--skip <name>`, which can be repeated, leaves that skill alone, and `--no-instructions` leaves the instruction block alone, as in `./install.sh --skip ship --no-instructions`. Both work with `--uninstall` too. Neither removes what an earlier run installed. A name that doesn't match a folder in `skills/` exactly, case included, stops the run before anything is touched.

Every installed copy carries a marker. The installer refuses to replace a same-name skill it didn't create, and removes only marked copies. Edit the source here and reinstall; edits made to installed copies are overwritten.

Both locations are needed. Claude Code does not read `~/.agents/skills` itself but follows the symlink from `~/.claude/skills`. Codex also still reads `~/.codex/skills`, so a same-name skill there would shadow the installed one. Both were checked on the versions above.

### Windows

Run `./install.sh` from Git Bash, which comes with Git for Windows. Developer Mode isn't needed.

On Windows the installer puts a second marked copy of each skill in `~/.claude/skills/<name>` instead of a link, because Git Bash's `ln -s` makes a plain copy unless Developer Mode is on and `MSYS=winsymlinks:nativestrict` is set. Reinstalling replaces the copies, `--uninstall` removes them, and a same-name folder without the marker is left alone. If another program holds a file in a copy open, the installer leaves that copy whole and says what to close. It also warns when bash's `HOME` isn't the Windows user folder, which is where both agents look.

## What a project needs

- An `AGENTS.md` that says how to run its checks, such as tests and a typecheck. The skills refer to "the project's checks" and look there. Claude Code reads a project `AGENTS.md` natively since version 2.1.277 when there is no `CLAUDE.md`; a `CLAUDE.md` containing `@AGENTS.md` still works.
- A GitHub remote, for `ship`.

Working files go in `.local/` in the project. The scripts add `.local/` to the repo's local git exclude list if the project doesn't ignore it.

## How the reviewer is run

`skills/review-loop/reviewer.sh` runs the other agent from the command line: `codex exec` when Claude Code is the builder, `claude -p` when Codex is. The reviewer may run the project's checks and read-only commands, keeps scratch files in `.local/scratch/`, and is told not to change the work. The builder checks a fingerprint of the work before and after each review to be sure.

The reviewer runs on each harness's own default model, as set in `~/.codex/config.toml` and `~/.claude/settings.json`. The script currently sets the Codex reviewer's reasoning effort to `high`; changing that is in the plan.

## Research

`research/` holds the periodic research cycles that compare these skills with what comparable tools, standards and studies do, and the implementation plans derived from them. [research/README.md](research/README.md) describes the layout and how to run a cycle. The latest report is [2026-10-07 cross-agent review landscape](research/2026-10-07-cross-agent-review-landscape/report.md).

## Adding a skill

Add a folder under `skills/` with a `SKILL.md` that starts with `name` and `description` front matter, and reinstall. Refer to helper scripts by their installed path, `~/.agents/skills/<name>/...`, until the plan's move to relative paths is done.
