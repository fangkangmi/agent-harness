#!/usr/bin/env bash
# PreToolUse hook for Bash: reject `git commit` invocations whose message
# contains forbidden trailers. Shipped example matches "Co-Authored-By:"
# trailers and a "Generated with [Claude Code]" tagline; customize the
# FORBIDDEN_PATTERN regex below for your team's policy.
#
# Fail-open on missing jq so a partially-set-up dev machine isn't blocked
# from all bash work.

set -euo pipefail

# Canonical forms only, not substrings in prose. Tune for your policy:
#   - line starting with "Co-Authored-By:"      (the real trailer form)
#   - the literal "🤖 Generated with [Claude Code]" tagline
FORBIDDEN_PATTERN='^[[:space:]]*Co-Authored-By:|🤖 Generated with \[Claude Code\]'

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

input=$(cat)
command=$(printf '%s' "$input" | jq -r '.tool_input.command // empty')

# Only inspect git commit invocations.
case "$command" in
  *"git commit"*) ;;
  *) exit 0 ;;
esac

if printf '%s\n' "$command" | grep -qE "$FORBIDDEN_PATTERN"; then
  cat >&2 <<'MSG'
Blocked: this commit message contains a forbidden footer.

Team policy:
  - No `Co-Authored-By:` lines
  - No "Generated with Claude Code" footer

Re-run the commit without those lines, or tighten/relax the regex in
.claude/hooks/reject-forbidden-footers.sh to match your team's policy.
MSG
  exit 2
fi

exit 0
