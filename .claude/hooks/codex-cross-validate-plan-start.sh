#!/usr/bin/env bash
# PreToolUse hook on EnterPlanMode.
#
# When the agent enters plan mode, kick off `codex exec` in the BACKGROUND
# so it plans the same task in parallel. By the time the agent exits plan
# mode, codex's output is (mostly) ready. The companion hook on
# ExitPlanMode (codex-cross-validate-plan.sh) waits for it to finish and
# feeds the output back to the agent as cross-validation.
#
# Returns immediately (well under 1s); never blocks the agent's planning.
#
# Requires the `codex` CLI on PATH. If it's missing, the hook exits 0 and
# planning proceeds without cross-validation.

set -uo pipefail

INPUT=$(cat)

SID=$(jq -r '.session_id // "default"' <<<"$INPUT")
TRANSCRIPT=$(jq -r '.transcript_path // empty' <<<"$INPUT")
CWD=$(jq -r '.cwd // empty' <<<"$INPUT")
[[ -z "$CWD" ]] && CWD="$PWD"

STATE_DIR="${TMPDIR:-/tmp}/claude-codex-plan"
mkdir -p "$STATE_DIR"

PID_FILE="$STATE_DIR/$SID.pid"
OUT_FILE="$STATE_DIR/$SID.out"
ERR_FILE="$STATE_DIR/$SID.err"
TASK_FILE="$STATE_DIR/$SID.task"
MARKER="$STATE_DIR/$SID.consulted"

# Re-entering plan mode in the same session: clean previous run.
if [[ -f "$PID_FILE" ]]; then
  OLD_PID=$(cat "$PID_FILE" 2>/dev/null || echo "")
  [[ -n "$OLD_PID" ]] && kill -- "$OLD_PID" 2>/dev/null || true
fi
rm -f "$PID_FILE" "$OUT_FILE" "$ERR_FILE" "$TASK_FILE" "$MARKER"

if ! command -v codex >/dev/null 2>&1; then
  echo "[codex-cross-validate-start] codex CLI not on PATH; skipping" >&2
  exit 0
fi

if [[ -z "$TRANSCRIPT" || ! -f "$TRANSCRIPT" ]]; then
  echo "[codex-cross-validate-start] no transcript path; skipping" >&2
  exit 0
fi

# Most recent REAL user message: type=="user" with string content, or array
# content where no element is a tool_result (i.e., user-typed text, not a
# tool-call result).
USER_TASK=$(tac "$TRANSCRIPT" 2>/dev/null \
  | jq -r 'select(.type == "user")
           | select(.message.content
                    | (type == "string")
                      or (type == "array" and (any(.[]; .type == "tool_result") | not)))
           | .message.content
           | if type == "string" then .
             else (map(select(.type == "text") | .text) | join("\n"))
             end' 2>/dev/null \
  | awk 'NF { print; exit }')

if [[ -z "$USER_TASK" ]]; then
  echo "[codex-cross-validate-start] no user message found in transcript; skipping" >&2
  exit 0
fi

printf '%s\n' "$USER_TASK" > "$TASK_FILE"

CODEX_PROMPT=$(cat <<EOF
The user asked: $USER_TASK

You are a second opinion. Another AI agent (Claude) is planning this same task in parallel. Investigate the relevant parts of this repository (you have read-only access), then write a concise INDEPENDENT implementation plan.

Output structure:
1. Brief task restatement (1 sentence).
2. Numbered plan steps with concrete file paths and what changes in each.
3. Key risks / edge cases (3-5 bullets).
4. Anything you'd want the other agent to double-check (gaps, ambiguities, alternative approaches).

Target under 400 words. Be specific. Skip preamble.
EOF
)

# Spawn codex in background, fully detached.
nohup codex exec \
  --sandbox read-only \
  --skip-git-repo-check \
  --color never \
  -C "$CWD" \
  "$CODEX_PROMPT" \
  </dev/null >"$OUT_FILE" 2>"$ERR_FILE" &

CODEX_PID=$!
echo "$CODEX_PID" > "$PID_FILE"
disown "$CODEX_PID" 2>/dev/null || true

exit 0
