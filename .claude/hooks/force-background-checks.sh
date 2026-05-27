#!/usr/bin/env bash
# PreToolUse hook on Bash: force long-running cargo/make check commands to
# run in the background (run_in_background: true), so the agent doesn't
# block waiting on a check that almost always passes.
#
# The agent is expected to pick run_in_background itself; this hook is the
# safety net that catches the cases it forgets. Customize the match list
# below for whatever long-running checks exist in your stack.

set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then exit 0; fi

input=$(cat)
command=$(printf '%s' "$input" | jq -r '.tool_input.command // empty')
bg=$(printf '%s' "$input" | jq -r '.tool_input.run_in_background // false')

# If the agent already picked background mode, nothing to enforce.
if [[ "$bg" == "true" ]]; then
  exit 0
fi

# Skip prose: git commit messages may legitimately mention these names.
case "$command" in
  *"git commit"*) exit 0 ;;
esac

# Commands heavy enough to deserve backgrounding. Tune for your stack.
match=0
case "$command" in
  *"cargo check"*)        match=1 ;;
  *"cargo test"*)         match=1 ;;
  *"cargo clippy"*)       match=1 ;;
  *"make check"*)         match=1 ;;
  *"make test"*)          match=1 ;;
  *"scripts/check.sh"*)   match=1 ;;
esac

[[ "$match" == "1" ]] || exit 0

cat >&2 <<'MSG'
Blocked: this is a long-running check that should run in the background.

Retry the same Bash call with `run_in_background: true`. You will be
notified automatically when it completes; in the meantime keep working
on other things. (Rule: cargo check/test/clippy, make check/test, and
.claude/scripts/check.sh all qualify as long-running.)
MSG
exit 2
