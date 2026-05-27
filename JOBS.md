# Scheduled / one-shot agent jobs

The harness runs agent jobs in two modes beyond the inline `claude` session:

- **Scheduled** — cron-style jobs that fire on a calendar, e.g. daily at
  06:00 or every Monday/Wednesday at 05:00. Used for recurring engineering
  hygiene work that doesn't need a human at the wheel.
- **One-shot** — long-lived jobs that run once on demand, kicked off in the
  background. Used for larger migrations, audits, and orchestration tasks
  that take long enough that you don't want to block your terminal.

Categories of work that fit this pattern well:

- Dependency auditing and version bumps.
- Self-regression of the harness itself — hook suite + scaffolding skills.
- Documentation sweeps (stale plans, orphaned files, link rot).
- Registry migrations (prompts, schemas, env-var inventories).
- Observability passes (trace audits, error-rate sweeps, span integrity).
- Correctness audits over async pipelines and multi-tenant isolation.
- Token / credential refresh for upstream services the agent depends on.

The pattern is the same in each case: define a prompt that describes the
audit or task; run it against the current repo state on a schedule; deliver
the result as a short report (Slack, file, PR comment, or stdout). The
specific job definitions live downstream of this template — fork the
repo, add your jobs, point them at the prompts you want to run.

This file is intentionally a stub. The jobs themselves are project-specific
and not part of the public template. The point of documenting them here is
to surface the *pattern* and the categories of work that respond well to it.
