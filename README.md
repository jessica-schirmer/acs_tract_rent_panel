# Pipeline
## Project: ADU Rent
## Processing phase: Create ACS rent, rent change, and covariates dataset.
## Overview
This repository covers selection of variables, cleaning, and creation of analysis measures for 2012-2016 and 2020-2024 ACS for 2010 tracts.

Assembly covers five Southern California counties plus the nine Bay Area counties.
The named `southern_california_counties` and `bay_area_counties` sets and their
union, `target_counties`, are centralized in `02_assemble.Rmd` §1.3. Both
vintages use that destination geography. The 2024 allocation retains all source
block groups contributing to those 2010 tracts, including sources outside the
target counties, with the original NHGIS fractions (no renormalization).

01_acs.Rmd - import selected variables from the 2012-2016 ACS (tracts) and 2020-2024 ACS (block groups); import cross-walk for 2024 block groups to 2010 tracts
02_assemble.Rmd - import ACS data; merge 2020-2024 data with 2010 tract crosswalk and aggregate 2020-2024 block group variables to 2010 tracts; import missind data flags and uncertainty measures
03_merge.Rmd - import 2024 ACS measures aggregated to 2010 tracts and merge w/ 2016 ACS measures; calculate change variables; save ACS tract panel



# Source / Inputs
Census API


# Processing Plan



## Step 1: Import ACS data
Script: `01_acs.Rmd`

Inputs:
- US Census Bureau ACS 5-year API (via `tidycensus`): 2012-2016 ACS at the tract
  level and 2020-2024 ACS at the block-group level, California. Requires a Census
  API key (`CENSUS_API_KEY`).
- `../../../data-raw-temp/nhgis/nhgis_bg2020_tr2010_06/nhgis_bg2020_tr2010_06.csv`
  — NHGIS crosswalk, 2020 block groups to 2010 tracts (allocation weights).
- `../../../data-raw-temp/nhgis/nhgis_tr2000_tr2010_06/nhgis_tr2000_tr2010_06.csv`
  — NHGIS crosswalk, 2000 tracts to 2010 tracts (allocation weights).

Outputs:
- `../../../data/acs_step1_16.feather` — 2012-2016 ACS estimates, one row per 2010 CA tract.
- `../../../data/acs_step1_24.feather` — 2020-2024 ACS estimates, one row per 2020 CA block group.
- `../../../data/xwalk_bg24_tr10.feather` — 2020 block group to 2010 tract crosswalk weights.
- `../../../data/xwalk_tr00_tr10.feather` — 2000 tract to 2010 tract crosswalk weights.

Schema:
- `schemas/acs_step1_16.md`
- `schemas/acs_step1_24.md`
- `schemas/xwalk_bg24_tr10.md`
- `schemas/xwalk_tr00_tr10.md`

Steps:
1. Set up environment (packages, helper functions from `R/helpers.R`, relative data paths)
2. Define the target ACS variables to extract
3. Import and prepare the 2012-2016 ACS tract data (download, derive low-rent counts, check MOE, rename ID, save)
4. Import and prepare the 2020-2024 ACS block-group data (parallel to step 3)
5. Import and prepare the geographic crosswalks (bg2020->tr2010, tr2000->tr2010)
6. Validate the saved outputs (key uniqueness, missingness, flag encoding, numeric distributions)


## Step 2: Assemble geographically consistent tract measures for later years
Script: `02_assemble.Rmd`

Inputs:
- `../../../data/acs_step1_24.feather` — 2020-2024 ACS estimates, one row per 2020 CA block group.
- `../../../data/xwalk_bg24_tr10.feather` — 2020 block group to 2010 tract allocation weights.
- `../../../data/acs_step1_16.feather` — 2012-2016 ACS estimates, one row per 2010 CA tract.
- Optional prior step-2 Feathers in `parity_reference_dir` — schema and Southern
  California parity references, read before saving.

Outputs:
- `../../../data/acs_step2_24.feather` — 2020-2024 ACS measures aggregated to 2010 tracts (Southern California + Bay Area), with interpolated rent, missing- and top-coded-rent shares, share, vacancy-rate, and CV measures.
- `../../../data/acs_step2_16.feather` — 2012-2016 ACS tract measures (Southern California + Bay Area), with top-code/missing/zero flags, share, vacancy-rate, and CV measures.

