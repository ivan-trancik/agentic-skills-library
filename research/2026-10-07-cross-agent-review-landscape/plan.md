# Implementation plan from the October 2026 research cycle

Derived from [report.md](report.md), whose prioritised list this plan turns into work items. Items are grouped in phases and ordered by value for cost within each phase. Each one says what to change, where, why, and how to check it.

Tags: **Verified** rests on documentation or a measurement on Codex CLI 0.160.1 and Claude Code 2.1.292 on 7 October 2026; **Inference** is reasoning from those facts or from the studies in the report; **Vendor claim** rests on a figure from the party selling or operating a tool. Status boxes: `[ ]` open, `[x]` done, `[-]` dropped, with the reason next to it.

Nothing below changes the design. A reviewer from the other vendor, must-fix findings only, a trend-based stop with a diff budget, a decisions file, a plan that starts from the user's words: the research supports all of it. The plan hardens the mechanics that carry that design.

## Decisions to make first

| Decision | Options | Recommendation |
|---|---|---|
| Claude reviewer context | `--safe-mode` drops CLAUDE.md, skills and MCP servers from the reviewer run; the default keeps them | `--safe-mode`. The reviewer needs the repository, not the user's instruction files, and one measured launch cost about $0.59 of cache creation before the reviewer did anything. |
| Screenshot capture | Tile the headless Chrome output, or move `screenshot.sh` to a Playwright script | Playwright. It also gives clicks, dark mode, device emulation and true full-page capture; tiling alone fixes legibility only. |
| Codex round one | Plain `codex exec` with our prompt, or `codex exec review "<prompt>"`, which keeps Codex's own rubric | Try `codex exec review` on two real tasks and compare the findings before switching. |
| Round cap | Three rounds, the modal practitioner choice, or five as in superpowers | Three, with verify-only first in rounds two and three. |
| Disputed findings | Leave them for the user, or run a fresh third reviewer as referee first | Referee, then the user. It costs one more launch only when a dispute exists. |
| Publishing | Keep the repository private with `install.sh`, or publish it so `npx skills add` and plugin marketplaces work | Decide after Phase 4. |

Decided on 8 October 2026: `--safe-mode` for the Claude reviewer, together with `--restricted` (see 1.1), and a cap of three rounds.

## Phase 1: the reviewer cannot edit, and the launches are correct

### 1.1 Make the Claude reviewer unable to edit `[x]`

- Change: in `skills/review-loop/reviewer.sh`, replace `--allowedTools "Bash,Read,Grep,Glob"` with `--permission-mode dontAsk --permission-prompts none`, allow rules for `Read`, `Grep`, `Glob`, `Bash(git status *)`, `Bash(git diff *)`, `Bash(git log *)`, `Bash(git show *)`, `Bash(mkdir -p .local/scratch*)` and the project's check commands, and `--disallowedTools "Edit" "Write" "NotebookEdit" "mcp__*"`. Keep the fingerprint check as the backstop.
- Why: a bare `Bash` entry approves every shell command, and in `auto` permission mode Claude Code drops it silently. **Verified** in the CLI reference, the permission modes page and the headless page.
- Check: run the reviewer on a scratch repository with a prompt that asks it to edit a file. The edit must be denied and `state.sh` must print the same fingerprint. Then run it on a project whose checks use `npm test` or `pytest` to see whether prefix rules cover the subprocesses they spawn. **Inference** until tested.
- Open question: check commands differ per project. Either the builder writes them to `.local/review-checks` for the script to allow, or the script allows the common runners.
- Done on 8 October 2026, corrected. `dontAsk` still honours the allow rules in user, project and local settings, and `--safe-mode` keeps them, so the reviewer runs with `--restricted`, which ignores every settings file; the script passes on only `model`, `effortLevel` and `modelSettings`. Check commands come from `.local/review-checks`, which the builder writes, and are allowed exactly: a prefix rule such as `Bash(npm test *)` also admits `npm test -- --updateSnapshot`. Read-only git needs no rule, and the scratch-folder rule was dropped, since the reviewer has no tool to write. Plan and design reviews give Claude no shell at all and run Codex `read-only`. The Codex code reviewer still runs `workspace-write` and can edit; the checks can write in either harness; the fingerprint stays the guard for both. `tests/live.sh` confirmed each denial on Claude Code 2.1.294. That version already ignores a project's allow rules until its workspace has been trusted, but the user's own repositories usually have been, and user-level rules apply everywhere.

