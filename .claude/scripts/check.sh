#!/usr/bin/env bash
# Full pre-PR quality gate suite — called by the /check skill.
# Runs fmt-check, lint, tests, and any project-specific integrity check.
# Compresses verbose output via a cheap model BEFORE returning, so only
# the summary hits the agent's context.
#
# This is a template. Adapt the gates and the working directory for your
# stack — the structure (continue-through-failures + compression) is the
# reusable part.
#
# Exit codes:
#   0  all gates green
#   1  one or more gates failed (see output)

set -uo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
# Adjust to wherever your build commands need to run from. If your project
# is single-rooted, leave RUST_ROOT empty and skip the cd in each gate.
RUST_ROOT="$REPO_ROOT"
THRESHOLD=25   # lines — compress output above this

# ── helpers ─────────────────────────────────────────────────────────────────

compress() {
  local label="$1"
  local raw="$2"
  local line_count
  line_count=$(printf '%s\n' "$raw" | wc -l)

  if [[ "$line_count" -le "$THRESHOLD" ]] || ! command -v claude >/dev/null 2>&1; then
    printf '%s\n' "$raw"
    return
  fi

  local truncated
  truncated=$(printf '%s\n' "$raw" | head -120)

  local prompt="$label output for a project. \
List ONLY actionable issues as '• file:line — what to fix'. \
Skip boilerplate lines (Compiling, Finished, Downloading). \
Under 80 words. If all green, reply exactly: [OK]"

  local summary
  summary=$(printf '%s\n' "$truncated" | claude -p "$prompt" 2>/dev/null) || {
    printf '%s\n' "$raw"   # fallback: raw output
    return
  }
  echo "$summary"
}

gate_failed=0

# ── 1. cargo fmt --check ─────────────────────────────────────────────────────

echo "▶ cargo fmt --check"
fmt_out=$(cd "$RUST_ROOT" && cargo fmt --check 2>&1) && fmt_status=0 || fmt_status=$?
if [[ $fmt_status -ne 0 ]]; then
  echo "[FAIL] fmt: run 'cargo fmt' to fix"
  gate_failed=1
else
  echo "[OK]  fmt"
fi

# ── 2. cargo clippy ──────────────────────────────────────────────────────────

echo ""
echo "▶ cargo clippy --workspace --all-targets -- -D warnings"
clippy_out=$(cd "$RUST_ROOT" && cargo clippy --workspace --all-targets -- -D warnings 2>&1) \
  && clippy_status=0 || clippy_status=$?

if [[ $clippy_status -ne 0 ]]; then
  echo "[FAIL] clippy:"
  compress "cargo clippy" "$clippy_out"
  gate_failed=1
else
  echo "[OK]  clippy"
fi

# ── 3. cargo test ────────────────────────────────────────────────────────────

echo ""
echo "▶ make test"
test_out=$(cd "$REPO_ROOT" && make test 2>&1) && test_status=0 || test_status=$?

if [[ $test_status -ne 0 ]]; then
  echo "[FAIL] tests:"
  compress "cargo test" "$test_out"
  echo ""
  echo "If snapshot tests failed, run: cargo insta review"
  gate_failed=1
else
  echo "[OK]  tests"
fi

# ── 4. project-specific integrity check ──────────────────────────────────────
# Example: registry ↔ store consistency. Replace with whatever startup-fatal
# invariants your project enforces. Skip the whole stanza if you don't have
# one yet.

# echo ""
# echo "▶ registry ↔ inventory consistency"
# integrity_out=$(
#   cd "$RUST_ROOT" \
#     && cargo run --quiet -p registry -- validate 2>&1 \
#     && cargo run --quiet --bin gen-expected-entries -- --check 2>&1
# ) && integrity_status=0 || integrity_status=$?
#
# if [[ $integrity_status -ne 0 ]]; then
#   echo "[FAIL] integrity:"
#   compress "registry integrity" "$integrity_out"
#   gate_failed=1
# else
#   echo "[OK]  integrity"
# fi

# ── summary ──────────────────────────────────────────────────────────────────

echo ""
if [[ $gate_failed -eq 0 ]]; then
  echo "✓ all gates green"
else
  echo "✗ one or more gates failed — fix before pushing"
  exit 1
fi