Schema:
- `schemas/acs_step2_16.md`
- `schemas/acs_step2_24.md`

Steps:
1. Set up environment (packages, `R/assemble_helpers.R` and shared `R/geography_qa.R`, data directory, named target counties, prior-output parity references)
2. Assemble 2020-2024 ACS tract measures (select destination crosswalk rows, join all contributing sources, check allocation weights, censor top-codes, aggregate and derive measures, check Southern California parity, save)
3. Prepare 2012-2016 ACS tract measures (select the same target counties, flag/censor values, build share, vacancy-rate, and CV measures, check parity, save)
4. Validate outputs (key uniqueness, county coverage, missing/top-coded rent by county, flag encoding, numeric distributions)


## Step 3: Create ACS panel, calculate change variables
Script: `03_merge.Rmd`

Inputs:
- `../../../data/acs_step2_16.feather` — 2012-2016 ACS tract measures (Southern California + Bay Area).
- `../../../data/acs_step2_24.feather` — 2020-2024 ACS tract measures (Southern California + Bay Area), aggregated to 2010 tracts.
- Existing `../../../data/acs_full.feather`, if present — column/type reference.

Outputs:
- `../../../data/acs_full.feather` — the ACS tract panel: 2016 and 2024 measures (2016 dollars inflation-adjusted to 2024) side by side on `tr2010_id`, with change ("POST") ratios and their coefficients of variation.

Schema:
- `schemas/acs_full.md`

Steps:
1. Set up environment (packages, `R/merge_helpers.R` and `R/geography_qa.R`, data directory, prior panel schema reference)
2. Import and prepare the 2020-2024 and 2012-2016 tract measures (rename with year suffix, select, inflation-adjust 2016 dollars to 2024)
3. Merge the two surveys (full join on tr2010_id, keep all tracts) and calculate change variables — level ratios (`*POST`) for dollar/count measures and percentage-point differences (`*PPC`) for share/rate measures (renter-occupied share, vacancy rates) — plus CVs, then save the panel
4. Validate output (key union and one-period-only membership from original input keys, county coverage, missingness, flag encoding, numeric distributions)

Analyst validation of the extension:

- Run stage 2 from the cached statewide ACS and crosswalk Feathers, then stage 3.
  A fresh stage-1 download is not needed for this geographic change. Codex
  validation uses syntax checks and synthetic data only, without production writes.
- Before running, preserve the prior step-2 outputs and set `parity_reference_dir`
  in stage 2 to that directory for repeatable comparisons. The default reads
  existing `data_dir` outputs into memory before saving; after a run those files
  become the new outputs. Missing references explicitly leave parity unverified.
- Inspect county counts for both vintages and the final panel: all 14 target
  counties must be populated, including the Bay Area, with no unintended
  destination counties. Stage 3 inherits the county set validated by stage 2.
- Crosswalk pairs and tract keys must be unique at their documented grains;
  selected allocations and tract-level joins must all match without row
  multiplication. Full source weights sum to one within `1e-6`; retained weights
  can sum below one and must remain identical to their original fractions.
  Assertion failures stop notebook execution.
- `socal_parity_16` and `socal_parity_24` compare every output column, reporting
  changed values and added/removed keys. Unaffected Southern California records
  must agree within numeric tolerance. Review boundary-group differences with
  `socal_boundary_contributions`, which identifies newly included sources and
  their weights/allocated counts. Use unchanged inputs for a valid comparison.
- Review raw and post-censoring rent missingness/top-codes by county. No empirical
  missingness threshold is imposed; unexplained county anomalies require review.
- Inspect `panel_membership`/`saved_panel_membership` for one-period-only tracts;
  these use original input keys, independently of the output's constant `base_id`.
  Column names/order/types are checked against prior files when available and
  across saving/reloading. Feather filenames and schemas remain unchanged.

The inspection's income-censoring and dollar-MOE discrepancies remain separate
research decisions; their executable behavior is unchanged. This cleaning-stage
expansion does not expand downstream analysis filters or supporting data. See
the stage's interface in [the shared pipeline document](../../PIPELINE.md).