### 1.2 Harden and cheapen the `claude -p` launch `[x]`

- Change: add `--settings '{"disableAllHooks":true}' --strict-mcp-config --no-session-persistence --max-turns <n> --max-budget-usd <x>`; prefer `--safe-mode` over `--bare`, which never reads OAuth credentials; use `--output-format json` so the builder can read `result`, `permission_denials` and `total_cost_usd`.
- Why: a `-p` session runs the repository's hooks and `.mcp.json` servers with no trust prompt. **Verified** in the permissions and headless pages. The saving from `--safe-mode` is **Inference** until measured.
- Check: review the same diff with and without `--safe-mode` and compare `total_cost_usd` and the findings.
- Done on 8 October 2026: `--restricted --safe-mode --strict-mcp-config --no-session-persistence --max-budget-usd 5 --output-format json`. `--restricted` and `--safe-mode` keep the repository's hooks out in place of `disableAllHooks`. `--max-turns` was left out: reaching it ends the run with an error and no findings. Measured by `tests/live.sh` for a one-word reply in a throwaway repository: $0.007 with these flags, against $0.10 and $0.13 in two runs with the old ones; the research measured $0.59 for the old ones in this repository.

### 1.3 Fix the Codex launch `[x]`

- Change: drop `-c model_reasoning_effort=high` or expose it as an option; make the `-o` path absolute from `git rev-parse --show-toplevel`; move the ten-minute timeout from prose into the script with `perl -e 'alarm shift; exec @ARGV' 600 codex exec ...`, since macOS has no `timeout`; on timeout, resume with `codex exec -o <fresh file> resume <session id> "Reply now with your complete findings" < /dev/null` instead of restarting; tell the prompt that `.git` and the home directory are write-protected in the sandbox, so a denied cache write is not reported as a project bug.
- Why: the user's `~/.codex/config.toml` sets `xhigh`, so `high` lowers the reviewer below the README's promise of the harness default; `workspace-write` denies `.git`, `~/.cache` and the network. **Verified** in the config reference and by a sandbox probe.
- Check: the reviewer log shows the configured effort; a forced timeout resumes and still produces findings.
- Done on 8 October 2026, corrected. The `perl alarm; exec` recipe would stop only the Superset `codex` wrapper, which runs the real binary as a child, so the script runs the reviewer in a process group of its own and stops the whole group. The deadline is 480 seconds plus one resume of at most 90 seconds at `medium` effort, inside the builder's 10-minute command limit; `-s` has to come before `resume`. The `-o` path is absolute, taken from the repository root. Meanwhile the user's default moved to `gpt-6.1-sol` at `ultra`, so the old override had sat further below it.

### 1.4 Evaluate `codex exec review` for round one `[ ]`

Correction, 8 October 2026: `codex exec review -s workspace-write ...` fails on 0.160.1 with "unexpected argument '-s' found". The sandbox flag goes before the subcommand, `codex exec -s workspace-write review ...`; whether the review thread honours it is untested.

- Change: run round one as `codex exec review -s workspace-write -o out.md "<prompt>" < /dev/null`, mapping P0 and P1 to must-fix and P2 and P3 to a "mentioned, not fixed" tail. Keep plain `codex exec` for design reviews: `exec review` has no `--image` and rejects `--worktree`.
- Why: a custom prompt replaces only the user message, so Codex's rubric comes for free: a confidence score per finding, "the author would fix it", "pre-existing bugs should not be flagged", "provably affected". **Verified** flags and rubric text; the mapping of P-levels is **Inference**.
- Check: review the same diff both ways on two tasks and compare findings and false positives.

## Phase 2: loop rules, prompt and ledger

### 2.1 Hard round cap, named exit, verify-only first `[x]`

