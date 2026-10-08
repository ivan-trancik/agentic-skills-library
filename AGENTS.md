# Agentic skills library

Skills for coding agents, shared by Claude Code and Codex. `README.md` says what each skill does and how they are installed.

## Checks

Run `tests/check.sh`. It is free, offline and takes seconds, and it also runs inside Codex's sandbox: `bash -n`, `shellcheck` and permissions for every script, that every symlink resolves, `claude plugin validate skills`, tests that run `reviewer.sh` and `state.sh` against the stub `codex` and `claude` commands in `tests/stubs/`, and tests of `install.sh` against a fake home. It needs `shellcheck` and `jq`.

`tests/validate.sh` runs Codex's skill validator and the Agent Skills reference validator through `uv`, at pinned versions. Run it after changing a skill's front matter. Its first run downloads the validators, and it can't run inside Codex's sandbox.

`tests/live.sh` runs the real reviewers against throwaway repositories and costs about ten model launches. Run it by hand after changing `reviewer.sh` or how a skill is invoked; `tests/live.sh <section>` runs only the sections named. It is not a routine check.

## Conventions

- Edit the sources here, then run `./install.sh`. Installed copies are overwritten.
- Every skill must work with either harness as the builder.
- A skill's scripts live in its `scripts/` folder, and `SKILL.md` names them as `${CLAUDE_SKILL_DIR}/scripts/<name>`. A script another skill also needs is a symlink to its source, which `install.sh` turns into a copy.
- The scripts run on the bash 3.2 that ships with macOS: no `mapfile`, no associative arrays, and no `"${array[@]}"` on an array that may be empty under `set -u`.
