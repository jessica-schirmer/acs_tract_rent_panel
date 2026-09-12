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

01_acs.Rmd - import selected variables from the 2012-2016 ACS (tracts) and 2020-2024 ACS (tracts and block groups); import cross-walk for 2024 block groups to 2010 tracts
02_assemble.Rmd - import ACS data; merge 2020-2024 data with 2010 tract crosswalk and aggregate 2020-2024 block group variables to 2010 tracts; import missind data flags and uncertainty measures
03_merge.Rmd - import 2024 ACS measures aggregated to 2010 tracts and merge w/ 2016 ACS measures; calculate change variables; save ACS tract panel



# Source / Inputs
Census API


# Processing Plan



## Step 1: Import ACS data
Script: `01_acs.Rmd`

Inputs:
- US Census Bureau ACS 5-year API (via `tidycensus`): 2012-2016 ACS at the tract
  level and 2020-2024 ACS at both tract and block-group levels, California.
  Requires a Census API key (`CENSUS_API_KEY`).
- `../../../data-raw-temp/nhgis/nhgis_bg2020_tr2010_06/nhgis_bg2020_tr2010_06.csv`
  — NHGIS crosswalk, 2020 block groups to 2010 tracts (allocation weights).
- `../../../data-raw-temp/nhgis/nhgis_tr2000_tr2010_06/nhgis_tr2000_tr2010_06.csv`
  — NHGIS crosswalk, 2000 tracts to 2010 tracts (allocation weights).

Outputs:
- `../../../data/acs_step1_2016_tract.feather` — 2012-2016 ACS estimates, one row per 2010 CA tract.
- `../../../data/acs_step1_2024_block_group.feather` — 2020-2024 ACS estimates, one row per 2020 CA block group.
- `../../../data/acs_step1_2024_tract.feather` — 2020-2024 ACS estimates, one row per 2020 CA tract, available for later assembly.
- `../../../data/xwalk_bg24_tr10.feather` — 2020 block group to 2010 tract crosswalk weights.
- `../../../data/xwalk_tr00_tr10.feather` — 2000 tract to 2010 tract crosswalk weights.

Schema:
- [2016 tract schema](schemas/acs_step1_2016_tract.md)
- [2024 block-group schema](schemas/acs_step1_2024_block_group.md)
- [2024 tract schema](schemas/acs_step1_2024_tract.md)
- `schemas/xwalk_bg24_tr10.md`
- `schemas/xwalk_tr00_tr10.md`

Steps:
1. Set up environment (packages, explicit block-group exclusions, helper functions from `R/helpers.R`, relative data paths)
2. Define the target ACS variables to extract
3. Import and prepare the 2012-2016 ACS tract data (download, derive low-rent counts, check MOE, rename ID, save)
4. Import and prepare the 2020-2024 ACS block-group data (using the available subset)
5. Import and prepare the 2020-2024 ACS tract data (using the full tract list)
6. Import and prepare the geographic crosswalks (bg2020->tr2010, tr2000->tr2010)
7. Validate all five saved outputs (required/omitted columns, row preservation, key uniqueness, missingness, flag encoding, numeric distributions)

Both tract requests share `tract_vars` (**65 aliases / 62 distinct Census
codes**). The 2024 block-group request uses `block_group_vars` (**62 aliases /
59 codes**), derived by removing exactly `rent1bdr` (B25031_003), `rent2bdr`
(B25031_004), and `rent3bdr` (B25031_005). Their estimate/MOE pairs remain in
tract outputs and are omitted from the block-group output. The explicit
`block_group_unavailable_vars` configuration follows package setup and
`rm(list = ls())` in §1.2; the installed geography lookup lacks 2024 entries
and is not used to infer exclusions.

All selected B25111 measures (B25111_001–005, including the total) and B25113
measures (B25113_002–003) are removed from both years. `vac_forrent` (B25004_002)
is retained and `vac_rented` (B25004_003, rented, not occupied) is added to all
three requests. Other mappings, including renter-occupied units, the rental
distribution, and for-sale vacancy, are preserved. The three duplicate-code
aliases (`grent_3`, `grent_20`, `grent_26`) remain configured; tidycensus wide
output uses each code's first alias, so request counts are not column counts.
The 2016 low-rent cutoffs remain categories 1–17 / 1–19; both 2024 outputs use
1–18 / 1–20. Stage 2 continues to use block groups for 2024; the new tract file
is available for later assembly.

### Stage-1 input migration

The revised filenames under `../../../data/` are:

| Historical filename | Current filename | Geographic key |
|---|---|---|
| `acs_step1_16.feather` | `acs_step1_2016_tract.feather` | `tr2010_id` |
| `acs_step1_24.feather` | `acs_step1_2024_block_group.feather` | `bg2020_id` |
| No prior file | `acs_step1_2024_tract.feather` | `tr2020_id` |

Retain all existing data files. The analyst must generate the newly named
inputs by running the revised stage 1; renaming or copying old caches cannot
supply the revised variables. The crosswalk filenames (`xwalk_bg24_tr10.feather`
and `xwalk_tr00_tr10.feather`) remain unchanged. Full API execution and output
regeneration are analyst-run work, outside this implementation.

After running stage 1, inspect §7 for all five outputs: no required columns
missing or excluded pairs present; imported and reloaded row counts agree;
keys are unique and non-missing; flags are logical, non-missing, constant
`TRUE`; and estimate missingness/numeric distributions have been reviewed.
Crosswalk weights must be finite and in [0, 1]. No empirical ACS row count or
missingness threshold is imposed.

