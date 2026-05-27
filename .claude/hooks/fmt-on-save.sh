#!/usr/bin/env bash
# PostToolUse hook: auto-rustfmt .rs files after every Edit or Write.
# Silent on success (no changes). Emits one line when it reformats so
# the agent knows the file changed beneath it.
#
# Rust-specific; adapt to your formatter (gofmt, black, prettier, …) for
# other stacks.

set -euo pipefail

if ! command -v jq      >/dev/null 2>&1; then exit 0; fi
if ! command -v rustfmt >/dev/null 2>&1; then exit 0; fi

input=$(cat)
tool_name=$(printf '%s' "$input" | jq -r '.tool_name // empty')
file_path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')

case "$tool_name" in Edit|Write) ;; *) exit 0 ;; esac
[[ "$file_path" == *.rs ]] || exit 0
[[ -f "$file_path"      ]] || exit 0

# --check exits non-zero if formatting would change the file
if ! rustfmt --edition 2021 --check "$file_path" >/dev/null 2>&1; then
  rustfmt --edition 2021 "$file_path" 2>/dev/null
  echo "auto-fmt: $(basename "$file_path")"
fi

exit 0