- Change: in `skills/review-loop/SKILL.md`, cap the loop at three review-fix rounds. Rounds two and three first verify the previous fixes, then look for new must-fix items. The final summary names the exit that fired: clean, count rose, second plateau, diff budget, or round cap.
- Why: gains concentrate in rounds one and two; a second review round added 62% more false positives for little recall; a budget exit looks identical to convergence unless it is named. **Inference** from arXiv 2603.16244 and 2604.10508 and from practitioner caps of two to five rounds.
- Check: the summary of a real loop states its exit; a loop with a large round one ends by round three.
- Done on 8 October 2026, without the second sentence of the change: later rounds already checked only the previous fixes, and "then look for new must-fix items" would have reopened the full review. Under a cap of three, the plateau rule could no longer end the loop before the cap did, so it was folded in: round 2 continues unless the accepted count rose, and round 3 is the last. The exits are clean, count rose, round cap, diff budget, reviewer failed and reviewer changed the work. A caveat on the evidence: the 62% rise in false positives compares multi-turn review with fresh single-pass review, and every round here already runs a fresh reviewer.

### 2.2 Rubric tests, confidence field and verdict line `[x]`

- Change: in `skills/review-loop/reviewer-prompt.md`, add the tests: the bug must be introduced by this change; speculation about other code counts only if that code is provably affected; no unstated assumptions about intent; report only what the author would fix if they knew, and prefer no findings otherwise; one paragraph per finding with code quotes of at most three lines, stating the inputs that trigger the failure. Add a confidence per finding, `confirmed-by-running`, `confirmed-by-reading` or `plausible`, a first line `VERDICT: PASS|NEEDS_CHANGES` with a tally, and the sentence "zero findings is a valid result".
- Why: these are Codex's own rubric tests and Claude Code's verify vote. **Verified** text of both.
- Check: a run on a known-clean diff returns `VERDICT: PASS` and no findings.
- Done on 8 October 2026. The prompt carries the four tests, says that no findings is a valid result, asks for a one-paragraph failure scenario quoting at most three lines, and asks for a confidence per finding. The verdict line became the `verdict` field of 2.3's JSON; a clean round returns `PASS`.

### 2.3 Structured output `[x]`

- Change: use `claude -p --output-format json --json-schema <schema>` and `codex exec --output-schema schema.json` so `review-loop` reads a `must_fix` array mechanically and keeps sub-threshold findings in a summary without reopening them.
- Why: both flags exist. **Verified**. Keeping sub-threshold findings visible is the pattern of Qodo and of Claude Code Review.
- Check: `jq .must_fix` on the output file.
- Done on 8 October 2026. `findings.schema.json` holds `verdict`, `findings`, `below_threshold` (at most five, listed in the final summary and never fixed) and `declined`. `reviewer.sh --schema` passes it as `--json-schema` to Claude and `--output-schema` to Codex, including on a resume, and every run leaves a record of its time and cost. `tests/live.sh` checks that both reviewers report a planted bug in that form.

### 2.4 Refute step and referee `[x]`

- Change: after the reviewer's list, run one more reviewer turn whose only job is to refute each finding by quoting the line that disproves it, and drop refuted items before the builder sees them. Findings the builder still disputes go to a fresh third reviewer run before they reach the user.
- Why: having a fresh model try to refute a result is Anthropic's own guidance; adversarial gates removed about 79% of candidates in one security pipeline; a finding repeated across rounds is not thereby confirmed. **Inference**.
- Check: the log counts refuted items per round and the cost of the extra turn.
- Done on 8 October 2026, refuting only the findings not confirmed by running, by the user's choice. `scripts/refute.sh` sends them to a fresh, read-only run with `refute-prompt.md` and splits the round into kept and refuted findings; if the refute run fails, every finding is kept. A finding the builder still rejects after the reviewer raised it again goes to a fresh run with `referee-prompt.md`, and only an `unclear` verdict reaches the user. `tests/live.sh` checks that each harness refutes a planted false finding and keeps a true one; the log counts refuted findings and adds the extra run's time and cost to the round.

### 2.5 A findings ledger instead of settled choices `[x]`

