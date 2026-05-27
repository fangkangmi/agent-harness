#!/usr/bin/env bash
# Tests for remind-rules.sh (PostToolUse reminder hook).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_lib.sh"
HOOK="$SCRIPT_DIR/../remind-rules.sh"

# Helpers
edit_payload() { printf '{"tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$1"; }

echo "remind-rules.sh"

# --- should emit reminder (matches the shipped REMIND_PATTERN) ---

assert_stdout_contains \
  "llm/ path triggers reminder" "$HOOK" \
  "$(edit_payload "/repo/services/llm/grading.rs")" \
  "[rules]"

assert_stdout_contains \
  "client.rs triggers reminder" "$HOOK" \
  "$(edit_payload "/repo/crates/shared/src/clients/client.rs")" \
  "[rules]"

assert_stdout_contains \
  "store yaml triggers reminder" "$HOOK" \
  "$(edit_payload "/repo/store/category/entry.yaml")" \
  "[rules]"

assert_stdout_contains \
  "inventory.rs triggers reminder" "$HOOK" \
  "$(edit_payload "/repo/crates/shared/src/services/inventory.rs")" \
  "[rules]"

assert_stdout_contains \
  "schemas.rs triggers reminder" "$HOOK" \
  "$(edit_payload "/repo/crates/foo/src/bin/schemas.rs")" \
  "[rules]"

# --- should be silent ---

assert_silent \
  "unrelated Rust file is silent" "$HOOK" \
  "$(edit_payload "/repo/crates/shared/src/models/score.rs")"

assert_silent \
  "handler file is silent" "$HOOK" \
  "$(edit_payload "/repo/services/foo/src/handlers.rs")"

assert_silent \
  "missing file_path is silent" "$HOOK" \
  '{"tool_name":"Edit","tool_input":{}}'

report "remind-rules.sh"
