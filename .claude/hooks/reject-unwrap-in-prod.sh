#!/usr/bin/env python3
"""PreToolUse hook on Edit/Write of .rs files: block changes that ADD
`.unwrap()` / `.expect()` to non-test Rust production code.

Background: a common project rule forbids panics in production paths and
explicitly disallows `.unwrap()` / `.expect()` on fallible operations.

Test code is exempt in two ways:
  1. By path:    tests/, *_tests.rs, *_test.rs, test_helpers.rs,
                 fixtures/, benches/, examples/, build.rs.
  2. By context: `#[cfg(test)] mod NAME { ... }` blocks inside any .rs
                 file. Detected by walking the post-edit file and
                 tracking `{`/`}` depth from the cfg(test) line.

Suppression: add `// allow-unwrap` on the same line if the operation is
provably infallible (e.g. parsing a compile-time const). Use sparingly.

The hook:
  • applies the Edit/Write to a synthetic post-edit copy of the file;
  • diffs pre→post to identify ADDED line numbers;
  • flags only added lines that contain `.unwrap()` or `.expect(` AND
    fall outside every `#[cfg(test)]` block.
This avoids false positives when an Edit preserves a pre-existing
unwrap in the surrounding context.

This hook is Rust-specific; adapt the pattern (or remove the hook) for
other stacks.
"""

import difflib
import json
import re
import sys


TEST_PATH_RE = re.compile(
    r"(?:/tests/"
    r"|_test\.rs$"
    r"|_tests\.rs$"
    r"|/test_helpers\.rs$"
    r"|/fixtures/"
    r"|/benches/"
    r"|/examples/"
    r"|/build\.rs$)"
)
VIOLATION_RE = re.compile(r"\.unwrap\(\)|\.expect\(")
ALLOW_RE = re.compile(r"allow-unwrap")
CFG_TEST_RE = re.compile(r"#\[cfg\(test\)\]")
MOD_OPEN_RE = re.compile(r"\bmod\s+\w+[^{]*\{")


def find_test_ranges(lines):
    """Return inclusive 1-indexed (start, end) ranges covering each
    `#[cfg(test)] mod NAME { ... }` block in `lines`. Brace counting is
    naive — it doesn't strip strings or comments — which is fine for the
    common case (no `{`/`}` chars inside test-mod string literals at the
    top level)."""
    ranges = []
    i = 0
    n = len(lines)
    while i < n:
        if not CFG_TEST_RE.search(lines[i]):
            i += 1
            continue
        # Scan forward up to a few lines for `mod NAME { ... `.
        j = i
        scan_limit = min(i + 6, n)
        while j < scan_limit and not MOD_OPEN_RE.search(lines[j]):
            j += 1
        if j >= scan_limit or not MOD_OPEN_RE.search(lines[j]):
            i += 1
            continue
        depth = lines[j].count("{") - lines[j].count("}")
        start = i + 1  # 1-indexed
        end = j + 1
        j += 1
        while j < n and depth > 0:
            depth += lines[j].count("{") - lines[j].count("}")
            end = j + 1
            j += 1
        ranges.append((start, end))
        i = j
    return ranges


def added_line_numbers(pre_lines, post_lines):
    """Set of 1-indexed line numbers in `post_lines` that are inserted
    or replaced relative to `pre_lines`."""
    matcher = difflib.SequenceMatcher(a=pre_lines, b=post_lines, autojunk=False)
    added = set()
    for tag, _i1, _i2, j1, j2 in matcher.get_opcodes():
        if tag in ("insert", "replace"):
            added.update(range(j1 + 1, j2 + 1))
    return added


def main():
    try:
        data = json.loads(sys.stdin.read())
    except json.JSONDecodeError:
        return 0

    tool = data.get("tool_name")
    if tool not in ("Edit", "Write"):
        return 0

    ti = data.get("tool_input", {})
    file_path = ti.get("file_path", "")
    if not file_path.endswith(".rs"):
        return 0
    if TEST_PATH_RE.search(file_path):
        return 0

    if tool == "Write":
        pre_content = ""
        post_content = ti.get("content", "")
    else:  # Edit
        old_s = ti.get("old_string", "")
        new_s = ti.get("new_string", "")
        try:
            with open(file_path, "r", encoding="utf-8") as f:
                disk_content = f.read()
        except OSError:
            disk_content = ""
        if disk_content and disk_content.count(old_s) == 1:
            pre_content = disk_content
            post_content = disk_content.replace(old_s, new_s, 1)
        else:
            # File unreadable or old_string not uniquely matched.
            # Fall back to analyzing just the chunk being swapped.
            # Hook unit tests that pass fictitious paths take this branch.
            pre_content = old_s
            post_content = new_s

    pre_lines = pre_content.splitlines()
    post_lines = post_content.splitlines()
    test_ranges = find_test_ranges(post_lines)
    added = added_line_numbers(pre_lines, post_lines)

    def in_test_range(lineno):
        return any(s <= lineno <= e for (s, e) in test_ranges)

    violations = []
    for lineno in sorted(added):
        line = post_lines[lineno - 1]
        if not VIOLATION_RE.search(line):
            continue
        if ALLOW_RE.search(line):
            continue
        if in_test_range(lineno):
            continue
        violations.append((lineno, line.rstrip()))

    if not violations:
        return 0

    err = sys.stderr
    print("Blocked: change adds .unwrap() / .expect() in a production path.", file=err)
    print("", file=err)
    print("Project rule (error handling) forbids:", file=err)
    print("  • Panics in handlers — use a proper error type", file=err)
    print("  • .unwrap() / .expect() on fallible ops in production code", file=err)
    print("", file=err)
    print("Lines:", file=err)
    for lineno, text in violations:
        print(f"{lineno}:{text}", file=err)
    print("", file=err)
    print("Use `?` with proper error mapping instead:", file=err)
    print("  let x = foo()?;", file=err)
    print("  let x = foo().map_err(MyError::from)?;", file=err)
    print("  let x = foo().ok_or(MyError::NotFound)?;", file=err)
    print("", file=err)
    print("If the operation is provably infallible (parsing a compile-time", file=err)
    print("const, unwrapping after a bounds check, etc.), suppress by adding", file=err)
    print("`// allow-unwrap` on the same line. Use sparingly.", file=err)
    print("", file=err)
    print("Test code is auto-exempt by path (tests/, *_tests.rs, fixtures/,", file=err)
    print("benches/, examples/, build.rs) and by context (`#[cfg(test)] mod", file=err)
    print("NAME { ... }` blocks inside any .rs file).", file=err)
    return 2


if __name__ == "__main__":
    sys.exit(main())