- Change: `.local/decisions.md` records every finding with an identity by behaviour and cause, a status of `open`, `fixed`, `rejected`, `deferred`, `settled` or `disputed`, the round it came from and the fix that resolved it. Dismissals carry one reason code: `wrong`, `not worth fixing`, `already handled`, `style` or `duplicate`. Choices are written as a ruling with the what, the why and the cost if wrong. The reviewer adds a "Declined to judge" list of behaviours it set aside. Rounds two and three receive the previous findings verbatim with their dispositions.
- Why: practitioner ledgers converged on this shape, and fleet data showed 44% of later findings landing in code the previous fix changed. **Inference**.
- Check: a reworded re-raise matches an existing entry; the final report separates reviewer errors from the other dismissal reasons.
- Done on 8 October 2026. `decisions.md` keeps a "Findings" ledger: one entry per finding with its round, status, file and line, behaviour and cause, and its fix or one of the five dismissal reasons; choices are rulings with the why and the cost if wrong. The reviewer treats a finding with an entry's behaviour as that entry, and its `declined` list goes into the final summary. Later rounds read the ledger rather than a separate copy of the earlier findings.
- Caution: passing the previous findings verbatim moves later rounds towards the multi-turn context that the 62% figure in 2.1 measured against, so log whether it raises the false positives.

### 2.6 Protect the tests in fix rounds `[x]`

- Change: in later rounds the reviewer diffs the test files first; the changed-file list comes from git, never from the builder's report; optionally a WIP commit per round, squashed at the end, so each review has a stable revision.
- Why: builders measurably weaken tests under pressure, and read-only tests stopped that without hurting honest work. **Inference**.
- Check: weaken a test deliberately in a fixture repository; the reviewer flags it.
- Done on 8 October 2026, with git tree snapshots in place of WIP commits. `state.sh`'s fingerprint is a tree of the whole work, untracked files included, written through a copy of the index, so history and the real index stay as they are. "Fixes to check" names the trees from before and after the fixes; the reviewer reads `git diff <before> <after>` and looks at changed tests first. A submodule's own work enters the snapshot as its own tree, so edits and symlinks inside it count, and a submodule that can't be snapshotted stops the loop rather than reading as unchanged. `tests/live.sh` checks that both reviewers flag a test a fix loosened while the checks still pass.

### 2.7 Right-size the ceremony `[x]`

- Change: in `instructions/how-to-work-on-a-task.md`, add a sizing step: if the diff can be described in one sentence, skip the plan and the plan review; cross-review stays for everything that changes behaviour. At the end of the loop, check the diff against `.local/plan.md`.
- Why: vendor guidance and practitioner cost complaints; planning is a cost saver rather than an accuracy gain for strong models, and a subpar plan hurts more than none, which is the argument for keeping plan review wherever a plan exists. **Vendor claim and practice**.
- Check: a one-line fix goes straight to build and the review loop.
- Done on 8 October 2026, by the user's choice: step 1 of the instruction block skips the plan and its review when the whole change fits in one sentence, and the loop's summary lists where the work differs from `.local/plan.md`.

## Phase 3: design review pipeline

### 3.1 Fix the capture before tuning the prompt `[x]`

- Change: tile the full-page capture into slices of at most 1568 px, or replace `screenshot.sh` with a Playwright script that gives `fullPage`, device descriptors, `emulateMedia({colorScheme:'dark'})` and `animations:'disabled'`. Add a 768 px pass, a dark-mode capture and a Tab-press focus capture. Label images in file-list order.
- Why: Anthropic's documented resize rule shrinks 1440x4000 to about 564x1568 on standard-tier models, so 16 px text lands at about 6 px. **Verified** rule; the figure is computed from it.
- Check: text in every delivered image is still legible after the vendor's resize.
- Done on 9 October 2026 with Playwright 1.63.0, through `npx`, driving the installed Chrome. `screenshot.sh` runs `capture.cjs` in one browser session after the network goes quiet and with animations off: desktop at 1440 x 900, the whole page cut into 900-pixel tiles with `sips` (at most twelve, and the part no tile covers is named), tablet at 768 x 1024, phone as a Pixel 7 (the iPhone profiles need WebKit), dark mode, and the page after one Tab press, naming the focused element. `shots.txt` lists the images in order with what each shows. Every image is at most 1440 x 900 apart from the phone's, so text stays legible after either vendor's resize. Clicked states are still the builder's own browser tools.

### 3.2 Delivery check and stated counts `[x]`

- Change: include a canary image with a random word that the reviewer must transcribe first. Have the builder state the expected counts and the states not captured in `.local/design-context.md`. Change the prompt from "count it" to "verify the stated count".
- Why: one issue reports total fabrication of image content in `-p` mode when the image data did not arrive; both vendors document weak counting and small-text reading. **Verified** issue report and vendor limitations.
- Check: remove the canary file and confirm the reviewer reports it missing instead of describing it.
- Done on 9 October 2026. `canary.png` shows a random dictionary word; only its hash is kept, and `screenshot.sh --check` confirms the review names it before the builder uses the review. `design-context.md` states the expected counts and the states not shown, and the prompt checks stated counts rather than counting. `tests/check.sh` tests the canary check, and `tests/live.sh` checks that both reviewers read the canary.

