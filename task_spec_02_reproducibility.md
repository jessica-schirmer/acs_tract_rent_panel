Fix paths and dependencies in the current repository so the ACS cleaning pipeline can run independently of the original research-project folder structure.

Start after the Git-history cleanup finishes. Follow applicable repository guidance. Use the completed audit findings below as authoritative; inspect code only to resolve implementation details. Make the smallest coherent changes without altering data definitions, geographic scope, sample rules, or calculations.

**Known issues**

- Notebooks 1–5 use `../../../data/` and `../../../data-raw-temp/`; some paths depend on the working directory.
- Writers assume output directories already exist.
- `renv.lock` omits `viridis`, although the recorded `Hmisc` dependency requires it.
- Notebook 4’s optional saving behavior can leave notebook 5 without its required panel.

**1. Centralize configurable data paths**

Data may remain outside the repository. Do not copy, move, or add raw or processed datasets to Git.

Reuse an existing path helper if suitable; otherwise create one concise shared R helper. Use:
- `ACS_RAW_DATA_DIR` for raw inputs.
- `ACS_DATA_DIR` for processed inputs and outputs.

Users should configure these through environment variables or an ignored local `.Renviron` file. Require explicit values when needed and provide an informative setup message when configuration is missing; do not silently fall back to the old parent-directory layout. A notebook should require only the directories it actually uses.

Accept absolute paths and resolve relative paths against the repository root. Use existing `here` conventions to locate the root reliably, without `setwd()` or assumptions about the surrounding research project.

Provide a tracked `.Renviron.example` containing placeholders and brief instructions, never actual credentials or machine-specific personal paths. Explain that users should restart R after editing `.Renviron`.

Update active notebooks, helpers, and affected tests to use the shared configuration. Preserve input filenames and their subdirectory structure, including NHGIS and Census locations. Keep figures and boundary caches under their existing repository-local `outputs/` paths.

Create required output directories before writing. For missing required raw files, report the exact expected location and point to setup instructions. Do not create empty placeholder inputs.

Preserve existing overwrite safeguards. Explain that the processed-data directory receives generated files and should be chosen accordingly.

**2. Make notebook 4 save the panel as a standard step**

Remove the `write_panel` option from `04_assemble_tract_panel.Rmd`. A successful run should save `acs_full.feather` to the configured processed-data directory.

- Run existing pre-save validation before writing.
- Preserve existing overwrite safeguards and post-save readback checks.
- Remove conditional branches and messages describing panel saving as optional.
- Update affected tests and documentation to reflect standard saving.
- Do not change panel contents, schema, filename, or calculations.
- Ensure first-run execution does not require a previous `acs_full.feather`; any comparison with an existing panel must remain conditional on its presence.

Keep historical parity references optional. Their absence must not prevent normal execution, and optional checks must not depend on the original project layout.

Keep notebook 5 dependent only on the saved ACS panel and public Census boundaries. Do not add the postponed ADU map or its external inputs.

**3. Repair dependency setup**

Inspect packages actually required by the active notebooks, helpers, tests, and rendering workflow.

- Resolve the `Hmisc`/`viridis` gap. If `Hmisc` is used, include its required dependency closure in the lockfile. If genuinely unused, remove the unnecessary load/declaration and update the lockfile accordingly.
- Ensure other directly required packages and their dependencies are represented.
- Preserve existing versions where feasible; do not broadly upgrade the environment.
- Ensure the repository includes the appropriate `renv` bootstrap/configuration files for a fresh checkout.
- Use supported dependency-management commands rather than fabricating lockfile entries.
- Do not install packages inside notebook chunks.

If installation is necessary, use the repository’s isolated environment and follow applicable installation-permission rules. Report unavailable dependencies or network limitations accurately.

**4. Update setup documentation and ignore rules**

Update the README and directly affected documentation to match the implementation. Consolidate with recent README edits rather than duplicating instructions.

Cover:
- R/environment restoration and required system dependencies.
- How to configure external raw-input and processed-data directories.
- Expected relative locations of the two NHGIS crosswalks and Census relationship file within the configured raw-input directory.
- Verified acquisition instructions or links for these manually supplied inputs.
- Census API-key setup through an ignored environment file or environment variable.
- Notebook execution order and the fact that notebook 4 saves the panel consumed by notebook 5.
- Which inputs users obtain manually, which the pipeline downloads, and which outputs it generates.

Explain that raw and intermediate datasets are not included in the public repository.

Document the 2000-to-2010 crosswalk as required if notebook 1 currently requires it, even though later stages do not consume it. Do not remove that processing step in this task.

Ignore local credentials, package libraries, caches, and any supported repository-local raw/processed data directories. Preserve tracking of `.Renviron.example`, intended example figures, and required `renv` bootstrap files. Avoid broad rules that hide source files or existing intentional diagnostic tables.

Do not modify `AGENTS.md` or `CLAUDE.md`, revisit history cleanup, or perform unrelated cleanup.

**5. Targeted validation**

Perform:
- R/Rmd parsing and relevant existing helper tests.
- Small tests of absolute and relative directory settings, missing configuration, output-directory creation, and informative missing-input errors.
- A small synthetic check of notebook 4’s save/readback behavior, including first-run execution without an existing panel.
- Checks that active execution paths no longer depend on the parent research-project layout.
- Dependency consistency and required-package loading checks.
- A search for obsolete `write_panel` references in active code and current documentation.

Use temporary directories for tests; do not write test outputs into existing research-data directories.

If feasible, verify `renv::restore()` in a temporary isolated library outside the working environment. Do not disturb the existing library. Report whether restoration was actually tested.

Do not download full ACS datasets, run data-intensive notebooks, regenerate the empirical panel, or replace example figures. Full pipeline execution remains analyst-run.

**Handoff**

Report files changed, path-configuration behavior, dependency changes, validation completed, and remaining blockers. Provide concise instructions for the analyst to restore the environment, configure directories and the API key, supply raw inputs, and run the notebook sequence.

Do not commit, push, publish, or rewrite Git history.