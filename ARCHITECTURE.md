# Architecture

`.claude/` is a project-level harness that turns Claude Code (and compatible agents) from a generic coding assistant into a project-aware contributor. It is committed to git so every developer on the team gets the same enforcement baseline, the same scaffolding skills, and the same pre-merge audit pipeline without per-machine setup.

The harness has six concerns:

1. **Enforcement** — pre/post tool-call shell hooks that block, nudge, or auto-format.
2. **Scaffolding** — slash-command skills that codify the project's "how to add X" recipes.
3. **Cost-aware quality gates** — a runner that compresses verbose output via a cheap model so it never blows the conversation context.
4. **Background pre-merge audits** — detached audit jobs spawned on PR-lifecycle commands, replacing what would otherwise be CI minutes.
5. **Parallel plan-mode cross-validation** — a second agent (`codex exec`) plans the same task in the background; on exit-plan-mode the agent reconciles both plans before proceeding.
6. **Self-testing** — a shell-based test suite for the hooks themselves, so harness changes can't silently regress.

```
.claude/
├── README.md                       # human-facing layout + onboarding
├── settings.json                   # committed: shared hook wiring
├── settings.local.json.example     # template: per-dev permission allowlist
├── .gitignore                      # excludes audits/, worktrees/, settings.local.json
│
├── hooks/                          # shell + python tool-call interceptors
│   ├── reject-forbidden-footers.sh # PreToolUse Bash — block forbidden git commit-message trailers
│   ├── reject-terraform-cli.sh     # PreToolUse Bash — example "use canonical CLI" rule (tofu, not terraform)
│   ├── reject-unwrap-in-prod.sh    # PreToolUse Edit|Write — block new .unwrap()/.expect() in Rust prod paths
│   ├── force-background-checks.sh  # PreToolUse Bash — force long cargo cmds to background mode
│   ├── suggest-check-script.sh     # PreToolUse Bash — nudge toward the compressed /check runner
│   ├── spawn-pr-audit.sh           # PreToolUse Bash — detach a Haiku audit on PR-lifecycle commands
│   ├── _run-pr-audit.sh            # background worker (not a hook entry point)
│   ├── codex-cross-validate-plan-start.sh # PreToolUse EnterPlanMode — spawn parallel codex planner
│   ├── codex-cross-validate-plan.sh       # PreToolUse ExitPlanMode  — wait for codex, deny once with its plan
│   ├── fmt-on-save.sh              # PostToolUse Edit|Write — auto rustfmt
│   ├── remind-rules.sh             # PostToolUse Edit|Write — print configurable per-pattern reminder
│   └── tests/                      # hook test suite
│       ├── _lib.sh                 # assertion helpers
│       ├── run-all.sh              # driver — exits non-zero on any failure
│       └── test-*.sh               # one suite per hook
│
├── skills/                         # slash commands as agent-readable docs
│   ├── check/SKILL.md              # /check — pre-PR quality gate
│   ├── new-plan/SKILL.md           # /new-plan — scaffold docs/plans/<date>-<slug>.md
│   ├── new-route/SKILL.md          # /new-route — example "add an HTTP route" recipe
│   └── new-registry-entry/SKILL.md # /new-registry-entry — registry+store+schema triad pattern
│
├── scripts/
│   └── check.sh                    # the runner /check invokes
│
├── prompts/
│   └── pre-merge-audit.md          # illustrative 6-check audit prompt (customize for your stack)
│
├── audits/                         # gitignored: pre-merge audit reports
└── worktrees/                      # gitignored: agents running with isolation:"worktree"
```

---

## 1. Enforcement layer — tool-call hooks

Hooks are shell or Python scripts wired into Claude Code's `PreToolUse` and `PostToolUse` events via `settings.json`. The agent's tool-call payload arrives on stdin as JSON; the hook decides allow / block / annotate by exit code and stderr.

