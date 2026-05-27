#!/usr/bin/env bash
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../reject-unwrap-in-prod.sh"
. "$HERE/_lib.sh"

# ── BLOCK cases ─────────────────────────────────────────────────────────────

assert_blocks "Write prod .rs with .unwrap()" "$HOOK" \
  '{"tool_name":"Write","tool_input":{"file_path":"/repo/crates/foo/src/lib.rs","content":"fn handler() {\n    let x = foo().unwrap();\n}\n"}}'

assert_blocks "Write prod .rs with .expect(" "$HOOK" \
  '{"tool_name":"Write","tool_input":{"file_path":"/repo/crates/foo/src/lib.rs","content":"let x = bar().expect(\"infallible\");"}}'

assert_blocks "Edit ADDS new .unwrap() (not in old_string)" "$HOOK" \
  '{"tool_name":"Edit","tool_input":{"file_path":"/repo/foo.rs","old_string":"fn a() {\n    println!(\"old\");\n}","new_string":"fn a() {\n    let x = bar().unwrap();\n    println!(\"new\");\n}"}}'

# ── ALLOW cases ─────────────────────────────────────────────────────────────

assert_allows "tests/ directory" "$HOOK" \
  '{"tool_name":"Write","tool_input":{"file_path":"/repo/crates/foo/tests/contract_tests.rs","content":"let x = foo().unwrap();"}}'

assert_allows "*_tests.rs (snake-case test module)" "$HOOK" \
  '{"tool_name":"Write","tool_input":{"file_path":"/repo/crates/foo/src/snapshot_tests.rs","content":"#[test]\nfn t() { let x = foo().unwrap(); }\n"}}'

assert_allows "fixtures/ directory" "$HOOK" \
  '{"tool_name":"Write","tool_input":{"file_path":"/repo/crates/foo/tests/fixtures/data.rs","content":"let x = foo().unwrap();"}}'

assert_allows "build.rs" "$HOOK" \
  '{"tool_name":"Write","tool_input":{"file_path":"/repo/crates/foo/build.rs","content":"let x = std::env::var(\"OUT_DIR\").unwrap();"}}'

assert_allows "// allow-unwrap suppression marker" "$HOOK" \
  '{"tool_name":"Write","tool_input":{"file_path":"/repo/foo.rs","content":"let x = CONST.parse::<u32>().unwrap(); // allow-unwrap: const"}}'

assert_allows "Edit PRESERVES existing unwrap (in both old and new)" "$HOOK" \
  '{"tool_name":"Edit","tool_input":{"file_path":"/repo/foo.rs","old_string":"fn a() {\n    let x = bar().unwrap();\n    println!(\"old\");\n}","new_string":"fn a() {\n    let x = bar().unwrap();\n    println!(\"new\");\n}"}}'

assert_allows "no unwrap/expect at all" "$HOOK" \
  '{"tool_name":"Write","tool_input":{"file_path":"/repo/foo.rs","content":"let x = bar()?;"}}'

assert_allows "non-rs file" "$HOOK" \
  '{"tool_name":"Write","tool_input":{"file_path":"/repo/foo.md","content":"foo().unwrap()"}}'

assert_allows "Write src/foo.rs with .unwrap() inside #[cfg(test)] mod tests" "$HOOK" \
  '{"tool_name":"Write","tool_input":{"file_path":"/repo/src/foo.rs","content":"fn prod() { 1 + 1; }\n\n#[cfg(test)]\nmod tests {\n    use super::*;\n    #[test]\n    fn t() {\n        let x = foo().unwrap();\n    }\n}\n"}}'

assert_blocks "Write src/foo.rs with .unwrap() outside but #[cfg(test)] mod present" "$HOOK" \
  '{"tool_name":"Write","tool_input":{"file_path":"/repo/src/foo.rs","content":"fn prod() {\n    let x = foo().unwrap();\n}\n\n#[cfg(test)]\nmod tests {\n    #[test]\n    fn t() { let y = bar().unwrap(); }\n}\n"}}'

report "reject-unwrap-in-prod" || exit 1
