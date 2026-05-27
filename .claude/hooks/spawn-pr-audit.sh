#!/usr/bin/env bash
# PreToolUse hook on Bash: when the agent is about to create / merge a PR
# (or push to a base branch), spawn a background Haiku audit. The exact
# checks are defined in .claude/prompts/pre-merge-audit.md — customize
# them for your stack's contracts.
#
# The audit is fully detached: this hook exits 0 immediately so the user's
# push / PR command is never blocked. The report lands in
# .claude/audits/pre-merge-<branch>-<ts>.md to be read manually before
# clicking merge. Saves CI minutes by doing the static-check work locally
# on a cheap model (~$0.01-0.03 per audit) instead of in a CI runner.
#
# Fail-open everywhere: missing jq / claude / git / changed-file mismatch
# all silently allow the command. Never block.

set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then exit 0; fi
if ! command -v claude >/dev/null 2>&1; then exit 0; fi

input=$(cat)
command=$(printf '%s' "$input" | jq -r '.tool_input.command // empty')

# ── trigger gate ────────────────────────────────────────────────────────────
# Fire on PR-lifecycle commands and direct base-branch pushes. The patterns
# are intentionally narrow — running `gh pr list` or `git push origin
# my-feature` should NOT spawn an audit.

should_fire=0
case "$command" in
  *"gh pr create"*)                              should_fire=1 ;;
  *"gh pr merge"*)                               should_fire=1 ;;
  *"git push"*"origin"*"develop"*)               should_fire=1 ;;
  *"git push"*"origin"*"release"*)               should_fire=1 ;;
  *"git push"*"origin"*"main"*)                  should_fire=1 ;;
esac

[[ "$should_fire" == "1" ]] || exit 0

# ── repo context ────────────────────────────────────────────────────────────

REPO_ROOT="${CLAUDE_PROJECT_DIR:-}"
[[ -n "$REPO_ROOT" ]] || REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[[ -n "$REPO_ROOT" && -d "$REPO_ROOT/.git" ]] || exit 0

BRANCH=$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
BRANCH_SLUG=$(printf '%s' "$BRANCH" | tr '/' '_' | tr -cd '[:alnum:]_-')
[[ -n "$BRANCH_SLUG" ]] || BRANCH_SLUG="unknown"

# ── lock: at most one in-flight audit per branch ────────────────────────────

LOCK_DIR="$REPO_ROOT/.claude"
LOCK="$LOCK_DIR/.audit-lock-$BRANCH_SLUG"

if [[ -f "$LOCK" ]]; then
  pid=$(cat "$LOCK" 2>/dev/null || echo "")
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    cat <<JSON
{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"pre-merge audit already running for branch $BRANCH (pid $pid). Latest report under .claude/audits/."}}
JSON
    exit 0
  fi
  rm -f "$LOCK"
fi

# ── diff range against the right base ───────────────────────────────────────

BASE_REF=""
for candidate in origin/develop develop origin/main main; do
  if git -C "$REPO_ROOT" rev-parse --verify "$candidate" >/dev/null 2>&1; then
    BASE_REF="$candidate"
    break
  fi
done
[[ -n "$BASE_REF" ]] || exit 0

BASE_SHA=$(git -C "$REPO_ROOT" merge-base HEAD "$BASE_REF" 2>/dev/null || echo "")
[[ -n "$BASE_SHA" ]] || exit 0

CHANGED=$(git -C "$REPO_ROOT" diff --name-only "$BASE_SHA"..HEAD 2>/dev/null || true)
[[ -n "$CHANGED" ]] || exit 0

# Skip if nothing relevant changed. The shipped pattern is a generic
# match for source files under a few crate paths plus an OpenAPI spec.
# Tune for whatever your audit cares about; if nothing matches, we save
# the cost of spawning the model call.
if ! printf '%s\n' "$CHANGED" | grep -qE '(crates/[^/]+/src/.*\.rs|services/[^/]+/src/.*\.rs|api/openapi.*\.yaml)'; then
  exit 0
fi

# ── spawn detached audit ────────────────────────────────────────────────────

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
AUDIT_DIR="$REPO_ROOT/.claude/audits"
OUT="$AUDIT_DIR/pre-merge-$BRANCH_SLUG-$TIMESTAMP.md"
RUNNER="$REPO_ROOT/.claude/hooks/_run-pr-audit.sh"

mkdir -p "$AUDIT_DIR"
[[ -x "$RUNNER" ]] || exit 0

# setsid detaches from the controlling terminal so the audit survives shell
# exit; nohup keeps it alive across SIGHUP. The runner is responsible for
# clearing the lockfile on completion or failure.
AUDIT_BASE_SHA="$BASE_SHA" \
AUDIT_BASE_REF="$BASE_REF" \
AUDIT_BRANCH="$BRANCH" \
AUDIT_OUT="$OUT" \
AUDIT_LOCK="$LOCK" \
AUDIT_REPO="$REPO_ROOT" \
  setsid nohup "$RUNNER" </dev/null >/dev/null 2>&1 &

child_pid=$!
echo "$child_pid" > "$LOCK"
disown "$child_pid" 2>/dev/null || true

REL_OUT="${OUT#$REPO_ROOT/}"
cat <<JSON
{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"Pre-merge audit spawned in background (Haiku, pid $child_pid) → $REL_OUT. Read it before merging."}}
JSON

exit 0
