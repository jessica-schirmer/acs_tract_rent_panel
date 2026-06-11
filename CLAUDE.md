
## Project: ADU Rent
## Processing phase: Clean ACS tract data

Processing phase: This repository covers selection of variables, cleaning, and creation of analysis measures for 2012-2016 and 2020-2024 ACS for 2010 tracts.

## Overview
Academic research project evaluating the impact of ADU policy on rents. 

Pipeline stages split across cleaning and analysis steps, each with subtrees. 
This is a cleaning substree. The analysis stages examine the impact of ADU production following
policy change on market rents and contract rents, and include unit-level hedonic
rent analyses of ADU status, drawing on RentHub rental listing data, ACS
measures, and housing market characteristics. 

Primary analyst is a solo researcher; reproducibility and auditability are top priorities. 

See README.md for context and details on this pipeline stage. 
See PIPELINE.md for how outputs flow into downstream pipeline stages.

## Tech Stack
- R (tidyverse, haven, lme4, stargazer, renv)

## Project Structure
- Each analysis folder is its own repository root; `.Rmd` notebooks live there, numbered by pipeline stage
- `schemas/` — data structure documentation; read before writing any code
- `R/helpers.R` (and companion files such as `R/labels.R`) — reusable helper functions
- `../../../data-raw-temp/` — shared raw source files (`ADU_Rent/data-raw-temp/`); never modify
- `../../../data/` — shared processed outputs (`ADU_Rent/data/`); the integration point between pipeline stages

## Data Access
- Never modify data in `data-raw-temp/`
- Consult `schemas/` before reading or writing data; never hardcode row counts or column names
- Write processed data to `../../../data/`; never overwrite raw files or overwrite outputs silently
- Ensure outputs can be traced back to their inputs and transformations

## Coding Conventions
- Use relative paths for all file references; never hardcode absolute paths
- Use `snake_case` for all variable and function names
- Comment every non-obvious transformation with a plain-language explanation
- Commit working code with descriptive git commit messages

## R Analysis Conventions
- Use `renv` to manage package versions
- Load all required packages at the top of each script or notebook
- Prefer tidyverse syntax; use base R only when it is clearly simpler
- Set a random seed before any stochastic procedure
- Be explicit about factor levels, missing values, date parsing, and type conversion
- Document model formulas, standard error choices, and any clustering or weighting decisions
- Treat cleaned pipeline outputs as the default input to analysis code

## Documentation Sync
Treat documentation as part of the deliverable. When code changes, update the
affected docs in the **same** change — not in a later pass. Before finishing any
task, re-read these and confirm they describe what the code actually does:

- **README.md** — update whenever a notebook is added, removed, renamed,
  reordered, or when its inputs, outputs, or pipeline-stage description changes.
  The pipeline overview must match the current set of notebooks and their order.
- **`schemas/`** — update or create the relevant schema file whenever an output
  file's structure changes (new/removed/renamed columns, changed dtypes, changed
  key variables, changed value encodings). If unsure which file applies, ask.
- **Notebook Overview block** — update whenever sections are added, removed,
  reordered, or when the notebook's inputs or outputs change (see Notebook
  Standards). The enumerated step list must match the numbered `#` headings.

If doc updates for a change are non-trivial, list the edits you intend to make
and confirm before writing them. Never leave a notebook where its code and its
Notebook Overview disagree.

## Workflow Rules
- Before writing any code, propose a plan and wait for approval
- When uncertain about scope, ask rather than assume
- Do not run `git push` without explicit instruction
- Do not merge or commit anything — the researcher reviews all changes

## What NOT to Do
- Do not refactor existing code unless explicitly asked
- Do not install new packages without listing them and asking first
- Do not combine tasks from different pipeline stages into one notebook

## R Markdown Notebook Standards

Notebooks should read like a **transparent, step-by-step record of the data
workflow**. Prioritize readability, auditability, and reproducibility.

### Structure
Organize each notebook into clearly separated sections that move logically from
inputs to outputs. A typical sequence is: load data, inspect/summarize,
clean/transform, validate/QA, save outputs — but the exact set and ordering
should fit the notebook's purpose (e.g., a modeling step between transformation
and validation). Each section should have a single clear purpose.

