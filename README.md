# Agentic skills library

Skills for coding agents, shared by Claude Code and OpenAI Codex, installed once for every project on this Mac.

## Goal

An agent should not grade its own work. The skills here make the two harnesses check each other: whichever one builds, the other reviews the plan before any code is written, the screenshots after a page changes, and the diff before the commit. The reviewer runs headless from the command line, reports only must-fix findings, and may not change the work. The user stays the judge of plans and designs. The code review loop runs without supervision and ends in a commit, never a push.

The library stays small on purpose: six skills, one installer, one instruction block and their checks, all readable in one sitting.

## Status

Second version, October 2026. Installed on this Mac with Codex CLI 0.160.1 and Claude Code 2.1.294. `tests/check.sh` holds this repository's checks, and `tests/live.sh` tests the real reviewers; `AGENTS.md` says when to run each.

The first [research cycle](research/README.md), in October 2026, compared the library with about twenty comparable libraries, both CLIs' built-in review commands, and the published evidence on cross-model review. It confirmed the design and produced an [implementation plan](research/2026-10-07-cross-agent-review-landscape/plan.md). The second version carries out its first part:

- The Claude reviewer can no longer edit: it has no editing tools, ignores every settings file, and may run only the listed checks. Plan and design reviewers are read-only in both harnesses.
- The Codex reviewer runs at the user's configured reasoning effort.
- The review loop runs three rounds at most and names the reason it stopped.
- A reviewer that runs too long is stopped, and a Codex reviewer is then asked for its findings so far.
- `ship` starts only when the user calls it by name.
- This repository has an `AGENTS.md` and checks of its own.

Since then, each skill names its scripts relative to its own folder, and `./install.sh --check` reports whether the installed copies match this repository. The review loop now takes the CLIs' own review tests, gets its findings as JSON, has a second reviewer try to disprove them, keeps a ledger of every finding, and logs every round. The design review takes its screenshots with Playwright: the whole page in readable tiles, tablet, phone, dark mode and keyboard focus, a canary image that proves the reviewer saw them, and a Lighthouse accessibility audit. Of the research plan, only one decision is open: whether the Codex reviewer's first round should use Codex's own `review` command, which found one more bug in a two-case comparison but replies in a format the loop would have to parse.

## The skills

| Skill | What it does |
|---|---|
| `review-plan` | One round of review on a plan before any code is written |
| `review-design` | One round of review on the look of a changed page, from screenshots |
| `review-loop` | Code review by the other agent, fixes, and repeat while the findings keep falling; then a commit |
| `save-review` | The reviewer writes its findings to `.local/review.md` for another agent |
| `apply-review` | The builder fixes the findings it agrees with and asks the user about the rest |
| `ship` | Checks, commit, take in the default branch, push, pull request, squash-merge; only when the user calls it by name |

`instructions/` holds the default sequence for any task that adds or changes behaviour: plan, plan review, the user's go-ahead, build and the project's checks, design review where a page changed, the user's feedback, the code review loop, commit. Shipping only when the user calls `ship` by name: `/ship` in Claude Code, `$ship` in Codex.

What lets the review loop run unsupervised:

- The reviewer reports only must-fix findings that pass the tests both CLIs' own review commands use: introduced by this change, shown to affect any other code it names, resting on no unstated assumption, and something the author would fix. Each comes as JSON, with a file and line, a failure scenario, and whether it was confirmed by running something, by reading the code, or neither.
- A second, fresh reviewer tries to disprove every finding that wasn't confirmed by running, and the disproved ones never reach the builder.
- The builder sorts the rest into accepted, deferred, rejected with one of five recorded reasons, or a choice it rules on. `.local/decisions.md` keeps one entry per finding, and a reworded repeat of a settled finding counts as that finding. A finding the builder still rejects after the reviewer raised it again goes to a fresh referee; only one the referee can't settle reaches the user.
- Each round's fixes are snapshotted as git trees, so the next round sees exactly what they changed, new files included, and checks first that no test was weakened.
- The loop runs three rounds at most. It stops sooner when the number of accepted findings rises, or when the diff has grown beyond its starting size by more than half, or by more than 200 lines where that allowance is larger. Its summary names the reason it stopped.
- The reviewer has no tool that can edit the work. In code reviews it may run the project's checks, which can write, and the Codex reviewer's sandbox can write in the repository, so a fingerprint of the work is taken before and after each review, and a change made during a review is caught.

## Install

```bash
./install.sh
```

This copies each skill to `~/.agents/skills/<name>`, which Codex reads, links it from `~/.claude/skills/<name>`, which Claude Code reads, and adds the instruction block to `~/.claude/CLAUDE.md` and `~/.codex/AGENTS.md`. Run it again after changing anything here. `./install.sh --check` reports each installed skill and instruction block as current, changed or missing, and notes when a CLI differs from the version `tests/live.sh` last passed on. `./install.sh --uninstall` removes exactly what it installed.

