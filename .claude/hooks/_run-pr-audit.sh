#!/usr/bin/env bash
# Background worker for spawn-pr-audit.sh. Not invoked directly by hooks.
#
# Reads context from env vars (set by the parent hook):
#   AUDIT_REPO       — repo root
#   AUDIT_BASE_SHA   — merge-base sha to diff against
#   AUDIT_BASE_REF   — human-readable name of the base ref (for the report)
#   AUDIT_BRANCH     — branch being audited
#   AUDIT_OUT        — markdown report destination
#   AUDIT_LOCK       — lockfile to remove on exit
#
# Detaches via setsid in the parent so we don't depend on the original
# shell. Always clears the lockfile on exit (success, failure, or signal)
# so a stale lock never wedges future audits.

set -uo pipefail

cleanup() {
  [[ -n "${AUDIT_LOCK:-}" && -f "$AUDIT_LOCK" ]] && rm -f "$AUDIT_LOCK"
}
trap cleanup EXIT INT TERM

: "${AUDIT_REPO:?}" "${AUDIT_BASE_SHA:?}" "${AUDIT_BASE_REF:?}" \
  "${AUDIT_BRANCH:?}" "${AUDIT_OUT:?}" "${AUDIT_LOCK:?}"

cd "$AUDIT_REPO" || exit 1

PROMPT_FILE="$AUDIT_REPO/.claude/prompts/pre-merge-audit.md"
if [[ ! -f "$PROMPT_FILE" ]]; then
  printf '# audit failed: prompt missing at %s\n' "$PROMPT_FILE" > "$AUDIT_OUT"
  exit 1
fi

# Pre-compute the diff context once so the model call doesn't re-shell out.
CHANGED_FILES=$(git diff --name-only "$AUDIT_BASE_SHA"..HEAD 2>/dev/null || true)
DIFF_STAT=$(git diff --stat "$AUDIT_BASE_SHA"..HEAD 2>/dev/null || true)

# Build the prompt with substitutions. We append the diff context as a
# fenced block at the end rather than relying on the model to re-run git —
# saves tool calls and keeps the audit deterministic.
PROMPT=$(cat "$PROMPT_FILE")
PROMPT="$PROMPT

---

## Diff context (precomputed)

- Branch: \`$AUDIT_BRANCH\`
- Base: \`$AUDIT_BASE_REF\` @ \`$AUDIT_BASE_SHA\`

### Changed files
\`\`\`
$CHANGED_FILES
\`\`\`

### Stat
\`\`\`
$DIFF_STAT
\`\`\`
"

# Write a header now so even if the model call fails, the file is useful.
{
  printf '# Pre-merge audit — %s\n\n' "$AUDIT_BRANCH"
  printf -- '- Base: `%s` @ `%s`\n' "$AUDIT_BASE_REF" "$AUDIT_BASE_SHA"
  printf -- '- Spawned: %s\n\n' "$(date -Is)"
  printf '## Changed files\n\n```\n%s\n```\n\n' "$CHANGED_FILES"
  printf '## Audit (Haiku 4.5)\n\n'
} > "$AUDIT_OUT"

# Haiku call. Read-only toolset — the runner itself writes the report,
# the model just prints markdown to stdout.
if ! printf '%s' "$PROMPT" | claude -p \
      --model claude-haiku-4-5-20251001 \
      --allowedTools 'Bash,Read,Grep,Glob' \
      >> "$AUDIT_OUT" 2>&1; then
  printf '\n\n_audit call failed — see stderr above_\n' >> "$AUDIT_OUT"
  exit 1
fi

exit 0