### Notebook Overview block
Open each notebook with a short prose block listing **Inputs**, **Outputs**, and
**Steps**:

- **Inputs** — source files read, with paths
- **Outputs** — files written, with paths and a one-line purpose for each
- **Steps** — an enumerated list mirroring the top-level (`#`) section numbers
  and titles

Input/output paths must match what the code actually reads and writes; update
this block whenever they change (see Documentation Sync). The block itself is
not numbered.

```markdown
## Notebook Overview
**Inputs:** `../../../data-raw-temp/renthub_listings.csv` (raw RentHub listings)
**Outputs:** `../../../data/listings_deduped.rds` (deduplicated listings, one row per unit)

This notebook:
1. Loads raw RentHub listing data
2. Checks for duplicates and missing tract IDs
3. Applies deduplication rules
4. Validates row counts and key constraints
5. Writes cleaned outputs to `../../../data/`
```

### Number sections and sub-sections
Number `#` and `##` headings using hierarchical decimal numbering applied
directly in the heading text (e.g., `# 1. Load data`, `## 1.1 Read raw RentHub
file`, `## 1.2 Confirm expected columns`, `# 2. Inspect / summarize data`). Do
not number headings deeper than `##` (e.g., `### Decision: Deduplication rule`
stays unnumbered).

- Numbering starts at 1 within each level and stays contiguous; sub-section
  numbers reset under each new parent.
- When sections are added, removed, reordered, renamed, or split, renumber every
  affected `#` and `##` heading in the same change and update the Notebook
  Overview block to match.

### Use action-oriented headings
Prefer verb-based section headings: "Check duplicates and deduplicate" not
"Duplicate check"; "Merge property and unit datasets" not "Merging". Use nouns
only when clearly more appropriate (e.g., "Inputs", "Outputs", "Validation
Summary").

### Narrative prose vs. code chunks
Use R Markdown prose blocks (not code comments) to document data quality issues
and assumptions, ambiguities and how they were resolved, and non-obvious design
decisions. Use code comments only for short implementation details.
**Rule of thumb:** if it explains *why*, write prose; if it explains *how*, use
a brief inline comment.

### Log decisions explicitly
When making a non-trivial choice (a filter rule, a deduplication strategy),
write a prose decision block immediately before the relevant code chunk:

````rmarkdown
### Decision: Deduplication rule

We keep the most recent listing per (`property_id`, `unit_id`) using `date_posted`.

**Rationale:**
- Multiple listings exist per unit over time
- Most recent observation reflects current market state

```{r deduplicate-listings}
listings_deduped <- listings |>
  arrange(desc(date_posted)) |>
  distinct(property_id, unit_id, .keep_all = TRUE)
```
````

Analytic decisions get the same treatment as cleaning decisions: model
specification, sample restrictions, fixed-effects/clustering/weighting choices,
and how pre-trends or treatment definitions are operationalized each warrant a
decision block with rationale before the relevant chunk.

### Keep code modular
- Break complex logic into small, well-named functions; avoid very long chunks
- Use clear variable names; avoid abbreviations unless standard in the field
- Define reusable helpers in `R/helpers.R` (documented with roxygen-style `#'`
  comments) rather than inline; keep one-off, notebook-specific logic inline
- Load shared code at the top of each notebook with
  `source(here::here("R", "helpers.R"))` (and companions such as `R/labels.R`)

### Always include a validation section
Report row counts immediately after each filtering or joining step, stating
expected vs. actual — where "expected" is what the operation should produce (an
exact target, a rough retention band, or no change for a join meant only to
attach columns) — so row loss or unintended duplication is caught at the step
that causes it, not only in the final tally.

Every notebook that modifies data must also end with a section that checks
duplicate counts, key uniqueness, missing values on critical variables, and flag
variables encoded as string labels (not 0/1 integers), and that summarizes the
distribution of the model/analytic variables (not all intermediate columns),
flagging unexpected ranges, missingness, or factor levels. State expected vs.
actual results explicitly.

### Write outputs transparently
Label each output file and describe its purpose in prose before writing it.