### 3.3 Objective checks `[x]`

- Change: run `@axe-core/playwright` for contrast, labels and focus; optionally a same-session `pixelmatch` on pages the task did not touch and an accessibility-snapshot text diff for "information no longer reachable". Feed the results to the reviewer with the rule "problems over prescriptions".
- Why: structured inputs lift vision-model accuracy sharply on exactly the defects the prompt asks about. **Inference**; the tooling facts are **Verified**.
- Check: a deliberately low-contrast button is caught by axe and relayed by the reviewer.
- Done on 9 October 2026 with Lighthouse 13.5.0's accessibility audit, which runs axe, through `npx`: `a11y.sh` writes the failing checks and their elements to `a11y.txt`, and the prompt passes on those that make content unreadable or unreachable or that a goal covers, describing problems rather than fixes. `tests/live.sh` checks that it reports a low-contrast button, and that both reviewers flag a focused button with no visible mark. Not done: pixel diffs of untouched pages and accessibility-tree diffs, which were optional; they need Playwright installed in each project, and pixel diffs are noisy between runs.

## Phase 4: skill hygiene, installer and distribution

### 4.1 Make `ship` explicit-only `[x]`

- Change: add `disable-model-invocation: true` to `skills/ship/SKILL.md`; add `skills/ship/agents/openai.yaml` with `policy: allow_implicit_invocation: false`; optionally a PreToolUse hook that denies a force-push to the default branch. Note in the README that this departs from OpenAI's advice not to infer explicit-only invocation from sensitivity.
- Why: both mechanisms are documented, and Codex's bundled `review-agent` skill uses the same policy. **Verified**.
- Check: `claude -p "ship this"` does not load the skill while `/ship` does; in Codex, `$ship` works and the skill is absent from the implicit list.
- Done on 8 October 2026, without the hook. `tests/live.sh` checks a renamed probe copy in both harnesses: a request to ship doesn't load it, and calling it by name does. The instruction block tells the agent to ask for `/ship` or `$ship` when the user asks to ship in other words.
- The optional force-push hook was left out by the user's decision on 8 October 2026: `ship` never forces a push, and a global hook would change every project's settings.

### 4.2 Relative script paths and no cross-skill dependency `[x]`

- Change: move helpers under `scripts/` and refer to them relative to the skill root, using `${CLAUDE_SKILL_DIR}` in Claude Code. Give `review-plan` and `review-design` their own copy of the runner, or a shared runner skill they call by name. Add `metadata` with a version and source to each `SKILL.md`.
- Why: the Agent Skills specification and both vendors say relative paths; the hard-coded `~/.agents/skills/...` breaks project-scope installs and plugin packaging. **Verified** guidance; the breakage is **Inference**.
- Check: install the skills into a project's `.agents/skills` folder and run a review from there.
- Done on 8 October 2026 with one source for the runner: `review-plan` and `review-design` hold symlinks to `review-loop/scripts/reviewer.sh`, and `install.sh` copies with `cp -RL`, so each installed skill holds a file of its own. Each `SKILL.md` names its scripts as `${CLAUDE_SKILL_DIR}/scripts/<name>`, after a line that tells Codex what that stands for. `tests/live.sh` checks, with a probe skill installed in a project's `.agents/skills` and `.claude/skills`, that both harnesses run a script named that way. Not done: `metadata` with a version and source, because the installer's marker records the commit and a hand-bumped version would drift.

### 4.3 Installer checks and validators `[x]`

