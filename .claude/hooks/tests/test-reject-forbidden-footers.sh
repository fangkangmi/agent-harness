#!/usr/bin/env bash
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../reject-forbidden-footers.sh"
. "$HERE/_lib.sh"

# ── BLOCK cases ─────────────────────────────────────────────────────────────

assert_blocks "co-authored-by trailer at line start" "$HOOK" \
  '{"tool_input":{"command":"git commit -m \"feat: x\n\nCo-Authored-By: foo <bar@baz>\""}}'

assert_blocks "indented co-authored-by trailer" "$HOOK" \
  '{"tool_input":{"command":"git commit -m \"feat: x\n\n   Co-Authored-By: foo <bar@baz>\""}}'

assert_blocks "generated-with markdown link" "$HOOK" \
  '{"tool_input":{"command":"git commit -m \"feat: x\n\n🤖 Generated with [Claude Code](https://claude.com/claude-code)\""}}'

# ── ALLOW cases ─────────────────────────────────────────────────────────────

assert_allows "prose mentioning the policy" "$HOOK" \
  '{"tool_input":{"command":"git commit -m \"chore: hooks block Co-Authored-By footers\""}}'

assert_allows "prose without colon (Co-Authored-By or)" "$HOOK" \
  '{"tool_input":{"command":"git commit -m \"chore: blocks Co-Authored-By or generator footers\""}}'

assert_allows "non-git command (irrelevant)" "$HOOK" \
  '{"tool_input":{"command":"ls -la"}}'

assert_allows "git status (not commit)" "$HOOK" \
  '{"tool_input":{"command":"git status"}}'

report "reject-forbidden-footers" || exit 1
