#!/usr/bin/env bash
# Run every hook test suite. Exit 0 if all pass, 1 if any fail.

HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE" || exit 1

if ! command -v jq >/dev/null 2>&1; then
  echo "✗ jq is required to run hook tests (used by both hooks and assertions)"
  exit 1
fi

total=0
failed=()

for f in test-*.sh; do
  [[ -e "$f" ]] || continue
  total=$((total + 1))
  echo ""
  echo "▶ $f"
  if ! bash "$f"; then
    failed+=("$f")
  fi
done

echo ""
echo "════════════════════════════════════════════════"
if [[ "${#failed[@]}" -eq 0 ]]; then
  echo "✓ all $total hook test suites passed"
  exit 0
fi

echo "✗ ${#failed[@]}/$total suites failed:"
printf '  - %s\n' "${failed[@]}"
exit 1
