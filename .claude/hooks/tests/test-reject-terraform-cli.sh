#!/usr/bin/env bash
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../reject-terraform-cli.sh"
. "$HERE/_lib.sh"

# ── BLOCK cases ─────────────────────────────────────────────────────────────

assert_blocks "terraform plan (bare)" "$HOOK" \
  '{"tool_input":{"command":"terraform plan"}}'

assert_blocks "terraform apply with cd prefix" "$HOOK" \
  '{"tool_input":{"command":"cd infra && terraform apply"}}'

assert_blocks "terraform init" "$HOOK" \
  '{"tool_input":{"command":"terraform init -backend-config=local"}}'

assert_blocks "terraform fmt" "$HOOK" \
  '{"tool_input":{"command":"terraform fmt -recursive"}}'

# ── ALLOW cases ─────────────────────────────────────────────────────────────

assert_allows "tofu plan (the right tool)" "$HOOK" \
  '{"tool_input":{"command":"tofu plan"}}'

assert_allows "git commit prose mentioning terraform" "$HOOK" \
  '{"tool_input":{"command":"git commit -m \"chore: blocks the bare terraform CLI\""}}'

assert_allows "ls of a terraform-named dir" "$HOOK" \
  '{"tool_input":{"command":"ls terraform-application"}}'

assert_allows "terraform-docs (different binary)" "$HOOK" \
  '{"tool_input":{"command":"terraform-docs markdown ."}}'

report "reject-terraform-cli" || exit 1
