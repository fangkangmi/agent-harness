# `.claude/` — Local Agent Harness

Project-level configuration for AI coding agents (Claude Code primarily).
Committed to git so the whole team gets the same baseline.

See [`../README.md`](../README.md) for the public-facing overview and
[`../ARCHITECTURE.md`](../ARCHITECTURE.md) for the long-form design doc.

## Layout

| Path | Tracked? | Purpose |
|---|---|---|
| `settings.json` | ✅ committed | Shared team settings — hook wiring, safe permissions. |
| `settings.local.json` | ❌ gitignored | Per-developer permission allowlist. Edit via `/permissions` in Claude Code. See `settings.local.json.example` for the shape. |
| `skills/<name>/SKILL.md` | ✅ committed | Project-level skills (slash commands) for repetitive workflows. |
| `hooks/*.sh` | ✅ committed | Shell scripts wired into `settings.json` hook events. |
| `worktrees/` | ❌ gitignored | Scratch worktrees from agents running with `isolation: "worktree"`. |
| `audits/` | ❌ gitignored | Per-PR audit reports from `spawn-pr-audit.sh`. |

## Skills

Each skill is a directory `skills/<name>/` containing a `SKILL.md`:

```yaml
---
name: <name>
description: When/why to use this skill (the agent reads this to decide)
allowed-tools: Bash, Read, ...
---

# instructions / steps the skill should follow
```

Invoked as `/<name>` in Claude Code. Shipped skills:

- `/check` — pre-PR quality gate: fmt, lint, test, integrity checks. Heavy
  integration tests are deliberately excluded — run them yourself when the
  diff touches their surface area.
- `/new-plan` — scaffold a new `docs/plans/YYYY-MM-DD-<slug>.md` design doc.
- `/new-route` — example "add an HTTP route" recipe. Walks the
  handler → service → contract → snapshot → integration-test loop.
- `/new-registry-entry` — example "registry + store + schema triad" recipe.
  Use whenever a new entry is added on one side of a two-file invariant
  enforced at startup.

## Hooks

Hooks are shell scripts wired into `settings.json` hook events. They get the
tool-call payload as JSON on stdin. Exit `0` allows the call; exit `2` (on
PreToolUse) blocks it and shows stderr to the agent.

Current hooks (most `PreToolUse` on `Bash`; `fmt-on-save.sh` and
`remind-rules.sh` are `PostToolUse` on `Edit`/`Write`):

- `reject-forbidden-footers.sh` — blocks `git commit` invocations whose
  message contains configured forbidden trailers. Shipped example matches
  `Co-Authored-By:` and a "Generated with [Claude Code]" tagline; customize
  for your team's policy.
- `reject-terraform-cli.sh` — example "use the canonical CLI" hook. Blocks
  the bare `terraform` CLI in favor of `tofu` (OpenTofu).
- `reject-unwrap-in-prod.sh` — blocks `Edit`/`Write` that adds `.unwrap()`
  or `.expect(` to non-test Rust production code. Diff-aware (only flags
  *added* lines), `#[cfg(test)]`-aware (walks brace depth), path-exempt for
  `tests/` / `fixtures/` / `benches/` / `examples/` / `build.rs`. Suppress
  per-line with `// allow-unwrap`.
- `force-background-checks.sh` — blocks long-running cargo/make checks not
  passed `run_in_background: true`. Pairs with a usage convention that
  expensive checks never block a conversation turn.
- `suggest-check-script.sh` — soft nudge toward `.claude/scripts/check.sh`
  when the agent runs a full-suite cargo/make invocation directly. Emits
  `additionalContext` JSON; never blocks.
- `spawn-pr-audit.sh` — on `gh pr create` / `gh pr merge` / base-branch
  push, spawns a detached Haiku audit (via `_run-pr-audit.sh` +
  `prompts/pre-merge-audit.md`). Report lands under `.claude/audits/`;
  the hook itself always exits 0 so the push isn't blocked. Replaces what
  would otherwise burn CI minutes.
- `codex-cross-validate-plan-start.sh` — `PreToolUse` on `EnterPlanMode`.
  When the agent enters plan mode, spawns `codex exec` in a detached
  background process to plan the same task in parallel. Returns in <1s;
  the agent's planning starts unblocked. Requires `codex` on PATH.
- `codex-cross-validate-plan.sh` — `PreToolUse` on `ExitPlanMode`.
  Companion to the start hook. Waits up to 120s for the background codex
  run to finish, then denies the first `ExitPlanMode` once with codex's
  plan attached as reconciliation feedback. A per-session one-shot
  marker ensures the second call passes through.
- `fmt-on-save.sh` — auto rustfmt after every `Edit`/`Write` on `.rs`.
  Silent on no-op; emits one line when it reformats.
- `remind-rules.sh` — `PostToolUse` on `Edit`/`Write`. When a configured
  path pattern is edited, prints a compact reminder of the rules that
  apply there. Informational; always exits 0. Edit the script's regex
  for your project's hot spots.

Hooks fail-open on missing `jq` (silently allow) so a half-set-up dev
machine doesn't get blocked from working.

## Testing the hooks

The harness ships with its own test suite. Run from repo root:

```bash
bash .claude/hooks/tests/run-all.sh
```

Layout:

- `tests/_lib.sh` — shared assertions (`assert_blocks`, `assert_allows`,
  `assert_emits_json`, `assert_silent`, `assert_stdout_contains`,
  `report`).
- `tests/test-<hook-name>.sh` — one suite per hook, with positive
  (should-block / should-nudge) and negative (should-allow /
  should-be-silent) cases.
- `tests/run-all.sh` — driver. Loops over `test-*.sh`, prints per-suite
  results, exits non-zero if any suite fails.

When you change a hook, **add a test case to its suite first** — proving
the new behavior works on a fixture is faster than playing whack-a-mole
with false positives in real sessions.

## Adding a new skill or hook

1. **Skill:** create `skills/<name>/SKILL.md` with the frontmatter above.
   Keep it focused — one workflow per skill.
2. **Hook:** drop a script in `hooks/`, `chmod +x` it, then add an entry
   to `settings.json` under the right matcher. **Then write its tests in
   `tests/test-<name>.sh` and confirm `bash tests/run-all.sh` passes
   before committing.**
3. Update this README's "Skills" / "Hooks" lists.
4. PR to share with the team.
