---
name: new-registry-entry
description: Example "registry + store + schema triad" recipe. Use whenever a new entry is added on one side of a two-file invariant enforced at runtime startup (store file ↔ runtime inventory list ↔ optional schema mapping).
allowed-tools: Bash, Read, Edit, Write
---

# /new-registry-entry — add an entry to a registry/store pair

Example recipe for the "config as code" pattern: adding a new entry is a
*three-file change*, not a one-file change. Skipping any of the three
causes silent breakage somewhere between local dev (cache miss) and
production (runtime startup validation fails).

**Fork the file paths and field names below for your project's actual
registry layout.**

## Inputs

Ask the user for any of these that aren't already clear:
- **Category + name** — e.g. `category/entry_name`. Lowercase
  snake_case. Category groups related rows.
- **Role / variant** — if your registry has a system / user split (or
  similar), pick one. Document which side drives runtime behavior.
- **Body** — the content of the new entry (template, configuration,
  whatever your registry holds).
- **Response struct** — if structured output is involved, the Rust
  struct (must derive `JsonSchema`) and where it lives.

## Steps (in order)

1. **Store file** — `store/<category>/<name>.yaml`. Copy the shape of an
   existing peer. The required fields typically include:

   ```yaml
   category: <category>         # required — must match the dir name
   name: <name>                 # required — must match the file stem
   role: system                 # required — variant indicator
   description: <one-line summary>
   version: 1                   # monotonic integer
   content: |
     <body>
   # plus any config-spec fields (model, temperature, etc.)
   environments:
     local: { version: 1 }
     dev:   { version: 1 }
     uat:   { version: 1 }
     prod:  { version: 1 }
   ```

   The store file's config fields are the **dev-authoring tip** — the
   body spec. Production runtime selection may still read from a
   separate `activeSpec` row in your central config service (which can
   override or pin to an older version per-env). The rule "no hardcoded
   config in source code" applies to **source files** — the YAML store
   IS the blessed location for these values.

2. **Inventory entry** — append `("<category>", "<name>")` to the
   runtime inventory list (e.g. `EXPECTED_ENTRIES` in
   `shared/src/services/inventory.rs`). Group with peers of the same
   category. Without this entry, the service passes locally but fails
   cold-start in production startup validation.

3. **Schema mapping (only if structured output)** — append to the
   schema registry (e.g. `bin/gen_schemas.rs`):

   ```rust
   entry::<YourResponseStruct>("<category>", "<name>"),
   ```

   The response struct must derive `JsonSchema`. Re-run the schema
   exporter if you want to inspect what the runtime will accept.

4. **Seed locally** — restart the cache so the new row is reachable:

   ```bash
   make registry-apply ARGS="--env local --yes"   # push store → local DB
   ```

   Then **restart the dev server** — the cache is per-process. A push
   is not instant for warm processes.

5. **Verify integrity** — both gates pass:

   ```bash
   <your registry validate command>
   <your inventory check command>
   ```

   `/check` typically runs both as one of its steps.

6. **Activate in the central config service (sister system)** — before
   merging, the entry needs an `activeSpec` published in your central
   config service. Without this, the runtime falls back to a
   last-resort default. Document the activation row in your PR body.

## What not to do

- Don't hardcode config values (model name, temperature) in **source
  files**. The YAML store is the dev-authoring source for those values
  (the central config service can override at runtime).
- Don't introduce a new `APP_*` env var for config selection. The
  spec-driven path is the only blessed mechanism.
- Don't call external APIs directly from the call site. Use the shared
  traced client wrappers.
- Don't forget to capture trace IDs on entities that may later be
  reviewed (anything a human can later edit or override). No trace ID
  on the entity = no downstream correlation possible.
