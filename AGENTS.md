# Agentic skills library

Skills for coding agents, shared by Claude Code and Codex. `README.md` says what each skill does and how they are installed.

## Checks

Run `tests/check.sh`. It is free, offline and takes seconds: `bash -n` and `shellcheck` on every script, `claude plugin validate skills`, and tests that run `reviewer.sh` and `state.sh` against the stub `codex` and `claude` commands in `tests/stubs/`. It needs `shellcheck` and `jq`.

`tests/live.sh` runs the real reviewers against throwaway repositories and costs about ten model launches. Run it by hand after changing `reviewer.sh` or a skill's invocation settings. It is not a routine check.

## Conventions

- Edit the sources here, then run `./install.sh`. Installed copies are overwritten.
- Every skill must work with either harness as the builder.
- The scripts run on the bash 3.2 that ships with macOS: no `mapfile`, no associative arrays, and no `"${array[@]}"` on an array that may be empty under `set -u`.