**Stage-2 parity compatibility remains a follow-up.** Its 2016 pass-through
output loses seven estimate/MOE pairs (`rentmv1yr`, `rentmv5yr`, `rentyrblt`,
`rentyrblt_14_16`, `rentyrblt_10_13`, `rentyrblt_00_09`, `rentyrblt_90_99`) and
gains `vac_rentedE/M`. Existing snapshots will fail strict schema comparison,
so the current parity checks cannot validate that regenerated output against
older snapshots. Preserve the checks and reference snapshots for the follow-up;
a missing reference means parity is unverified. The removed measures have no
direct downstream calculation references. Stage-2 executable changes in this
implementation are limited to the two input filenames; rental-inventory
calculations, geographic harmonization, and censoring are unchanged.


## Step 2: Assemble geographically consistent tract measures for later years
Script: `02_assemble.Rmd`

Inputs:
- `../../../data/acs_step1_2024_block_group.feather` — 2020-2024 ACS estimates, one row per 2020 CA block group.
- `../../../data/xwalk_bg24_tr10.feather` — 2020 block group to 2010 tract allocation weights.
- `../../../data/acs_step1_2016_tract.feather` — 2012-2016 ACS estimates, one row per 2010 CA tract.
- Optional prior step-2 Feathers in `parity_reference_dir` — schema and Southern
  California parity references, read before saving. The configured directory is
  `../../../data/parity_reference`.

Outputs:
- `../../../data/acs_step2_24.feather` — 2020-2024 ACS measures aggregated to 2010 tracts (Southern California + Bay Area), with interpolated rent, missing- and top-coded-rent shares, share, vacancy-rate, and CV measures.
- `../../../data/acs_step2_16.feather` — 2012-2016 ACS tract measures (Southern California + Bay Area), with top-code/missing/zero flags, share, vacancy-rate, and CV measures.

Schema:
- `schemas/acs_step2_16.md`
- `schemas/acs_step2_24.md`

Steps:
1. Set up environment (packages, `R/assemble_helpers.R` and shared `R/geography_qa.R`, data directory, named target counties, prior-output parity references)
2. Assemble 2020-2024 ACS tract measures (select destination crosswalk rows, join all contributing sources, check allocation weights, capture legacy/corrected income expectations before censoring, aggregate and derive measures, check Southern California parity, save)
3. Prepare 2012-2016 ACS tract measures (select the same target counties, capture income expectations before flagging/censoring, build share, vacancy-rate, and CV measures, check parity, save)
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

Analyst validation of assembly and the panel (after stage-1 migration and the parity follow-up):

- The earlier geographic extension alone used cached statewide inputs. With
  the revised stage-1 contract, generate the new inputs first and resolve the
  parity compatibility follow-up above before validating stages 2 and 3.
  Focused income validation runs with `Rscript tests/test_income_censoring.R`;
  it exercises income expectations and the parity helper using synthetic inputs.
- Before running, preserve the prior step-2 outputs and set `parity_reference_dir`
  in stage 2 to that directory for repeatable comparisons. It is configured as
  `../../../data/parity_reference`; saving candidates in `data_dir` does not
  replace those snapshots. Missing references explicitly leave parity unverified.
- Inspect county counts for both vintages and the final panel: all 14 target
  counties must be populated, including the Bay Area, with no unintended
  destination counties. Stage 3 inherits the county set validated by stage 2.

- Crosswalk pairs and tract keys must be unique at their documented grains;
  retained allocations and tract-level joins must all match without row
  multiplication. Unmatched crosswalk links are reported with their IDs/weights
  and excluded only when all four weights are finite and exactly zero; matched
  zero-weight links remain. Missing sources with any positive or missing/invalid
  weight still fail validation. Exclusions must preserve destination tract
  coverage. Full source weights sum to one within `1e-6`; retained weights
  can sum below one and must remain identical to their original fractions.
  Assertion failures stop notebook execution.
  [Note: conditions met when 02_assemble.Rmd runs without error.]
- `socal_parity_16` and `socal_parity_24` compare every output column, reporting
  changed values and added/removed keys. Each changed cell is classified as
  `verified_income_correction`, `boundary_review`, or `unexpected`, with counts
  in `difference_summary` and the complete values in `differences`. For
  geographically unaffected tracts, only changed `med_hhincE`/`med_hhincCV` cells
  matching both the expected legacy reference and corrected candidate may pass.
  Expectations use uncensored source incomes and the existing household weights
  (2024); both CV expectations use the reference income MOE and existing formula.
  Candidate MOEs, all other columns, and tract membership remain subject to
  ordinary parity. The existing tolerance is unchanged, and the helper remains
  strict when `expected_income = NULL`. Review boundary differences with
  `socal_boundary_contributions`, which identifies newly included sources and
  their weights/allocated counts. Use unchanged inputs for a valid comparison.
- Review raw and post-censoring rent missingness/top-codes by county. No empirical
  missingness threshold is imposed; unexplained county anomalies require review.
- Inspect `panel_membership`/`saved_panel_membership` for one-period-only tracts;
  these use original input keys, independently of the output's constant `base_id`.
  Column names/order/types are checked against prior files when available and
  across saving/reloading. Stage-2 and panel filenames remain unchanged; the
  2016 pass-through schema changes as described in the migration above.

Income is retained independently of missing or top-coded rent, following the
analyst decision; see the [income correction and acceptance checks](notes/income_censoring.md).
The inspection's dollar-MOE discrepancy remains a separate research decision;
its executable behavior is unchanged. This cleaning-stage
expansion does not expand downstream analysis filters or supporting data. See
the stage's interface in [the shared pipeline document](../../PIPELINE.md).
