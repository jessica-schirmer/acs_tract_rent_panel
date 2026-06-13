# Pipeline
## Project: ADU Rent
## Processing phase: Create ACS rent, rent change, and covariates dataset.
## Overview
This repository covers selection of variables, cleaning, and creation of analysis measures for 2012-2016 and 2020-2024 ACS for 2010 tracts.

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

Outputs:
- `../../../data/acs_step2_24.feather` — 2020-2024 ACS measures aggregated to 2010 tracts (SCAG region), with interpolated rent, missing- and top-coded-rent shares, share, vacancy-rate, and CV measures.
- `../../../data/acs_step2_16.feather` — 2012-2016 ACS tract measures (SCAG region), with top-code/missing/zero flags, share, vacancy-rate, and CV measures.

Schema:
- `schemas/acs_step2_16.md`
- `schemas/acs_step2_24.md`

Steps:
1. Set up environment (packages, helper functions from `R/assemble_helpers.R`, data directory, SCAG target counties)
2. Assemble 2020-2024 ACS tract measures (merge crosswalk, restrict to SCAG, censor top-codes, weight-aggregate block groups to 2010 tracts, derive interpolated rent / missing- and top-coded-rent shares / share / vacancy-rate / CV measures, save)
3. Prepare 2012-2016 ACS tract measures (restrict to SCAG, flag and censor top-coded/missing/zero values, build share, vacancy-rate, and CV measures, save)
4. Validate outputs (key uniqueness, missingness, flag encoding, numeric distributions)


## Step 3: Create ACS panel, calculate change variables
Script: `03_merge.Rmd`

Inputs:
- `../../../data/acs_step2_16.feather` — 2012-2016 ACS tract measures (SCAG region).
- `../../../data/acs_step2_24.feather` — 2020-2024 ACS tract measures (SCAG region), aggregated to 2010 tracts.

Outputs:
- `../../../data/acs_full.feather` — the ACS tract panel: 2016 and 2024 measures (2016 dollars inflation-adjusted to 2024) side by side on `tr2010_id`, with change ("POST") ratios and their coefficients of variation.

Schema:
- `schemas/acs_full.md`

Steps:
1. Set up environment (packages, helper functions from `R/merge_helpers.R`, data directory)
2. Import and prepare the 2020-2024 and 2012-2016 tract measures (rename with year suffix, select, inflation-adjust 2016 dollars to 2024)
3. Merge the two surveys (full join on tr2010_id, keep all tracts) and calculate change variables — level ratios (`*POST`) for dollar/count measures and percentage-point differences (`*PPC`) for share/rate measures (renter-occupied share, vacancy rates) — plus CVs, then save the panel
4. Validate output (key uniqueness, missingness, flag encoding, numeric distributions)


