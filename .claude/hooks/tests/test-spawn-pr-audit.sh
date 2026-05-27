#!/usr/bin/env bash
# Trigger-logic tests for spawn-pr-audit.sh.
#
# We can't easily exercise the full spawn path inside a test harness
# (would actually shell out to Haiku), so this suite focuses on:
#   - which commands trip the trigger gate (via the additionalContext JSON
#     emitted when the audit is spawned);
#   - which commands stay silent.
#
# Strategy: stub `claude` to /bin/true so the gate logic runs end-to-end
# but no real model call happens. The audit will still spawn a detached
# runner — that's fine for testing because the runner respects
# AUDIT_OUT pointing at a temp dir.

HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../spawn-pr-audit.sh"
. "$HERE/_lib.sh"

# Stub `claude` so the runner doesn't try to actually call Haiku.
STUB_DIR="$(mktemp -d)"
cat > "$STUB_DIR/claude" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
chmod +x "$STUB_DIR/claude"
export PATH="$STUB_DIR:$PATH"

# Use a throwaway lock/audit dir so test runs don't pollute the repo.
SANDBOX="$(mktemp -d)"
export CLAUDE_PROJECT_DIR="$SANDBOX"

# Initialise a tiny git repo with a relevant changed file so the
# changed-file filter passes.
git -C "$SANDBOX" init -q
git -C "$SANDBOX" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
git -C "$SANDBOX" branch -M develop
git -C "$SANDBOX" checkout -q -b feature
mkdir -p "$SANDBOX/crates/foo/src"
echo 'fn r() {}' > "$SANDBOX/crates/foo/src/routing.rs"
git -C "$SANDBOX" add -A
git -C "$SANDBOX" -c user.email=t@t -c user.name=t commit -q -m "change"

# Cleanup on exit.
cleanup() {
  rm -rf "$STUB_DIR" "$SANDBOX"
}
trap cleanup EXIT

# ── ALLOW (no fire) cases — should be silent ─────────────────────────────────

assert_silent "git push feature branch" "$HOOK" \
  '{"tool_input":{"command":"git push origin feature"}}'

assert_silent "gh pr list" "$HOOK" \
  '{"tool_input":{"command":"gh pr list"}}'

assert_silent "git status" "$HOOK" \
  '{"tool_input":{"command":"git status"}}'

assert_silent "gh pr view" "$HOOK" \
  '{"tool_input":{"command":"gh pr view 319"}}'

# ── FIRE cases — should emit additionalContext JSON ──────────────────────────

# Reset the lock between fire cases so each one re-spawns.
rm -f "$SANDBOX/.claude/.audit-lock-feature"
mkdir -p "$SANDBOX/.claude/hooks" "$SANDBOX/.claude/prompts"
# Copy runner + prompt into the sandbox so the lock-clear path works
# even though the runner is stubbed via PATH'd claude. Without these the
# runner would print "prompt missing" but still clean up.
cp "$HERE/../_run-pr-audit.sh" "$SANDBOX/.claude/hooks/_run-pr-audit.sh"
cp "$HERE/../../prompts/pre-merge-audit.md" "$SANDBOX/.claude/prompts/pre-merge-audit.md"
chmod +x "$SANDBOX/.claude/hooks/_run-pr-audit.sh"

assert_emits_json "gh pr create" "$HOOK" \
  '{"tool_input":{"command":"gh pr create --title test"}}'

rm -f "$SANDBOX/.claude/.audit-lock-feature"
assert_emits_json "gh pr merge" "$HOOK" \
  '{"tool_input":{"command":"gh pr merge 319 --squash"}}'

rm -f "$SANDBOX/.claude/.audit-lock-feature"
assert_emits_json "git push origin develop" "$HOOK" \
  '{"tool_input":{"command":"git push origin develop"}}'

rm -f "$SANDBOX/.claude/.audit-lock-feature"
assert_emits_json "git push origin release" "$HOOK" \
  '{"tool_input":{"command":"git push origin release"}}'

rm -f "$SANDBOX/.claude/.audit-lock-feature"
assert_emits_json "git push origin main" "$HOOK" \
  '{"tool_input":{"command":"git push origin main"}}'

# ── Lock behaviour: second spawn within the same branch should still emit
#    additionalContext, but referencing the live pid. We just check that it
#    emits JSON (any of the two paths is acceptable).
assert_emits_json "second push while audit running" "$HOOK" \
  '{"tool_input":{"command":"git push origin develop"}}'

# ── ALLOW: changed files outside the relevant set should be silent ──────────

rm -f "$SANDBOX/.claude/.audit-lock-feature"
# Add an irrelevant change on a fresh branch
git -C "$SANDBOX" checkout -q develop
git -C "$SANDBOX" checkout -q -b irrelevant
echo "noise" > "$SANDBOX/README.md"
git -C "$SANDBOX" add -A
git -C "$SANDBOX" -c user.email=t@t -c user.name=t commit -q -m "readme only"

assert_silent "gh pr create with only README changes" "$HOOK" \
  '{"tool_input":{"command":"gh pr create --title docs"}}'

report "spawn-pr-audit" || exit 1