- Change: add `install.sh --check` to compare installed copies with the repository; warn when `~/.codex/skills/<name>` exists; record the source commit in the marker; run `skills-ref validate`, `claude plugin validate` and Codex's `quick_validate.py` from a check script. Avoid the `compatibility` key while Codex's validator rejects it.
- Why: Codex still scans `~/.codex/skills`, so a same-name skill there shadows the installed one, and the validators disagree on allowed keys. **Verified** by probe and docs.
- Check: a duplicate in `~/.codex/skills` produces a warning; all validators pass.
- Done on 8 October 2026. The marker names the commit. `install.sh --check` reports each installed skill and instruction block as current, changed or missing, and notes a CLI version that differs from `research/verified-versions`; install and `--check` warn about a same-named skill in `~/.codex/skills`. `tests/check.sh` tests all of it against a fake home. The validators run from `tests/validate.sh` through `uv`, pinned at `skills-ref` 0.1.1 and `pyyaml` 6.0.3, on copies without `disable-model-invocation`, which both reject although Codex's runtime accepts it. They need a download on first use and can't run inside Codex's sandbox, where `uv` can't open its cache, so they stay out of `tests/check.sh`.

### 4.4 Give this repository the checks it asks of others `[x]`

- Change: add an `AGENTS.md` with the checks: `bash -n` and `shellcheck` on the scripts, the validators from 4.3, and a smoke test that runs `reviewer.sh` against a fixture repository.
- Why: the skills take "the project's checks" from `AGENTS.md`, and this repository has none, so its own review loops run unchecked.
- Check: the review loop on this repository runs the checks.
- Done on 8 October 2026, first rather than last, so that every later change runs the checks, and split in two. `tests/check.sh` is free and offline: syntax, `shellcheck`, `claude plugin validate skills`, and tests of `reviewer.sh` and `state.sh` against stub CLIs. `tests/live.sh` runs the real reviewers and costs about ten launches, so it is run by hand: the loop runs the checks several times per round. Codex's `quick_validate.py` needs PyYAML, which isn't installed, so it isn't run yet.

### 4.5 A second install path `[-]`

- Change: when the repository is public, keep the `skills/<name>/SKILL.md` layout so `npx skills add <owner>/agentic-skills-library` works, and optionally add plugin manifests for both harnesses. On the Claude side the instruction block can become an `@~/.agents/instructions/how-to-work-on-a-task.md` import; Codex keeps the verbatim copy, since it has no import syntax.
- Why: the Vercel `skills` CLI uses the same canonical `.agents/skills` plus symlink layout as `install.sh`, and adds a lockfile and an update check. **Verified**.
- Check: a fresh machine installs by either path and both harnesses list the skills.
- Dropped on 8 October 2026 by the user's decision: the repository stays private and `install.sh` is the install path. The `skills/<name>/SKILL.md` layout already suits `npx skills add` if it is published later.

## Phase 5: instrumentation and cadence

### 5.1 Log every round `[x]`

- Change: append one line per round to `.local/loop-log.jsonl`: findings reported, accepted, rejected, disputed and refuted; whether each finding lies in code the previous fix changed; the `lines` value; wall time; cost from the JSON output. Keep the logs across sessions.
- Why: the same class of tool lands anywhere between 7% and 75% acceptance depending on policy, and no controlled study of Claude reviewing Codex or the reverse on real repositories exists. **Inference**.
- Check: after ten loops the logs answer how many rounds ran, how much was accepted, and how often the cap fired.
- Done on 8 October 2026. `scripts/log-round.sh` appends a line per round to `~/.local/state/agentic-skills-library/review-loop.jsonl`, outside the workspace: the counts, the findings in lines the previous fixes changed (from the snapshots' diff hunks), the size of the work, the exit, and the time, cost and tokens summed from the round's run records. The README shows `jq` lines that summarise it.

### 5.2 Research cadence `[x]`

- Change: run a cycle as described in `research/README.md` each quarter, or when either CLI changes its minor version. Consider a `research-cycle` skill that scaffolds the folder and the thread prompts.
- Check: the cycles table in `research/README.md` grows.
- Done on 8 October 2026: `research/README.md` sets a quarterly cycle, `tests/live.sh` records the CLI versions it passed on, and `install.sh --check` says when the installed CLIs have moved past them. No `research-cycle` skill, so the library stays at six skills.

## Not planned, and why

- Moving from CLI-to-CLI to MCP bridges: `codex mcp-server` was removed, and `claude mcp serve` exposes tools rather than a reviewing model. **Verified**.
- Hosted visual regression services: they add accounts and uploads to a local two-agent loop, and one of them, Lost Pixel, was archived in April 2026.
- Letting the loop push or merge: every surveyed library hands the merge to the human, and `ship` stays explicit.
