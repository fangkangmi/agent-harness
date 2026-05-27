#!/usr/bin/env bash
# PostToolUse — Edit|Write
# When a configured path pattern is edited, emit a compact reminder of the
# rules that apply to that hot spot. Informational only; always exits 0.
#
# Customize REMIND_PATTERN and the heredoc body below for the rules that
# matter in your project. The shipped example fires on any path that
# looks like an LLM call site or a schema-defining file — replace with
# whatever your team's drift-prone surfaces are.

set -uo pipefail
command -v jq >/dev/null 2>&1 || exit 0

# Regex of file paths that should trigger the reminder. Tune for your repo.
REMIND_PATTERN='/llm/|/worker/|client\.rs|inventory\.rs|schemas\.rs|/store/[^/]+/[^/]+\.yaml'

input=$(cat)
file_path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // ""' 2>/dev/null)
[[ -z "$file_path" ]] && exit 0

printf '%s' "$file_path" | grep -qE "$REMIND_PATTERN" || exit 0

cat <<'REMINDER'
[rules] File matched a drift-prone pattern — quick reminder:
  1. Config values (model name, temperature, timeouts) live in the central
     spec, not in source code. No hardcoding, no new env vars.
  2. New entry on one side of a registry/store pair? The other side
     needs the matching update or runtime startup will fail.
  3. Every external call goes through the shared traced client wrapper;
     persist returned trace IDs on entities you save.
  4. After changing a config-spec value, recycle the process — caches are
     per-instance.
REMINDER

exit 0
