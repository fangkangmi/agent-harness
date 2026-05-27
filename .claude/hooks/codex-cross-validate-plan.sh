#!/usr/bin/env bash
# PreToolUse hook on ExitPlanMode.
#
# Companion to codex-cross-validate-plan-start.sh. When the agent exits
# plan mode, wait for the background codex run that was kicked off on
# EnterPlanMode to finish, then DENY the ExitPlanMode call once with
# codex's plan attached as feedback. The agent reconciles the two plans
# and re-calls ExitPlanMode; the second call passes through (one-shot
# marker).
#
# If the start hook never ran (or codex never spawned), exit 0 so the
# plan goes through unblocked — never trap the user in plan mode.

set -uo pipefail

INPUT=$(cat)

SID=$(jq -r '.session_id // "default"' <<<"$INPUT")

STATE_DIR="${TMPDIR:-/tmp}/claude-codex-plan"
PID_FILE="$STATE_DIR/$SID.pid"
OUT_FILE="$STATE_DIR/$SID.out"
ERR_FILE="$STATE_DIR/$SID.err"
MARKER="$STATE_DIR/$SID.consulted"

# Already cross-validated this plan-mode session → let the plan through.
if [[ -f "$MARKER" ]]; then
  exit 0
fi

# Start hook didn't fire (or codex skipped) → nothing to consult; pass through.
if [[ ! -f "$PID_FILE" ]]; then
  exit 0
fi

# Wait up to MAX_WAIT seconds for codex to finish. If it's already done,
# this loop exits on the first iteration.
PID=$(cat "$PID_FILE" 2>/dev/null || echo "")
MAX_WAIT=120
ELAPSED=0
INTERVAL=2
if [[ -n "$PID" ]]; then
  while kill -0 "$PID" 2>/dev/null; do
    if (( ELAPSED >= MAX_WAIT )); then
      kill -- "$PID" 2>/dev/null || true
      echo "[codex-cross-validate] codex still running after ${MAX_WAIT}s; killed and proceeding with partial output" >&2
      break
    fi
    sleep "$INTERVAL"
    ELAPSED=$((ELAPSED + INTERVAL))
  done
fi

# One-shot regardless of outcome below.
touch "$MARKER"

if [[ ! -s "$OUT_FILE" ]]; then
  echo "[codex-cross-validate] codex output empty; skipping cross-validation" >&2
  if [[ -s "$ERR_FILE" ]]; then
    echo "[codex-cross-validate] codex stderr:" >&2
    cat "$ERR_FILE" >&2
  fi
  exit 0
fi

REASON_FILE=$(mktemp)
trap 'rm -f "$REASON_FILE"' EXIT
{
  cat <<'HEADER'
A second AI agent (Codex CLI) was planning this same task in parallel for cross-validation. It just finished. Compare its plan with yours, reconcile differences, then re-call ExitPlanMode with your final plan.

=== CODEX'S INDEPENDENT PLAN ===
HEADER
  cat "$OUT_FILE"
  cat <<'FOOTER'
=== END CODEX'S PLAN ===

Cross-validation guidance:
- Where Codex agrees with you, keep that approach.
- Where Codex disagrees, decide which is correct (do not blindly take either side).
- Where Codex flagged a gap, address it in your final plan.
- Briefly note in your final plan any places you deliberately chose your approach over Codex's, and why.
FOOTER
} > "$REASON_FILE"

jq -n --rawfile reason "$REASON_FILE" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: $reason
  }
}'