| Exit code | Effect |
|-----------|--------|
| `0` | Allow the tool call. Anything emitted via `hookSpecificOutput.additionalContext` JSON becomes a system reminder injected on the next agent turn. |
| `2` (PreToolUse only) | Block the tool call. Stderr is shown to the agent so it can correct itself. |

Two design rules apply to every hook in the harness:

- **Fail-open on missing dependencies.** Every hook starts with `command -v jq >/dev/null 2>&1 || exit 0`. A half-set-up dev machine should be able to work; the hook is a safety net, not a hard dependency.
- **Match canonical forms, not substrings.** The hooks regex against trailer formats (`^[[:space:]]*Co-Authored-By:`) and CLI-shaped tokens (`terraform[[:space:]]+(init|plan|apply|...)`), not bare words — so a commit message that *explains* a policy doesn't trigger the policy itself.

### Pre-tool-use blockers (Bash matcher)

- **`reject-forbidden-footers.sh`** — blocks `git commit` when the message contains configured forbidden trailers (the shipped example matches `Co-Authored-By:` and a "Generated with [Claude Code]" tagline; customize the regex for your team's policy). Matches canonical trailer form at line start, not substring mentions.
- **`reject-terraform-cli.sh`** — an example "use the canonical CLI" hook. Blocks the bare `terraform` CLI in favor of `tofu` (OpenTofu) — a known team-policy pattern. Skips commit-message prose. Uses an explicit allowlist of subcommands (`init|plan|apply|destroy|fmt|validate|state|...`) so paths like `terraform-application/` and `terraform-docs` don't false-positive. Fork the structure for whichever CLI pair matters in your stack.
- **`force-background-checks.sh`** — blocks any `cargo check / test / clippy`, `make check / test`, or `scripts/check.sh` invocation that wasn't passed `run_in_background: true`. The agent gets an instruction to retry with the flag. Pairs with the general rule that long-running checks should never block the conversation turn — the agent gets notified when the background command finishes.

### Pre-tool-use blocker (Edit|Write matcher)

- **`reject-unwrap-in-prod.sh`** — the only Python hook in the harness, because of what it has to do. It synthesizes the post-edit content, runs a `difflib.SequenceMatcher` diff against the pre-edit content, and flags only **added** lines that contain `.unwrap()` or `.expect(` *and* fall outside a `#[cfg(test)] mod NAME { ... }` block (brace-depth tracked through the file). Two exemption layers:
  - **By path:** `tests/`, `*_test.rs`, `_tests.rs`, `fixtures/`, `benches/`, `examples/`, `build.rs`.
  - **By context:** any `#[cfg(test)]` module, walked structurally rather than greppily.
  - Explicit suppression: `// allow-unwrap` on the same line for provably-infallible cases (parsing a compile-time const, unwrap after a bounds check, etc.).

  This is a good example of the harness's "structural over textual" preference — a naive grep would either false-positive on test code or false-negative on cfg-gated production modules; the diff-aware design catches only true regressions.

### Pre-tool-use nudges (Bash matcher, fail-soft)

- **`suggest-check-script.sh`** — when the agent invokes a full-suite cargo command directly (`cargo clippy --workspace`, `make test`), exits `0` but emits `additionalContext` JSON pointing at `.claude/scripts/check.sh`. The script wraps the same gates but compresses the output via a cheap model before returning it to context. Soft nudge — the agent can still run raw cargo when it specifically needs unfiltered output.

### Post-tool-use hooks (Edit|Write matcher)

- **`fmt-on-save.sh`** — runs `rustfmt --check`; if it would reformat, applies `rustfmt` and prints one line so the agent knows the file changed under it. Silent on no-op.
- **`remind-rules.sh`** — when an edit touches a path matching a configured regex (e.g. files in a particular subsystem, schema-defining structs, or a registry index), prints a compact reminder of the rules that apply there. Counteracts long-session drift on rules that show up explicitly in CLAUDE.md but might fade from the agent's working memory across hundreds of turns.

### Spawn hook — the pre-merge audit pipeline

`spawn-pr-audit.sh` is the most architecturally interesting hook. It fires on PR-lifecycle commands (`gh pr create`, `gh pr merge`, `git push origin {develop,release,main}`) and spawns a fully detached Claude Haiku audit, then exits `0` immediately so the developer's push is never blocked.

Mechanics:

1. **Trigger gate** — narrow case-statement match. `gh pr list` doesn't fire; pushing a feature branch doesn't fire.
2. **Per-branch lock** — `.claude/.audit-lock-<branch_slug>` holding a PID. If a previous audit on the same branch is still alive (`kill -0`), the new request short-circuits with an `additionalContext` note pointing at the existing run; stale locks are reaped on PID-not-found.
3. **Diff range resolution** — walks an ordered candidate list (`origin/develop` → `develop` → `origin/main` → `main`), picks the first that exists, computes `git merge-base HEAD <ref>`. Robust to repos that develop off `develop` and to forks that only have `main`.
4. **Cheap path-filter** — bails out unless the changed files match a configured set of "interesting" paths (the shipped example matches Rust source under a few crate directories and an OpenAPI spec file). No point auditing a docs-only diff.
5. **Detach** — `setsid nohup "$RUNNER" </dev/null >/dev/null 2>&1 &`, write child PID to the lock, `disown`. The runner is responsible for clearing the lock on EXIT/INT/TERM via a trap, so even SIGKILL of the parent shell can't wedge future audits.
6. **Report path** — `.claude/audits/pre-merge-<branch_slug>-<ts>.md`. The hook tells the agent the relative path via `additionalContext` so the next conversation turn can read it before merging.

The worker (`_run-pr-audit.sh`) pre-computes the diff context (changed-files list + diff-stat) and appends it to the audit prompt as a precomputed fenced block, rather than letting the model re-shell out for `git` info. Saves tool calls; keeps the audit deterministic.

The audit itself (`prompts/pre-merge-audit.md`) is a single-shot static auditor with six illustrative checks. Each check is grounded in a project-specific rule with a concrete grep recipe so the cheap model doesn't have to invent its analysis. The shipped checks are templates you should fork — what matters is the shape:

1. **Contract drift** — every added/modified route declaration in a service must appear in the corresponding API contract file (the shipped example uses an OpenAPI spec), with parameter-syntax normalization between the two formats, and the inverse (paths removed from source still in spec).
2. **Telemetry trace-ID propagation** — when an instrumented client call returns a result-plus-trace-IDs bundle and the result is persisted, the trace IDs must be persisted alongside it. Otherwise downstream observability tooling can't correlate the persisted entity back to the original call. Pure structural check on a specific result type.
3. **Two-file coupling** — when a schema-defining struct gains or loses fields, the corresponding contract/spec file should change in the same diff. Advisory (renames are legitimate); flags missed updates for reviewer confirmation.
4. **No hardcoded config in source** — any inline model name, temperature literal, or environment variable that belongs in a centralized config spec is flagged outside a single allowlisted file. The "config lives in a spec, source code reads from it" rule.
5. **Shared-wrapper bypass** — flag raw HTTP client usage (`reqwest::Client::new()...post(...)`, direct SDK calls) where a shared traced wrapper exists. Catches the failure mode where someone copies an example from documentation and skips the observability layer.
6. **Registry ↔ store consistency** — when one side of a two-file pattern gains, renames, or loses an entry, the other side must change in lockstep. Either side missing is a runtime fatal at startup; the audit catches it before merge instead of waiting for the deploy to fail.

Output is hard-capped at 600 words across all six sections. The audit is read by a human (or by the agent in a future turn) before clicking merge. Cost: roughly $0.01–0.03 per run on Haiku — meaningfully cheaper than the equivalent CI job, and lands seconds after the push rather than at the end of a queue.

### Parallel plan-mode cross-validation

A separate pair of hooks (`codex-cross-validate-plan-start.sh` on `EnterPlanMode`, `codex-cross-validate-plan.sh` on `ExitPlanMode`) implements a parallel-planning pattern with a second AI agent — the example uses [Codex CLI](https://github.com/openai/codex), but the pattern works for any read-only CLI agent that can be invoked headlessly.

Lifecycle:

1. **Enter plan mode** — `codex-cross-validate-plan-start.sh` reads the most recent user message from the transcript (the task to plan), kicks off `codex exec --sandbox read-only` in a detached `nohup` background process, and writes its PID + stdout/stderr destinations to a per-session state directory (`$TMPDIR/claude-codex-plan/<session_id>.*`). Returns in well under a second; the agent's planning starts unblocked. Codex usually takes 30–90 seconds.
2. **Exit plan mode** — `codex-cross-validate-plan.sh` checks for a per-session "already consulted" marker; if present, exits 0 and the plan goes through. Otherwise it `kill -0`-polls the codex PID with a 120-second cap. Once codex finishes (or the cap expires), it returns a `permissionDecision: "deny"` with codex's full plan + reconciliation guidance attached via `permissionDecisionReason`. The agent reads both plans, reconciles, and re-calls `ExitPlanMode`; the second call sees the marker and passes through.
3. **Fail-open** — if codex isn't installed, or the transcript path is missing, or the codex run produces empty output, the hooks log a stderr note and exit 0 so the user is never trapped in plan mode.

The one-shot marker is load-bearing. Without it the cross-validation would loop forever; with it, the second-opinion injection happens exactly once per plan-mode session even if the agent re-enters plan mode later. The pattern generalizes to any "consult a second source before committing to an irreversible decision" workflow — the deny-with-context-then-allow-on-retry shape is the reusable part.

---

## 2. Scaffolding layer — skills as recipes

Each skill is a directory `skills/<name>/SKILL.md` with YAML frontmatter (`name`, `description`, `allowed-tools`). The description tells Claude *when* to invoke the skill; the body tells it *how*. Skills are not code — they're agent-readable runbooks committed alongside the project, encoding the same patterns a senior engineer would coach a new hire through.

The four shipped skills correspond to the workflow shapes that come up often enough to be worth codifying:

| Skill | Purpose |
|-------|---------|
| `/check` | Run the full pre-PR quality gate via `.claude/scripts/check.sh` — fmt, lint, test, and project-specific integrity checks. Reports a one-line summary. Deliberately excludes integration tests (they need external services up). |
| `/new-plan` | Scaffold `docs/plans/<date>-<slug>.md`, mirroring the team's section structure (Problem / Goal / Non-goals / Design / Milestones / Risks / Test plan / Rollout). Stops after creating the file so the user can review before implementation. |
| `/new-route` | Walk through an example "add an HTTP route" recipe: handler → service → repository call → route wiring → API contract update → snapshot test → integration test stub → local sanity check. Stops at step 1 if the change is non-trivial and prompts for a `/new-plan` instead. |
| `/new-registry-entry` | Walk through a "registry + store + schema triad" pattern: add the source-of-truth store file, register it in a runtime inventory list, and (if structured output is involved) map it in a schema registry. Encodes the rule that the canonical source location is the store file, not Rust source. |

Skills carry institutional knowledge that isn't obvious from reading the code:

- `/check` documents *why* integration tests are intentionally excluded (they need Docker / local infra up; bundling them would either fail cold or silently skip).
- `/new-route` documents the test-fixture pyramid so agents pick the cheapest level that still covers the route.
- `/new-registry-entry` documents which file is the source-of-truth dev-authoring location for config values that are otherwise forbidden in source code (the YAML store, not the Rust struct that consumes it).

---

## 3. Cost-aware quality gate — `scripts/check.sh`

`check.sh` runs the project's quality gates in order, *continuing through failures* so the developer gets one report instead of N sequential errors:

1. `cargo fmt --check`
2. `cargo clippy --workspace --all-targets -- -D warnings`
3. `make test` (or equivalent test entry point)
4. Project-specific integrity checks (e.g., a registry ↔ store consistency check)

Verbose output is the design problem. A failing clippy run on a non-trivial workspace can be 500+ lines of compiler diagnostics; dumping that into the agent's context window evicts something more important. The script's `compress` helper handles it:

- If output is ≤ 25 lines, pass through verbatim.
- Otherwise, pipe the first 120 lines through `claude -p` with a Haiku model and a prompt that says: list only actionable issues as `• file:line — what to fix`, skip boilerplate, under 80 words.
- If the model call is unavailable or fails, fall back to raw output. Never silently drop information.

The result is that a failed gate prints something like:

```
[FAIL] clippy:
• crates/<service>/src/handlers.rs:142 — unused variable `ctx`
• crates/<other>/src/lib.rs:88 — needless borrow
```

…instead of the verbatim compiler output. The agent gets enough to fix the issue in one turn, and the context budget is preserved for the next ten turns of work.

---

## 4. Self-testing the harness

Hooks are easy to write and hard to keep correct. Pattern matchers go through tightening rounds after false positives block legitimate work. The harness therefore ships its own test suite under `hooks/tests/`.

Layout:

- `_lib.sh` — shared assertion helpers: `assert_blocks`, `assert_allows`, `assert_emits_json`, `assert_silent`, `assert_stdout_contains`, plus a `report` function for per-suite pass/fail counts.
- `test-<hook-name>.sh` — one suite per hook. Each suite drives the hook by piping a synthetic tool-call payload to stdin and asserting against exit code + stderr + stdout. Positive cases (should-block / should-nudge) and negative cases (should-allow / should-be-silent) are both required.
- `run-all.sh` — driver. Loops over `test-*.sh`, prints per-suite results, exits non-zero if any suite fails.

The rule: when changing a hook, add a test case to its suite first. Proving the new behavior on a fixture is faster than playing whack-a-mole with false positives in real sessions.

---

## 5. Settings and gitignore boundaries

- `settings.json` (committed) — the wiring layer. Maps `PreToolUse: Bash` and `PreToolUse: Edit|Write` matchers to the relevant hook scripts; same for `PostToolUse`. Uses `$CLAUDE_PROJECT_DIR` so paths resolve from the repo root, not whatever subdirectory the agent happens to be running from.
- `settings.local.json` (gitignored, with an `.example` template committed) — per-developer permission allowlist edited via `/permissions` in Claude Code. Personal preferences (e.g. "always allow `gh pr view`"); never team-wide.
- `audits/` (gitignored) — disposable per-PR snapshots; never committed.
- `worktrees/` (gitignored) — scratch git worktrees from agents running with `isolation: "worktree"`. Lives under `.claude/` so it's discoverable, but kept out of git.

---

## Design philosophy

A few principles run through the harness, useful for anyone reviewing or extending it:

- **Fail-open over fail-closed.** Every hook checks for `jq` / `rustfmt` / `claude` and silently exits 0 if missing. A misconfigured dev machine is annoying; a misconfigured dev machine that *also blocks the developer from working* is rage-inducing.
- **Structural over textual.** The `.unwrap()` blocker diffs Rust source to find *added* lines; the audit normalizes route parameters between source and contract; the terraform blocker uses a subcommand allowlist rather than a substring match. Wherever a textual approach has obvious false-positive cases, the harness invests in a structural one.
- **Nudge before block.** `suggest-check-script.sh` and `remind-rules.sh` are informational. The hard blockers (`reject-*.sh`, `force-background-checks.sh`) only exist for rules with an unambiguous canonical form (commit policy, canonical-CLI rules, no panics in prod).
- **Test-the-tools.** The hook test suite is required before merging a hook change. The harness eats its own dog food on the same "tests-as-contract" principle it enforces on the rest of the codebase.
- **Money awareness.** The `check.sh` output compression and the audit's 600-word output cap are explicitly about preserving the agent's context budget. The pre-merge audit running on Haiku locally (~$0.01–0.03 per run) instead of CI minutes is the same instinct one tier up.
- **Don't lock the team in.** Skills and hooks are committed; per-developer permissions and scratch worktrees are gitignored. The harness expresses a baseline, not a straitjacket.
