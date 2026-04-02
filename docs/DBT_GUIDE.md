# dbt guide (BTC project)

This document summarizes dbt concepts and commands used in this repository. For authoritative reference, see the [dbt Developer Hub](https://docs.getdbt.com/).

---

## 1. `dbt_project.yml` and its reference

`dbt_project.yml` is the **root configuration** for your dbt project. It defines:

- **Project identity**: `name` (must match how models are nested under `models:`) and `version`.
- **Profile**: `profile` links to an output in `~/.dbt/profiles.yml` (here: `BTC`).
- **Paths**: where dbt looks for models, seeds, tests, macros, snapshots, etc.
- **Defaults**: global configs under `models: <project_name>:` (e.g. materialization for `marts/`).

**Reference**: [dbt_project.yml](https://docs.getdbt.com/reference/dbt_project.yml)

In this repo, `BTC` models under `marts/` default to `table` materialization and run post-hooks (including `create_latest_version_view()`).

---

## 2. Jinja in dbt

dbt compiles SQL **templates** with **Jinja** (`{% ... %}` and `{{ ... }}`). Typical uses:

- **`{{ ref('model_name') }}`**: reference another model (build order + dependency graph).
- **`{{ source('source_name', 'table_name') }}`**: reference a declared source.
- **`{{ this }}`**: the relation for the current model being built.
- **`{% if is_incremental() %} ... {% endif %}`**: conditional SQL for incremental runs.
- **`{{ config(...) }}`**: set materialization, tags, schema, etc.

**Reference**: [Jinja + dbt](https://docs.getdbt.com/docs/build/jinja-macros)

---

## 3. Materialization and precedence

**Materialization** is how dbt persists a model in the warehouse (view, table, incremental, ephemeral, etc.).

**Precedence** (highest wins):

1. Config in the model file: `{{ config(materialized='table') }}`
2. Config in `schema.yml` / property files under `config:`
3. Config in `dbt_project.yml` under `models: <project>: <path>: ...`

**Reference**: [Materializations](https://docs.getdbt.com/docs/build/materializations)

---

## 4. dbt installation and version check

Install dbt for your warehouse adapter (this project uses Snowflake):

```bash
pip install dbt-core dbt-snowflake
```

Check versions:

```bash
dbt --version
```

You should see **dbt-core** and **adapter** versions. Keep them compatible with your project and CI.

---

## 5. `dbt init` and `dbt debug`

- **`dbt init <project_name>`**: scaffolds a new dbt project (directories, starter `dbt_project.yml`, etc.). Use once when creating a project; this repo is already initialized.

- **`dbt debug`**: validates setup—Python environment, `profiles.yml`, connection to the warehouse, and project parsing. Always run after changing profiles or credentials.

```bash
dbt debug
dbt debug --target prod   # use a specific output from profiles.yml
```

**Note**: `dbt debug` does **not** write a full `manifest.json` the way parse/compile/run do.

---

## 6. `dbt run` with a single model (`-m` / `--select`)

Build one (or more) models:

```bash
dbt run -m stg_btc
# preferred in newer dbt:
dbt run --select stg_btc
```

`-m` is a legacy shorthand for `--select`. Selection supports graph operators (`+stg_btc`, `stg_btc+`, tags, etc.).

**Reference**: [Model selection syntax](https://docs.getdbt.com/reference/node-selection/syntax)

---

## 7. `dbt build`

`dbt build` is a **single command** that runs **`dbt run`** and **`dbt test`** for the same selection in one invocation. For each selected node, dbt builds the resource (model, seed, snapshot, etc.) and then runs **tests attached to that resource** where applicable—so you get “build then verify” without switching between `run` and `test`.

Typical uses:

```bash
# Full project: run all runnable nodes, then run their tests (default selection)
dbt build

# Same selection syntax as dbt run / dbt test
dbt build --select stg_btc
dbt build --select +whale_alert
dbt build --target prod
```

Notes:

- **Snapshots and seeds** are included in `build` when selected; tests run in dependency-aware order with the rest of the DAG.
- Optional flags (e.g. **`--empty`**) depend on your dbt version; see the command reference for your install.
- For **only** models without tests in the same pass, `dbt run` is still fine; use **`dbt build`** when you want run + test in one pipeline step (local dev or CI).

**Reference**: [`dbt build`](https://docs.getdbt.com/reference/commands/build)

---

## 8. Main YAML files in this project

| File | Role |
|------|------|
| **`dbt_project.yml`** | Project name, profile, paths, default model configs. |
| **`packages.yml`** | Declares dbt packages (e.g. `dbt-labs/dbt_utils`); consumed by `dbt deps`. |
| **`models/sources.yml`** | Declares **sources** (raw tables), including **freshness** and `loaded_at_field`. |
| **`models/schema.yml`** | Documents and tests **models** (columns, tests, **versions**, **contracts**, **exposures**). |

You can split YAML into multiple files under `models/`; dbt merges them by resource type.

---

## 9. Source freshness

Freshness checks how **stale** loaded data is in a source table, using a timestamp column.

In `models/sources.yml` (example from this repo):

- **`loaded_at_field`**: column dbt uses for “last load” time (e.g. `BLOCK_TIMESTAMP`).
- **`warn_after`**: e.g. data older than **1 hour** → warning.
- **`error_after`**: e.g. older than **3 hours** → error (non-zero exit when strict).

Run:

```bash
dbt source freshness
```

**Reference**: [Source freshness](https://docs.getdbt.com/reference/resource-properties/freshness)

---

## 10. `dbt test`

Tests validate model logic and data quality (unique, not_null, relationships, custom tests, etc.).

Typical flow:

```bash
# Build the model first (tests run against built relations unless singular SQL tests say otherwise)
dbt run -m stg_btc

# Run tests (default: all tests in the project)
dbt test
```

To **run and test in one step**, use **`dbt build`** (see **§7** above).

Narrow selection:

```bash
dbt test --select stg_btc
```

**Reference**: [Tests](https://docs.getdbt.com/docs/build/tests)

---

## 11. Incremental models

Incremental models **append or merge** new data instead of rebuilding the whole table every run—better for large fact tables.

**Core ideas**:

- Use `{{ config(materialized='incremental', ...) }}` and `{% if is_incremental() %}` to restrict the query to new rows.
- Choose an **incremental strategy** appropriate to your warehouse (merge, append, delete+insert, etc.).

**References**:

- [Incremental models](https://docs.getdbt.com/docs/build/incremental-models)
- [Incremental strategies](https://docs.getdbt.com/docs/build/incremental-strategy)

---

## 12. Incremental model — **merge** strategy (`stg_btc`)

This repo’s `stg_btc` uses **incremental** materialization with **`merge`** and **`unique_key: 'HASH_KEY'`**.

Behavior:

- On incremental runs, dbt only pulls rows **newer than** the max `BLOCK_TIMESTAMP` already in the target (see `WHERE` + `is_incremental()` in the model).
- **`dbt run -m stg_btc --full-refresh`** rebuilds the table from scratch (ignores incremental slice).

Use **`--debug`** for verbose logs (SQL compilation, connection steps, etc.):

```bash
dbt run -m stg_btc --debug
```

---

## 13. `LATERAL FLATTEN` in Snowflake

Snowflake’s **`LATERAL FLATTEN`** turns **array / semi-structured** data (e.g. `VARIANT` arrays) into **one row per element**.

In `stg_btc_outputs`, the `outputs` array is flattened so each output (address + value) becomes its own row. A `WHERE` clause drops rows with no address.

**Reference**: [FLATTEN](https://docs.snowflake.com/en/sql-reference/functions/flatten) (Snowflake docs)

---

## 14. Incremental model — **append** strategy (`stg_btc_outputs`)

`stg_btc_outputs` uses **`incremental_strategy: 'append'`**: new rows are **appended** each run (no merge by key).

- The incremental filter limits new data (e.g. by `block_timestamp` vs `max(block_timestamp)` in `{{ this }}`).
- **`LATERAL FLATTEN`** unpacks the `outputs` array into rows.
- **`dbt run -m stg_btc_outputs --debug`** shows detailed execution logs.

---

## 15. Ephemeral models

**Ephemeral** models are **not** built as database objects; their SQL is **inlined** into downstream models that `ref()` them. Use for shared CTEs / intermediate logic.

**Command example** (building a downstream model that may depend on ephemeral nodes):

```bash
dbt run -m whale_alert --debug
```

In **this** project, `whale_alert` is a **versioned** mart (not ephemeral); the command above is still the usual way to **run** that model and inspect behavior with `--debug`.

**Reference**: [Ephemeral materialization](https://docs.getdbt.com/docs/build/materializations#ephemeral)

---

## 16. `dbt seed`

**Seeds** load CSV files from the `seed-paths` folder into the warehouse as tables.

```bash
dbt seed
dbt seed --select my_seed_name
```

Use seeds for small reference data—not for large production extracts.

**Reference**: [Seeds](https://docs.getdbt.com/docs/build/seeds)

---

## 17. Macros in dbt

**Macros** are reusable Jinja functions (often SQL snippets or control flow). They live under `macros/` (e.g. `create_latest_version_view()` in this repo).

Invoke with `{{ macro_name(...) }}` or use `{% macro %} ... {% endmacro %}` definitions.

**Reference**: [Macros](https://docs.getdbt.com/docs/build/jinja-macros#macros)

---

## 18. `profiles.yml`

`profiles.yml` (usually `~/.dbt/profiles.yml`) defines **connection targets**: account, user, role, database, schema, **outputs** named `dev`, `prod`, etc.

**Never commit secrets**; use env vars or secret managers in CI.

**Production examples**:

```bash
dbt seed --target prod
dbt run --target prod
```

**Reference**: [profiles.yml](https://docs.getdbt.com/docs/core/connect-data-platform/connection-profiles)

---

## 19. `manifest.json`

After commands that **parse** the project (e.g. `run`, `compile`, `parse`), dbt writes **`target/manifest.json`**—a full description of nodes, sources, configs, and dependency maps (`parent_map` / `child_map`).

Used by docs, state comparison, lineage tools, and **defer**.

**Reference**: [Manifest JSON file](https://docs.getdbt.com/reference/artifacts/manifest-json)

---

## 20. Creating a new profile output in `profiles.yml`

Under your profile (e.g. `BTC`), add another **`outputs:`** entry:

```yaml
BTC:
  target: dev
  outputs:
    dev:
      type: snowflake
      account: ...
      # ...
    prod:
      type: snowflake
      account: ...
      # ...
```

Set `target:` to the default output, or pass `--target prod` on the CLI.

---

## 21. Defer and production `manifest.json`

**Defer** lets you run a subset of models **without** rebuilding upstream objects that already exist in another environment, by comparing to a **state** artifact (a `manifest.json` from a prior run).

Typical pattern:

1. In production (or a gold environment), produce a manifest:

   ```bash
   dbt compile --target prod
   ```

2. Copy **`target/manifest.json`** (and optionally other artifacts) into a folder at the project root, e.g. **`state/`**.

3. From another workspace or CI, run with:

   ```bash
   dbt run -m whale_alert --defer --state state
   ```

dbt skips rebuilding refs that are unchanged vs the state manifest when those relations are assumed to exist in the **current** target (see dbt docs for full rules).

**Reference**: [Defer](https://docs.getdbt.com/reference/node-selection/defer)

---

## 22. Zero-copy cloning — `dbt clone`

**`dbt clone`** uses Snowflake **zero-copy cloning** (or equivalent patterns) to duplicate schemas/tables quickly from a reference state.

Example:

```bash
dbt clone --state state
```

Requires a valid **state** directory (manifest from the reference build). Exact behavior depends on adapter support and dbt version.

**Reference**: [dbt clone](https://docs.getdbt.com/reference/commands/clone)

---

## 23. Defer vs clone

| | **Defer** | **Clone** |
|---|-----------|-----------|
| **Purpose** | Run selected models while **reusing** unchanged upstream logic vs a **state manifest**; avoid rebuilding what already matches. | **Replicate** database objects (e.g. zero-copy) from a reference environment/state. |
| **Typical use** | Slim CI, partial runs against prod metadata. | Fast environment copies for dev/QA. |

Both often involve a **`--state`** path pointing at artifacts from a reference run.

---

## 24. Python models

dbt can run **Python** models (adapter-dependent; Snowflake Python UDFs / Snowpark patterns). This repo includes `stg_btc_outputs_py.py`, which uses `dbt.ref("stg_btc")` and returns a DataFrame-like result.

**Reference**: [Python models](https://docs.getdbt.com/docs/build/python-models)

---

## 25. dbt packages and `dbt deps`

`packages.yml` lists packages (GitHub or dbt Hub). Install them into `dbt_packages/`:

```bash
dbt deps
```

This project pins **`dbt-labs/dbt_utils`** (see `packages.yml`).

**Reference**: [Packages](https://docs.getdbt.com/docs/build/packages)

---

## 26. Using a `dbt_utils` test in `schema.yml`

Package tests are namespaced by package. Example from this repo (`equal_rowcount` comparing two models):

```yaml
tests:
  - dbt_utils.equal_rowcount:
      compare_model: ref('stg_btc_outputs_py')
```

After changing `packages.yml`, run `dbt deps` and ensure the package version matches your dbt version.

**Reference**: [dbt_utils](https://github.com/dbt-labs/dbt-utils)

---

## 27. `dbt docs`

Generate static documentation (manifest + catalog):

```bash
dbt docs generate
dbt docs serve
```

`generate` writes artifacts under `target/`; `serve` starts a local web server for the DAG, descriptions, and column metadata.

**Reference**: [Documentation](https://docs.getdbt.com/docs/collaborate/documentation)

---

## 28. Exposures and Looker (Looker Studio) connectivity

**Exposures** document **downstream** uses of dbt models (dashboards, ML jobs, apps). They appear in lineage and docs.

In `schema.yml`, `btc_whale_alert_exposure` points to a **Looker Studio** URL and `depends_on: ref('whale_alert', v=2)`.

Looker / Looker Studio do **not** auto-sync from dbt; the **`url`** field is documentation and discoverability. Real connectivity is via your warehouse or semantic layer as you design it.

**Reference**: [Exposures](https://docs.getdbt.com/docs/build/exposures)

---

## 29. Generic tests from `tests/generic/`

**Generic tests** are parameterized tests defined with `{% test ... %}` in `tests/generic/` (e.g. `assert_valid_btc_address` in `tests/generic/crypto_utils.sql`).

They are referenced in YAML like built-in tests:

```yaml
data_tests:
  - assert_valid_btc_address
```

Run tests for one model:

```bash
dbt test --select whale_alert
```

**Reference**: [Generic data tests](https://docs.getdbt.com/docs/build/data-tests#generic-data-tests)

---

## 30. Model contracts in `schema.yml`

A **contract** enforces **column names and types** at build time (`contract.enforced: true` on the model config).

`whale_alert` in this repo defines columns with `data_type` and `contract: enforced: true`, so dbt validates the created relation against the contract.

**Reference**: [Model contracts](https://docs.getdbt.com/docs/collaborate/govern/model-contracts)

---

## 31. Versioned models and `dbt run`

This project versions **`whale_alert`** (`latest_version: 2`, `versions:` in `schema.yml`).

Run **default / both resolution** behavior depends on selection and `latest_version`; commonly:

```bash
dbt run --select whale_alert
```

To select explicitly by version (syntax may vary slightly by dbt version):

```bash
dbt run --select "whale_alert,version:latest"
```

Use `dbt ls --select whale_alert` to see how dbt resolves versions.

**Reference**: [Model versions](https://docs.getdbt.com/docs/mesh/model-versions)

---

## 32. `dbt-ci.yml` (GitHub Actions)

Workflow: **`.github/workflows/dbt-ci.yml`**

- Triggers on **pull requests** and **pushes** to `master` / `main` / `dev` / `dev2`.
- Computes **`PUSH_BRANCH`** (`head` on PRs, `ref` on push) and **`MERGE_BRANCH`** (PR **base**, or same as ref on push).
- Maps **`MERGE_BRANCH`** → **`DBT_TARGET`**: `master|main` → `prod`, `dev2` → `dev2`, `dev` → `dev`.
- Uses GitHub **environment** `DBT_BTC` and secrets for `profiles.yml` + private key.
- Runs **`dbt deps`**, **`dbt debug`**, **`dbt run`** with `--target "$DBT_TARGET"`. You can swap **`dbt run`** for **`dbt build`** if you want tests in the same job (longer runs).

Adjust the `case` block if your branch naming or Snowflake outputs change.

---

## Quick command cheat sheet

| Goal | Command |
|------|---------|
| Install packages | `dbt deps` |
| Check setup | `dbt debug` |
| Run one model | `dbt run --select stg_btc` |
| Run + test (same selection) | `dbt build` or `dbt build --select stg_btc` |
| Full refresh incremental | `dbt run --select stg_btc --full-refresh` |
| Source freshness | `dbt source freshness` |
| All tests | `dbt test` |
| Tests for one model | `dbt test --select whale_alert` |
| Docs | `dbt docs generate` && `dbt docs serve` |
| Prod run | `dbt run --target prod` |
| Defer | `dbt run --select whale_alert --defer --state state` |
| Clone | `dbt clone --state state` |

---

*Generated for the BTC dbt project. Update branch → target mappings and examples if your workflows change.*
