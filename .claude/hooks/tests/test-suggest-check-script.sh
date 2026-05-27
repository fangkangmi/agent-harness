#!/usr/bin/env bash
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../suggest-check-script.sh"
. "$HERE/_lib.sh"

# ── NUDGE cases (should emit JSON additionalContext) ────────────────────────

assert_emits_json "cargo clippy --workspace --all-targets" "$HOOK" \
  '{"tool_input":{"command":"cargo clippy --workspace --all-targets -- -D warnings"}}'

assert_emits_json "cargo test --workspace" "$HOOK" \
  '{"tool_input":{"command":"cargo test --workspace"}}'

assert_emits_json "make test" "$HOOK" \
  '{"tool_input":{"command":"make test"}}'

# ── SILENT cases ────────────────────────────────────────────────────────────

assert_silent "single-crate cargo test (-p)" "$HOOK" \
  '{"tool_input":{"command":"cargo test -p foo"}}'

assert_silent "single-crate cargo clippy (--package)" "$HOOK" \
  '{"tool_input":{"command":"cargo clippy --package foo -- -D warnings"}}'

assert_silent "already using the script" "$HOOK" \
  '{"tool_input":{"command":"bash .claude/scripts/check.sh"}}'

assert_silent "cargo build (not a gate)" "$HOOK" \
  '{"tool_input":{"command":"cargo build --release"}}'

assert_silent "ls (irrelevant)" "$HOOK" \
  '{"tool_input":{"command":"ls -la"}}'

report "suggest-check-script" || exit 1
