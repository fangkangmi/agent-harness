#!/usr/bin/env bash
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../force-background-checks.sh"
. "$HERE/_lib.sh"

# ── BLOCK cases: foreground long-running checks ─────────────────────────────

assert_blocks "cargo check (foreground)" "$HOOK" \
  '{"tool_input":{"command":"cargo check -p foo"}}'

assert_blocks "cargo test --workspace (foreground)" "$HOOK" \
  '{"tool_input":{"command":"cargo test --workspace"}}'

assert_blocks "cargo clippy (foreground)" "$HOOK" \
  '{"tool_input":{"command":"cargo clippy --all-targets -- -D warnings"}}'

assert_blocks "make check (foreground)" "$HOOK" \
  '{"tool_input":{"command":"make check"}}'

assert_blocks "make test (foreground)" "$HOOK" \
  '{"tool_input":{"command":"make test"}}'

assert_blocks "scripts/check.sh (foreground)" "$HOOK" \
  '{"tool_input":{"command":"bash .claude/scripts/check.sh"}}'

assert_blocks "cd-prefixed cargo check (foreground)" "$HOOK" \
  '{"tool_input":{"command":"cd crates && cargo check"}}'

assert_blocks "cargo check with run_in_background: false (foreground)" "$HOOK" \
  '{"tool_input":{"command":"cargo check","run_in_background":false}}'

# ── ALLOW cases: background mode, unrelated commands, or prose ──────────────

assert_allows "cargo check with run_in_background: true" "$HOOK" \
  '{"tool_input":{"command":"cargo check","run_in_background":true}}'

assert_allows "cargo test with run_in_background: true" "$HOOK" \
  '{"tool_input":{"command":"cargo test --workspace","run_in_background":true}}'

assert_allows "ls (unrelated)" "$HOOK" \
  '{"tool_input":{"command":"ls -la"}}'

assert_allows "git status (unrelated)" "$HOOK" \
  '{"tool_input":{"command":"git status"}}'

assert_allows "cargo build (not a check)" "$HOOK" \
  '{"tool_input":{"command":"cargo build --release"}}'

assert_allows "cargo run (not a check)" "$HOOK" \
  '{"tool_input":{"command":"cargo run -p foo"}}'

assert_allows "git commit prose mentioning cargo test" "$HOOK" \
  '{"tool_input":{"command":"git commit -m \"chore: cargo test now runs in background\""}}'

report "force-background-checks" || exit 1