Every installed copy carries a marker that names the commit it came from. The installer refuses to replace a same-name skill it didn't create, and removes only marked copies. Edit the source here and reinstall; edits made to installed copies are overwritten. A script that several skills use, such as the reviewer runner, is a symlink here and becomes a file of its own in each installed copy.

Both locations are needed. Claude Code does not read `~/.agents/skills` itself but follows the symlink from `~/.claude/skills`. Codex also still reads `~/.codex/skills`, so a same-name skill there would shadow the installed one; the installer warns when it finds one. Both were checked on the versions above.

## What a project needs

- An `AGENTS.md` that says how to run its checks, such as tests and a typecheck. The skills refer to "the project's checks" and look there. Claude Code reads a project `AGENTS.md` natively since version 2.1.277 when there is no `CLAUDE.md`; a `CLAUDE.md` containing `@AGENTS.md` still works.
- A GitHub remote, for `ship`.
- Google Chrome and Node.js, for `review-design`. Its scripts fetch Playwright 1.63.0 and Lighthouse 13.5.0 through `npx` on first use and drive the installed Chrome, so no browser is downloaded.

Working files go in `.local/` in the project. The scripts add `.local/` to the repo's local git exclude list if the project doesn't ignore it.

## How the reviewer is run

`skills/review-loop/scripts/reviewer.sh` runs the other agent from the command line: `codex exec` when Claude Code is the builder, `claude -p` when Codex is.

- Plan and design reviews are read-only. Codex runs in its `read-only` sandbox, and Claude gets only the `Read`, `Grep` and `Glob` tools.
- Code reviews pass `--run-checks`. Claude then also gets the shell, in `dontAsk` mode: it may run read-only commands and the exact check commands the builder listed in `.local/review-checks`, and every other command is denied. Codex runs in its `workspace-write` sandbox, which test suites need for their caches but which also lets it edit files, and it may keep scratch files in `.local/scratch/`. The checks themselves can write too, which is why the builder compares a fingerprint of the work before and after each review.
- Claude runs with `--restricted`, which ignores every settings file, so no allow rule in a user or project file can open the shell to it; the script passes on only the user's model and effort from `~/.claude/settings.json`. `--safe-mode` also leaves out CLAUDE.md, skills, plugins, hooks and MCP servers, which cut a one-word launch in `tests/live.sh` from about $0.10 to under a cent.
- Each reviewer runs on its harness's own model and reasoning effort, as set in `~/.codex/config.toml` and `~/.claude/settings.json`. `REVIEWER_EFFORT` overrides the effort for both.
- `REVIEWER_TIMEOUT`, 480 seconds by default, is the reviewer's deadline. The script then stops the reviewer's whole process group, resumes a Codex reviewer once at `medium` effort for its findings so far, and stays within the builder's 10-minute command limit.
- `--schema <file>` makes the reviewer reply with JSON that matches the schema: `--json-schema` for Claude, `--output-schema` for Codex. Every run leaves a record beside its output: the harness, the seconds it took, whether the deadline fired, and its cost or token counts.

## The review log

`review-loop` appends one line per round to `~/.local/state/agentic-skills-library/review-loop.jsonl`, which outlives the workspace: the repository and branch, how many findings were reported, refuted, accepted, rejected and disputed, how many lay in lines the previous fixes changed, the size of the work, the round's time and cost, and how the loop ended. For example:

```bash
log=~/.local/state/agentic-skills-library/review-loop.jsonl
jq -s 'map(select(.exit)) | group_by(.exit) | map({exit: .[0].exit, loops: length})' "$log"   # how loops end
jq -s '{reported: (map(.reported) | add), refuted: (map(.refuted) | add), accepted: (map(.accepted) | add)}' "$log"
jq -s 'map(select(.round > 1)) | {later_findings: (map(.reported) | add), in_previous_fix: (map(.in_previous_fix // 0) | add)}' "$log"
```

## Research

`research/` holds the periodic research cycles that compare these skills with what comparable tools, standards and studies do, and the implementation plans derived from them. [research/README.md](research/README.md) describes the layout and how to run a cycle. The latest report is [2026-10-07 cross-agent review landscape](research/2026-10-07-cross-agent-review-landscape/report.md); the status boxes in its plan show what is done.

## Adding a skill

Add a folder under `skills/` with a `SKILL.md` that starts with `name` and `description` front matter. Put its scripts in `scripts/` and name them as `${CLAUDE_SKILL_DIR}/scripts/<name>`, after the line the other skills use to tell Codex what that stands for; a script another skill already has is a symlink to it. Run `tests/check.sh` and `tests/validate.sh`, and reinstall.
