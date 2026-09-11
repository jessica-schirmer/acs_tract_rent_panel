## Project: ADU Rent

## Overview
This repository selects, cleans, and constructs analysis measures from
2012–2016 and 2020–2024 ACS data for 2010 census tracts as part of the ADU Rent
pipeline. Reproducibility and auditability are priorities.

See `README.md` for stage details and `PIPELINE.md` for upstream/downstream data flow.

## Tech Stack
- R (tidyverse, haven, lme4, stargazer, renv)

## Project Structure
- Each analysis folder is its own repository root; `.Rmd` notebooks live there,
  numbered by pipeline stage.
- `schemas/` — data structure documentation; read before writing any code.
- `R/helpers.R` (and companion files such as `R/labels.R`) — reusable helper functions.
- `../../../data-raw-temp/` — shared raw source files (`ADU_Rent/data-raw-temp/`);
  never modify.
- `../../../data/` — shared processed outputs (`ADU_Rent/data/`); the integration
  point between pipeline stages.

## Data Access
- Raw source files under `data-raw-temp/` are strictly read-only. Never modify,
  rename, move, delete, or overwrite them.
- Consult `schemas/` before reading or writing data; never invent or hardcode
  row counts, column names, dtypes, or value encodings.
- Write processed data to `../../../data/`; never overwrite outputs silently.
- Ensure outputs can be traced back to their inputs and transformations.

## Coding Conventions
- Use `here::here()` for repository-relative paths. Do not use `setwd()` or
  hardcode user-specific absolute paths.
- Use `snake_case` for variable and function names.
- Git inspection commands are allowed (`git status`, `git diff`, `git log`,
  `git show`).
- Do not stage, commit, push, merge, rebase, checkout/switch branches, reset,
  or otherwise modify repository history or branch state unless explicitly
  requested.

## R Analysis Conventions
- Use `renv` to manage package versions.
- Prefer packages already declared in the project's `renv` environment.
  Do not install, update, or otherwise modify package dependencies without
  approval. If a new dependency is approved, record it in `renv.lock` as part
  of the same change.
- Load all required packages at the top of each script or notebook.
- Prefer tidyverse syntax; use base R only when it is clearly simpler.
- Set a random seed before any stochastic procedure.
- Be explicit about factor levels, missing values, date parsing, and type conversion.

## Documentation Sync
Treat documentation as part of the deliverable. When code changes, update the
affected docs in the same change:

- **README.md** — update when a notebook is added, removed, renamed, reordered,
  or its inputs, outputs, or pipeline-stage description changes.
- **`schemas/`** — update when an output structure changes, including columns,
  dtypes, key variables, or value encodings.
- **Notebook Overview** — update when sections, inputs, or outputs change; its
  step list must match the numbered top-level headings.
- **PIPELINE.md** — update when a stage's inputs, outputs, or relationship to
  upstream/downstream stages changes.
- **renv.lock** — update when an approved dependency is added or its required
  version changes.

Documentation updates required to keep existing documentation synchronized with
an authorized code change are implicitly authorized. Ask before introducing a
new project-wide convention, changing substantive research definitions, or
substantially reorganizing documentation beyond what the implementation requires.

## Workflow Rules
- Resolve routine implementation choices from existing code, documentation,
  schemas, and established patterns.
- Ask before choices that materially affect research logic, filtering, output
  contracts, destructive behavior, or external cost.
- Do not refactor existing code unless explicitly asked.
- Do not combine tasks from different pipeline stages into one notebook.

## R Markdown Notebook Standards
Notebooks should provide a transparent, reproducible record of the data workflow.

### Structure
Organize notebooks into clearly separated sections that move logically from
inputs through transformation and validation to outputs. Each section should
have a single clear purpose.

### Notebook Overview
Open each notebook with an unnumbered **Notebook Overview** listing:
- **Inputs** — source files and paths.
- **Outputs** — output files, paths, and purpose.
- **Steps** — numbered list matching the notebook's top-level `#` sections.

Keep this block synchronized with the code and numbered headings.

### Number sections and sub-sections
Number `#` and `##` headings hierarchically (for example, `# 1. Load data`,
`## 1.1 Read source file`). Do not number headings deeper than `##`.
Keep numbering contiguous, and renumber affected headings and the Notebook
Overview when sections are changed.

### Narrative prose vs. code chunks
Use R Markdown prose to document data quality issues, assumptions, ambiguities,
and non-obvious decisions. Use code comments only for brief implementation
details: if it explains *why*, use prose; if it explains *how*, use a short
comment.

### Log decisions explicitly
Document non-trivial cleaning choices (for example, filters, deduplication
rules, type conversions, or encoding decisions) in a `### Decision: ...` prose
block immediately before the relevant code, with a brief rationale.

### Keep code modular
- Put reusable or independently testable logic in `R/helpers.R` or a relevant
  companion helper file; keep one-off notebook logic inline.
- Load shared helpers at the top of each notebook with
  `source(here::here("R", "helpers.R"))` and equivalent companion files.

### Validation
Report row counts after each filtering or joining step and state the expected
behavior of the operation (for example, no row multiplication for a many-to-one
join). Do not invent or hardcode expected empirical row counts unless they are
established by documentation or source data.

Every notebook that modifies data must end with validation of row counts, key
uniqueness, missingness in critical variables, and relevant ranges or value
distributions. Flag unexpected results explicitly.

## Execution and Validation
- After changing executable code, perform inexpensive targeted validation when
  the required inputs and environment are available.
- Prefer syntax/parse checks, helper-level tests, inspection of changed logic,
  or small/sample-based execution.
- Do not knit or run full data-intensive notebooks, regenerate large outputs,
  or reproduce full-pipeline empirical results unless full execution is
  specifically necessary to the task.
- Treat expensive end-to-end execution as analyst-run validation. Implement
  required assertions, diagnostics, and QA code, and report the acceptance
  checks/results the analyst should inspect after running the pipeline.
- Do not incur external/API costs or overwrite existing outputs without
  authorization.
