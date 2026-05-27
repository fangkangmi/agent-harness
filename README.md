# agent-harness

> Built by [Fang](https://github.com/fangkangmi) — contact via GitHub or [LinkedIn](https://www.linkedin.com/in/fangkangmi).

A project-level harness for AI coding agents (built around Claude Code, but the patterns generalize) that adds enforcement, scaffolding, cost-aware quality gates, background audits, parallel plan-mode cross-validation, and a self-testing layer to any codebase. This is a sanitized public template distilled from a private working harness used team-wide on a Rust + AWS Lambda backend; domain specifics have been stripped, the structural patterns are kept intact.

## What's inside

- **Enforcement** — pre/post tool-call shell hooks that block forbidden commit footers, prevent panics in production paths, auto-format on save, and force long-running checks into the background. See [`.claude/hooks/`](.claude/hooks).
- **Scaffolding** — slash-command skills that codify a project's "how to add X" recipes as agent-readable runbooks. See [`.claude/skills/`](.claude/skills).
- **Cost-aware quality gates** — a runner that compresses verbose tool output via a cheap model before it lands in the conversation context. See [`.claude/scripts/check.sh`](.claude/scripts/check.sh).
- **Background pre-merge audits** — detached Claude Haiku audits spawned on PR-lifecycle commands, replacing CI minutes with a few cents of model calls. See [`.claude/hooks/spawn-pr-audit.sh`](.claude/hooks/spawn-pr-audit.sh) and [`.claude/prompts/pre-merge-audit.md`](.claude/prompts/pre-merge-audit.md).
- **Multi-agent cross-validation** — exploits the price gap between Claude and Codex by running them as independent reviewers of each other. `EnterPlanMode` spawns a background `codex exec` planning the same task; `ExitPlanMode` waits for it and feeds the independent plan back as a one-shot deny so the primary agent must reconcile before proceeding. Code-review uses the same separation-of-concerns principle: the implementer agent never reviews its own output — a Codex pass and a subagent pass review independently. See [`.claude/hooks/codex-cross-validate-plan-start.sh`](.claude/hooks/codex-cross-validate-plan-start.sh).
- **Self-testing** — a shell-based test suite for the hooks themselves, so harness changes can't silently regress. See [`.claude/hooks/tests/`](.claude/hooks/tests).

## Why this exists

AI-assisted development surfaces four problems at once in any non-trivial codebase. Context drift: rules in long-form docs (CLAUDE.md, AGENTS.md, READMEs) fade across hundreds of agent turns. Hard-to-audit agent actions: commits, PRs, and base-branch pushes happen without a separate review pass. Cost blowups: verbose compiler or test output dumped into the conversation context evicts something more important and inflates token use. And the absence of team-level policy enforcement beyond hope and code review.

This harness addresses all four. Hooks enforce policy at the tool-call boundary; skills re-state recipes at the moment they apply; a compressing runner protects context budgets; and a detached audit checks each PR-bound diff against repo-specific contracts before merge.

## Design principles

- **Fail-open over fail-closed.** Hooks silently exit 0 on missing dependencies — a misconfigured dev machine should never block a developer from working.
- **Structural over textual.** Pattern matchers normalize, allowlist subcommands, or diff before flagging; wherever a textual approach has obvious false-positive cases, the harness invests in a structural one.
- **Nudge before block.** Hard blockers exist only for rules with an unambiguous canonical form; everything else is an informational reminder via `additionalContext` JSON.
- **Test-the-tools.** Hook changes require a test case in the bundled suite before merging — the harness eats its own dog food.
- **Money awareness.** Output compression, audit word caps, and running expensive checks on a cheaper model locally instead of in CI are deliberate choices to preserve both context budget and dollars.
- **Don't lock the team in.** Skills and hooks are committed; per-developer permissions and scratch worktrees are gitignored. The harness expresses a baseline, not a straitjacket.
- **Separation of concerns across agents.** The implementer never reviews its own work. Plans, reviews, and audits are routed to an independent model — usually a cheaper one — so the harness gets a second opinion without doubling the primary agent's cost.

## How to adopt

1. Clone or copy this repo's `.claude/` directory into your own project's root.
2. Edit `.claude/settings.json` if your layout differs — the wiring uses `$CLAUDE_PROJECT_DIR` so the defaults work for most repos.
3. Run `bash .claude/hooks/tests/run-all.sh` to verify the harness is healthy on your machine.
4. Customize the example domain rule in `.claude/prompts/pre-merge-audit.md` — the six checks that ship are illustrative; the structure is the reusable part.
5. Commit, PR, and your team picks up the same baseline on the next pull.

## What's intentionally not here

This is a template, not a product.

- **MIT licensed.** Use freely; the patterns are more interesting than the code.
- **No language assumptions beyond Rust + AWS Lambda in the examples.** The example hooks reference `cargo`, `rustfmt`, and `.unwrap()` because that's the soil they grew in. The patterns generalize cleanly to other stacks (Python + Lambda, Go + Cloud Run, TypeScript + Vercel) — you will need to adapt the example shell glue.
- **No CI integration.** The pre-merge audit hook is the only "CI-shaped" piece, and it runs locally by design.
- **The audit prompt's six checks are illustrative.** Fork and rewrite them for your stack's contracts; the harness is the framing, not the rule set.

---

Distilled from production use at a private Rust + AWS Lambda backend, 2025–2026.
