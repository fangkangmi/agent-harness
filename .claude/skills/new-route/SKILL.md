---
name: new-route
description: Example "add an HTTP route" recipe — handler → service → route → contract → snapshot → integration test stub. Use when adding routes to any of your project's services.
allowed-tools: Bash, Read, Edit, Write
---

# /new-route — add an HTTP route to a service

Example "add a route" recipe. Each route flows handler → service → route
→ contract → snapshot. Don't skip or reorder. **Fork the file paths and
suite-directory mapping below for your project's actual layout.**

## Inputs

Ask the user for any of these that aren't already clear:
- **Service** — which deployable owns the route. Refuse to create a *new*
  service / deployable — that needs explicit user discussion.
- **Method + path** — e.g. `POST /resources/{id}/submit-for-action`. URLs
  use plural nouns and kebab-case actions.
- **Request / response shape** — JSON, camelCase. New optional fields use
  `#[serde(default)]` (in Rust) or equivalent.
- **Roles** — which auth context / role check applies.

## Steps (in order)

1. **Handler** in `<service>/src/<area>_handlers.rs`. Thin: extract
   state + auth context, delegate to the service. Return a result type;
   never panic.

2. **Service method** in `shared/src/services/<service>.rs`. Apply RBAC
   via the auth context. Business logic lives here, not in the handler.

3. **Repository call** through the trait — never the raw DB client.

4. **Wire the route** in `<service>/src/routing.rs`:
   ```rust
   .route("<path>", <method>(handler_fn))
   ```

5. **API contract** — update the OpenAPI spec (or equivalent). JSON:
   camelCase. Use existing schemas where possible.

6. **Snapshot tests** — if the response model is new or changed, run
   the project's snapshot test command and review:
   ```bash
   cargo test
   cargo insta review
   ```
   Code, snapshots, and contract must land in the same commit.

7. **Integration test stub** — drop a thin test file under the matching
   directory in the integration test tree. Reuse fixtures where
   possible — they typically form a pyramid (cheaper fixtures on top,
   richer ones built on top); pick the cheapest level that covers your
   route. At minimum, write one happy path + one auth/validation
   rejection. Pattern off the closest existing file.

   Don't bundle integration tests into `/check` — they require external
   services to be up. Run them yourself before PR.

8. **Local sanity check** — bring the service up and curl the endpoint
   with a token. Confirm the happy path before opening a PR.

## Stop early

If the request is more than a thin CRUD-style endpoint (touches async
queues, adds a new entity, changes auth semantics), stop after step 1
and remind the user: "this looks non-trivial — should we write a plan
in `docs/plans/` first?" (see `/new-plan`).
