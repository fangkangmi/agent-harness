#!/usr/bin/env bash
# Shared assertions for hook tests. Source from each test-*.sh.
#
# Conventions:
#   PASS / FAIL counters are accumulated across calls.
#   FAILED_NAMES collects the human-readable label of each failing case.
#   Call `report "<hook-name>"` at the end to print the suite summary
#   and propagate the right exit code.

PASS=0
FAIL=0
FAILED_NAMES=()

# assert_blocks <case-label> <hook-script> <stdin-json>
# Hook should exit 2 (PreToolUse block).
assert_blocks() {
  local name="$1" hook="$2" input="$3"
  local actual
  actual=$(printf '%s' "$input" | "$hook" >/dev/null 2>&1; echo $?)
  if [[ "$actual" == "2" ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    FAILED_NAMES+=("$name (expected exit 2, got $actual)")
  fi
}

# assert_allows <case-label> <hook-script> <stdin-json>
# Hook should exit 0 (no block).
assert_allows() {
  local name="$1" hook="$2" input="$3"
  local actual
  actual=$(printf '%s' "$input" | "$hook" >/dev/null 2>&1; echo $?)
  if [[ "$actual" == "0" ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    FAILED_NAMES+=("$name (expected exit 0, got $actual)")
  fi
}

# assert_emits_json <case-label> <hook-script> <stdin-json>
# Hook should exit 0 AND emit JSON containing
# .hookSpecificOutput.additionalContext (the soft-nudge pattern).
assert_emits_json() {
  local name="$1" hook="$2" input="$3"
  local output
  output=$(printf '%s' "$input" | "$hook" 2>/dev/null)
  if printf '%s' "$output" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    FAILED_NAMES+=("$name (expected additionalContext JSON, got: ${output:0:80})")
  fi
}

# assert_silent <case-label> <hook-script> <stdin-json>
# Hook should exit 0 with no stdout (silent allow / no nudge).
assert_silent() {
  local name="$1" hook="$2" input="$3"
  local output
  output=$(printf '%s' "$input" | "$hook" 2>/dev/null)
  if [[ -z "$output" ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    FAILED_NAMES+=("$name (expected silence, got: ${output:0:80})")
  fi
}

# assert_stdout_contains <case-label> <hook-script> <stdin-json> <substring>
# Hook should exit 0 and stdout must contain the substring.
assert_stdout_contains() {
  local name="$1" hook="$2" input="$3" needle="$4"
  local output
  output=$(printf '%s' "$input" | "$hook" 2>/dev/null)
  if [[ "$output" == *"$needle"* ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    FAILED_NAMES+=("$name (expected stdout to contain '$needle', got: ${output:0:80})")
  fi
}

# report <hook-name>
# Print summary line and exit 0/1 accordingly.
report() {
  local hook_name="$1"
  if [[ "$FAIL" -eq 0 ]]; then
    echo "  $PASS passed"
    return 0
  fi
  echo "  $PASS passed, $FAIL FAILED:"
  for n in "${FAILED_NAMES[@]}"; do
    echo "    - $n"
  done
  return 1
}
