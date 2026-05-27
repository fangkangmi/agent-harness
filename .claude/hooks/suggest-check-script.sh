#!/usr/bin/env bash
# PreToolUse hook on Bash: when the agent runs a full-suite cargo
# invocation directly (cargo clippy --workspace, cargo test --workspace,
# make test), inject a system reminder via additionalContext suggesting
# .claude/scripts/check.sh — which compresses verbose output via a cheap
# model BEFORE returning to context.
#
# This is a soft nudge, not a block. The agent can still run raw cargo if
# it explicitly needs unfiltered output. The reminder just makes the
# context-saving path discoverable when the /check skill wasn't invoked.

set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then exit 0; fi

input=$(cat)
command=$(printf '%s' "$input" | jq -r '.tool_input.command // empty')

# Bail out fast if we shouldn't fire.
case "$command" in
  *"scripts/check.sh"*) exit 0 ;;   # already using the script
  *" -p "*|*"-p="*)     exit 0 ;;   # single-crate cargo, fine to run raw
  *"--package "*)       exit 0 ;;   # ditto, long form
esac

# Match full-suite invocations — anything that runs the whole gate.
is_full_suite=0
case "$command" in
  *"make test"*)                            is_full_suite=1 ;;
  *"cargo clippy"*"--workspace"*)           is_full_suite=1 ;;
  *"cargo clippy"*"--all-targets"*)         is_full_suite=1 ;;
  *"cargo test"*"--workspace"*)             is_full_suite=1 ;;
  *"cargo test --all"*)                     is_full_suite=1 ;;
esac

[[ "$is_full_suite" == "1" ]] || exit 0

# Emit additionalContext via JSON. Exit 0 so the command still runs.
# The reminder shows up as a system message the agent reads on the next turn.
cat <<'JSON'
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "additionalContext": "Tip: .claude/scripts/check.sh wraps the full quality gate suite (fmt + clippy + make test) and compresses verbose output BEFORE returning it to the conversation, which keeps context tight. For full-suite runs prefer `bash .claude/scripts/check.sh` (or invoke the /check skill). Run raw cargo only when you specifically need unfiltered output (e.g. debugging a flaky test or investigating a specific lint at a precise line)."
  }
}
JSON
exit 0
