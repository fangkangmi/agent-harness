---
name: new-plan
description: Scaffold a new docs/plans/YYYY-MM-DD-<slug>.md design doc. Use before starting any feature or non-trivial change — the team requires a plan before implementation.
allowed-tools: Bash, Read, Write
---

# /new-plan — scaffold a planning doc

Project rule (workflow): write a plan in `docs/plans/` before implementing
any feature or non-trivial change. The plan is the contract; the PR
should match it.

## Steps

1. **Get the date.** Run `date +%Y-%m-%d` for today's date as `YYYY-MM-DD`.

2. **Get the slug.** Use the user's argument if given, else ask. Slug
   format: lowercase, hyphenated, ~3–5 words, no trailing extension.
   Example: `request-id-propagation`.

3. **Path:** `docs/plans/<date>-<slug>.md`. If the file already exists,
   stop and ask the user whether to update or pick a different slug.

4. **Mirror existing shape.** Look at the 2–3 most recent files in
   `docs/plans/`:
   ```bash
   ls -t docs/plans/*.md | head -3
   ```
   Teams converge on a particular section structure. Skim those files
   and use the same headings + ordering. Do not invent new shapes.

5. **Typical sections** (cross-check against the recent files):
   - **Problem / context** — what's broken or missing, with concrete
     pointers (`file:line`, ticket links, prior plan references).
   - **Goal** — one or two sentences of what done looks like.
   - **Non-goals** — explicit out-of-scope, to prevent scope creep.
   - **Design** — chosen approach. Include alternatives considered if
     the decision was non-obvious.
   - **Milestones** — discrete, reviewable steps. Map to commits or PR
     stages.
   - **Risks / unknowns** — what could go wrong, what you don't know yet.
   - **Test plan** — how we'll know it works (unit, integration, manual,
     observability).
   - **Rollout** — flag gating, env order (local → dev → uat → prod),
     any migration steps.

6. **Stop after creating the file.** Do **not** start implementing — give
   the user a chance to read, edit, and approve the plan first.

## Output

After creating the file, print:
```
created docs/plans/<date>-<slug>.md — open it, fill in the sections, then
say "go" when you're ready to implement.
```
