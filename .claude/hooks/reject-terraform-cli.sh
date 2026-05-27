#!/usr/bin/env bash
# PreToolUse hook for Bash: reject the bare `terraform` CLI.
# Example "use the canonical CLI" rule — the shipped policy is "use
# OpenTofu (tofu), not terraform". Fork the structure for any CLI pair
# that matters in your stack.
#
# Matches the bare `terraform` command, not `terraform-application/`,
# `terraform-docs`, or any path containing the word.

set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

input=$(cat)
command=$(printf '%s' "$input" | jq -r '.tool_input.command // empty')

# Skip prose: `git commit -m "..."` may legitimately mention the word
# terraform inside the message. The hook should police actual invocations,
# not commit prose.
case "$command" in
  *"git commit"*) exit 0 ;;
esac

# Match `terraform` followed by a real terraform subcommand. Catches the
# actual CLI without false-positiving on words like "terraform-docs" or
# prose mentions of "the terraform configs".
SUBCMDS='init|plan|apply|destroy|fmt|validate|state|workspace|import|output|show|console|providers|version|graph|login|logout|refresh|taint|untaint|force-unlock'
if printf '%s\n' "$command" | grep -qE "(^|[[:space:];&|()\`]|sudo[[:space:]])terraform[[:space:]]+($SUBCMDS)([[:space:]]|$)"; then
  cat >&2 <<'MSG'
Blocked: use `tofu` (OpenTofu) instead of `terraform` CLI.

Example team policy. The `terraform` CLI may produce subtly different
state than `tofu` against the same configuration. Customize this hook
(or remove it) for your team's actual CLI conventions.
MSG
  exit 2
fi

exit 0
