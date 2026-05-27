---
name: check
description: Run the full pre-PR quality gate suite (fmt, clippy, test, project-specific integrity). Use before pushing or opening a PR, or whenever the user asks for "the checks" / "ci-style verification".
allowed-tools: Bash, Read
---

# /check — full quality gate suite

Run the project's quality gates via the bundled script, which compresses
verbose clippy/test output via a cheap model before returning so only a
tight summary lands in context.

## Steps

1. **Run the suite:**
   ```bash
   bash .claude/scripts/check.sh
   ```
   The script runs the gates in order, continuing through failures:
   format check, lint, test, and any project-specific integrity check.
   Each failing gate prints a compressed `[FAIL]` summary instead of full
   compiler output.

   **Not included by design:** heavy integration tests. They typically
   need external services (Docker / database / queue) up, so bundling
   them would either fail cold or silently skip. Run them yourself
   before PR.

2. **Read the output.** The script ends with `✓ all gates green` (exit 0)
   or `✗ one or more gates failed` (exit 1). Each failed gate prints a
   `[FAIL]` line with a compressed list of actionable issues:
   `• file:line — what to fix`.

3. **If snapshots failed:** the test stage will say so. Re-run the
   snapshot review tool (e.g. `cargo insta review`) and confirm with the
   user whether the new snapshots are correct. Do not auto-accept.

4. **If lint failed:** report the compressed list. Do not auto-fix
   without user OK — show the diff first.

5. **If format failed:** the script reports the formatter command to
   fix. The `fmt-on-save` PostToolUse hook should normally prevent this,
   so format failures here usually mean someone bypassed the hook.

## Output

End with a one-line summary:
- `[OK] all gates green`
- `[FAIL] <gate>: <one-line reason>`

Do not commit, push, or amend automatically — just report.
