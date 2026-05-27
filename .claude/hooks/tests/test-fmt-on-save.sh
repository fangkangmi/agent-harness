#!/usr/bin/env bash
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../fmt-on-save.sh"
. "$HERE/_lib.sh"

# Pre-flight: skip the suite if rustfmt isn't installed (CI containers
# without the Rust toolchain still pass).
if ! command -v rustfmt >/dev/null 2>&1; then
  echo "  skipped: rustfmt not in PATH"
  exit 0
fi

TMPDIR=$(mktemp -d)
trap "rm -rf '$TMPDIR'" EXIT

# ── SILENT cases ────────────────────────────────────────────────────────────

# Already-clean .rs file → silent (no auto-fmt notice).
cat > "$TMPDIR/clean.rs" <<'EOF'
fn main() {
    println!("hello");
}
EOF
assert_silent "already-clean rs file" "$HOOK" \
  "$(jq -nc --arg p "$TMPDIR/clean.rs" '{tool_name:"Edit",tool_input:{file_path:$p}}')"

# Non-rs file → silent.
echo "plain text" > "$TMPDIR/foo.txt"
assert_silent "non-rs file (txt)" "$HOOK" \
  "$(jq -nc --arg p "$TMPDIR/foo.txt" '{tool_name:"Edit",tool_input:{file_path:$p}}')"

# Non-Edit/Write tool → silent.
assert_silent "Read tool (irrelevant)" "$HOOK" \
  "$(jq -nc --arg p "$TMPDIR/clean.rs" '{tool_name:"Read",tool_input:{file_path:$p}}')"

# ── REFORMAT case ───────────────────────────────────────────────────────────

# Dirty .rs file → emit "auto-fmt: <basename>" + reformat.
printf 'fn main(){println!("x");}\n' > "$TMPDIR/dirty.rs"
assert_stdout_contains "dirty rs reformatted (notice emitted)" "$HOOK" \
  "$(jq -nc --arg p "$TMPDIR/dirty.rs" '{tool_name:"Edit",tool_input:{file_path:$p}}')" \
  "auto-fmt: dirty.rs"

# Verify the file was actually reformatted on disk.
expected="fn main() {
    println!(\"x\");
}"
actual=$(cat "$TMPDIR/dirty.rs")
if [[ "$actual" == "$expected" ]]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  FAILED_NAMES+=("dirty rs reformatted on disk (got: ${actual:0:80})")
fi

report "fmt-on-save" || exit 1
