# Pipeline
## Project: ADU Rent
## Processing phase: Create ACS rent, rent change, and covariates dataset.
## Overview
This repository prepares 2012-2016 ACS tract measures, 2020-2024 block-group measures aggregated to 2010 tracts, and a separate 2020-2024 tract-source product on native 2020 tracts.

Step 3 separately identifies geographically consistent 2010–2020 tract pairs
from Census geographic intersections for all California 2020 tracts. Its
crosswalk supports later comparison of the two native tract-source products.

Assembly covers five Southern California counties plus the nine Bay Area counties.
The named `southern_california_counties` and `bay_area_counties` sets and their
union, `target_counties`, are centralized in `02_assemble.Rmd` §1.3. All three
products use those counties while retaining their documented tract vintages.
The 2024 block-group allocation retains all source
block groups contributing to those 2010 tracts, including sources outside the
target counties, with the original NHGIS fractions (no renormalization).

01_acs.Rmd - import selected variables from the 2012-2016 ACS (tracts) and 2020-2024 ACS (tracts and block groups); import cross-walk for 2024 block groups to 2010 tracts
02_assemble.Rmd - aggregate 2020-2024 block groups to 2010 tracts; prepare 2016 and 2024 tract-source measures separately; construct rental inventory with explicit missingness, data flags, and uncertainty measures for all three products
03_tract_change.Rmd - characterize statewide 2010–2020 tract intersections and save a 2020-tract crosswalk identifying exact geographic consistency
04_merge.Rmd - retain the 2016/block-group 2024 key union, select canonical 2024 bundles by geographic consistency, retain smfE and sfd_detE levels for both years, calculate changes including separate rental inventory change, retain source comparisons, and optionally save the panel



# Source / Inputs
Census API

Local NHGIS crosswalks and the Census 2020-to-2010 tract relationship file.


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
- `../../../data/acs_step1_2024_tract.feather` — 2020-2024 ACS estimates, one row per 2020 CA tract, consumed by the separate Step 2 tract-source path.
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
1–18 / 1–20. Stage 2 consumes both 2024 inputs separately: block groups are
aggregated to 2010 tracts, and the tract source retains its native 2020 geography.

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

**Stage-2 parity compatibility is implemented through a narrow allowlist.**
`compare_socal_parity()` stays strict by default (`schema_migration = NULL`).
The notebook opts into fixed migrations for the two existing products:

| Vintage / `schema_migration` | Permitted additions relative to older references | Permitted removals |
|---|---|---|
| 2016 / `"2016"` | `vac_rentedE`, `vac_rentedM`, `rhu_inventoryE` | Estimate/MOE pairs for `rentmv1yr`, `rentmv5yr`, `rentyrblt`, `rentyrblt_14_16`, `rentyrblt_10_13`, `rentyrblt_00_09`, `rentyrblt_90_99` |
| 2024 block-group aggregated / `"2024"` | `rhu_inventoryE` | None |

Actual additions/removals appear in `schema_changes`; unlisted differences fail.
Shared columns retain strict order, storage type/class, and value checks,
including the existing income-correction and geographic classifications.
Inventory is validated independently before saving and after reloading even
when absent from a reference. Save/reload schema checks remain strict for every
column. Preserve all reference snapshots; a missing reference remains **parity
not checked**. The removed source measures have no direct downstream calculation
references. Step 4 selects canonical 2024 bundles by geography and adds separate inventory
levels/change; `rhuPOST` remains occupied-renter change.


## Step 2: Assemble 2016 tract and separate 2024 block-group/tract measures
Script: `02_assemble.Rmd`

Inputs:
- `../../../data/acs_step1_2024_block_group.feather` — 2020-2024 ACS estimates, one row per 2020 CA block group.
- `../../../data/xwalk_bg24_tr10.feather` — 2020 block group to 2010 tract allocation weights.
- `../../../data/acs_step1_2016_tract.feather` — 2012-2016 ACS estimates, one row per 2010 CA tract.
- `../../../data/acs_step1_2024_tract.feather` — 2020-2024 ACS estimates, one row per 2020 CA tract.
- Optional prior step-2 Feathers in `parity_reference_dir` — schema and Southern
  California parity references, read before saving. The configured directory is
  `../../../data/parity_reference`.

Outputs:
- `../../../data/acs_step2_2024_block_group_aggregated.feather` — 2020-2024 ACS block-group measures aggregated to 2010 tracts (`tr2010_id`), with inventory, interpolated rent, missing/top-coded-rent shares, structure, share, vacancy-rate, and CV measures.
- `../../../data/acs_step2_2016_tract.feather` — 2012-2016 ACS tract measures (`tr2010_id`), with inventory, revised Step 1 pass-through columns including `vac_rentedE/M`, top-code/missing/zero flags, structure, share, vacancy-rate, and CV measures.
- `../../../data/acs_step2_2024_tract.feather` — 2020-2024 ACS tract-source measures (`tr2020_id`), with direct inventory, retained bedroom-rent pairs and 2024 low-rent counts, top-code/missing/zero flags, structure, share, vacancy-rate, and CV measures.

All three outputs cover the configured Southern California and Bay Area counties.

Schema:
- `schemas/acs_step2_16.md`
- `schemas/acs_step2_24.md`
- [2024 tract-source schema](schemas/acs_step2_2024_tract.md)

Steps:
1. Set up environment (packages, `R/assemble_helpers.R` and shared `R/geography_qa.R`, data directory, named target counties, prior-output parity references)
2. Assemble 2020-2024 ACS block-group measures to 2010 tracts (select destination crosswalk rows, join all contributing sources, check allocation weights, capture legacy/corrected income expectations before censoring, aggregate existing measures and separate inventory components, validate inventory and Southern California parity, save)
3. Prepare 2012-2016 ACS tract measures (select the same target counties, capture income expectations before flagging/censoring, build share, vacancy-rate, CV, and direct inventory measures, validate inventory and parity, save)
4. Prepare 2020-2024 ACS tract-source measures (restrict native 2020 tracts to the target counties, preserve uncensored income diagnostics, apply tract flags/censoring and derived measures, construct direct inventory, validate income/inventory and optional strict parity, save)
5. Validate all three outputs separately (native key membership, county coverage, missing/top-coded rent, flag encoding, numeric distributions, strict saved schema/values, inventory completeness and reconciliation in §5.6)

Rental inventory combines renter-occupied units (`rhuE`, B25003_003), vacant
for rent (`vac_forrentE`, B25004_002), and rented, not occupied (`vac_rentedE`,
B25004_003). Both tract-source calculations add the three unique tract estimates directly.
For the 2024 block-group product, `calc_rental_inventory()` separately sums **each** source component
with **`wt_renthu`** on the retained `acs_2024_bg_allocations` rows. A contributing
source is a link with **`wt_renthu > 0`**. Any contributing `NA` or `NaN` in any
required estimate makes inventory `NA`; sums do not remove missing values or
substitute zero. Zero-weight links have no effect on completeness. A target
without positive-weight contributors has zero components and inventory, with
an explicit zero-contributor diagnostic. Missing rent, income, or MOEs do not
affect inventory completeness.

Only the native tract key and `rhu_inventoryE` are joined one-to-one from the diagnostic
table onto each production table, with identical key sets and preserved rows
and unrelated columns. The separate `inventory_rhuE`, `inventory_vac_forrentE`,
`inventory_vac_rentedE`, contributing/missing counts, and `inventory_incomplete`
stay in the notebook. Block-group-aggregated `vac_forrentE` continues to use **`wt_hu`**
for vacancy rates; inventory's diagnostic vacancy components use **`wt_renthu`**.
Occupied-renter counts and rent denominators, cash/low-rent/bin measures,
censoring, income, other weights, flags, MOEs, and CVs keep their calculations.
No inventory MOE/CV is added. The 2000-to-2010 tract crosswalk remains outside
Step 2's input contract. The two 2024 products are not compared or reconciled in
Step 2; Step 4 compares their measurements on geographically consistent links.

### Stage-2 output naming and references

| Historical output | Current output | Key |
|---|---|---|
| `acs_step2_16.feather` | `acs_step2_2016_tract.feather` | `tr2010_id` |
| `acs_step2_24.feather` | `acs_step2_2024_block_group_aggregated.feather` | `tr2010_id` |
| No prior file | `acs_step2_2024_tract.feather` | `tr2020_id` |

Preserve existing data files. The notebook writes only the three current output
names; it does not refresh the legacy filenames. Objects and diagnostics use
`2024_bg_aggregated` / `2024_tract` to distinguish sources while ACS columns keep
their existing names. Existing schema document paths are retained for link stability.

The explicit `parity_reference_files` map in §1.4 keeps historical reference
filenames `acs_step2_16.feather` and `acs_step2_24.feather` under the preserved
reference directory. The new tract product uses only its own optional
`acs_step2_2024_tract.feather` reference. Missing references mean **parity not
checked**, and are never replaced with another product. Its comparison uses
`key = "tr2020_id"` with strict schema/value checks and no income or boundary
exceptions. Pre-censoring source income and its existing CV formula are checked
independently of reference availability. Shared QA helpers retain
`key = "tr2010_id"` as their default.


## Step 3: Identify geographically consistent 2010–2020 tracts
Script: `03_tract_change.Rmd`

Inputs:
- `../../../data-raw-temp/census/tab20_tract20_tract10_st06.txt` — U.S. Census
  Bureau UTF-8, pipe-delimited geographic intersections between 2020 and 2010
  census tracts. The source is read-only.

Outputs:
- `../../../data/xwalk_tr20_tr10.feather` — one row per California 2020 tract
  (`tr2020_id`), with a uniquely linked `tr2010_id` where available and
  consistency, relationship, zero-land, partner-count, share, and land-area QA.
- Full relationship-level diagnostics, target-region/county summaries, and
  rejected one-to-one pair details remain in the notebook.

Schema:
- [2020-to-2010 tract crosswalk](schemas/xwalk_tr20_tr10.md).

Steps:
1. Set up environment (existing packages and shared/stage-specific helpers, `here::here()` paths, overwrite enabled for reruns, target-county diagnostic lookup)
2. Read and validate source intersections (character GEOIDs, exact integer-valued land areas stored as doubles, unique pairs, consistent repeated totals)
3. Characterize tract relationships (distinct partner counts from the complete file, denominator-safe shares, exact consistency and diagnostic flags)
4. Construct the tract-level crosswalk (retain every 2020 key; attach only unique 2010 links; classify mixed relationships with the analyst-selected rule)
5. Review geographic diagnostics (statewide and target-region/county classifications, one-to-one exclusion reasons, same/different consistent GEOIDs, changed-pair share distributions, source coverage and land reconciliation)
6. Save and validate the output (announced replacement on reruns, source fingerprint, complete membership, keys, types, values, flags, missingness, and ranges after reload)

**Exact geographic consistency** requires both partner counts to equal one,
both tract land areas to be positive, and intersection land area to equal each
tract's total land area exactly. There is no near-match threshold. Zero-land-area
pairs are excluded even when all areas equal zero. `same_geoid` is diagnostic
only; equal IDs cannot establish consistency and different IDs are permitted.
No water-area, population, housing, or allocation measures are used.

All source relationships contribute to partner counts, including zero-land
intersections and links to 2010 tracts outside California. Tract classes are
`consistent`, `one_to_one_changed`, `split`, `merge`, and `many_to_many`. For
multiple 2010 partners, **any** reverse multiplicity makes the tract
`many_to_many`, including mixed pair-level classes; `max_n_2020_partners` records
that distinction. Otherwise such a tract is `merge`. The 2010 key and all
pair-specific output fields are `NA` for multiple partners; no dominant partner
is selected. The tract zero-land flag covers any associated zero-land-area pair.

For later ACS comparison, select `geo_consistent == 1`, join the native-2020
2024 product using `tr2020_id`, then the 2016 product using `tr2010_id`. This
stage does not merge ACS measures or impose Step 2's county selection. Step 4
uses this crosswalk for canonical source selection, geographic coverage, and
consistent-pair diagnostics. Missing panel mappings remain unresolved. The differently structured historical
`tract_change.feather` is preserved.

Targeted validation uses `Rscript --vanilla tests/test_tract_change.R` for
synthetic relationships and temporary Feather round trips. The new notebook's
small local-source calculations can also run directly without executing other
stages. Its diagnostics report incomplete 2010 land coverage without changing
the source universe or consistency rule. Notebook reruns overwrite the existing
crosswalk with `overwrite_output <- TRUE`; replacement is announced and validated
before saving and after reloading. Setting it to `FALSE` restores the refusal
guard. The helper retains its protective default for other callers.

In addition to `tract_summary`, §5.2 reports `one_to_one_land_summary` statewide,
`target_region_summary` for Bay Area and Southern California, and
`target_county_summary` for all 14 configured counties. Each includes counts for
all five classes, percent consistent, one-to-one candidates, rejected
candidates, positive-land mismatches, and zero-land exclusions. County membership
uses `tr2020_id`; Step 3's diagnostic lookup is checked against Step 2's county
definitions by the focused tests. Partner counts and the saved crosswalk remain
statewide. Absent classes count as zero; empty counties retain zero counts and
an `NA` percentage.

A one-to-one candidate has exactly one partner in **both** directions.
Candidates reconcile into consistent pairs, zero-land exclusions, and
positive-land mismatches (intersection land differs from either tract total).
Zero-land cases receive the zero-land reason even if their areas also differ,
preventing double counting. `one_to_one_rejected_pairs` lists the rejected
GEOIDs, 2020 county, three land areas, and reason; non-target counties use FIPS
labels. These diagnostics add no columns to the Feather. Tests also cover
regional/county reconciliation, full-source reverse counts, the `matrixStats`
masking case, and the actual notebook save/reload chunks replacing an existing
temporary Feather.

## Step 4: Create ACS panel and compare revised measurement sources
Script: `04_merge.Rmd`

The notebook reads all three current Step 2 products and the Step 3 crosswalk.
Canonical 2024 estimates and their uncertainty/quality bundles use Census tract
values for `geo_consistent == 1` and block-group aggregates for every other row,
including missing or unrecognized numeric flags. The original geographic flags
and classes remain intact for QA; every row receives a selected-source label.
A missing selected estimate, source record, MOE, CV, or flag is never filled
from the alternative source. Selection precedes the single
set of canonical change calculations.

Inputs:
- `../../../data/acs_step2_2016_tract.feather` — 2012-2016 ACS measures on `tr2010_id`.
- `../../../data/acs_step2_2024_block_group_aggregated.feather` — 2020-2024 block-group measures aggregated to `tr2010_id`.
- `../../../data/acs_step2_2024_tract.feather` — Census-reported 2020-2024 tract measures on native `tr2020_id`.
- `../../../data/xwalk_tr20_tr10.feather` — statewide geographic-consistency flags and explicit links on `tr2020_id`.
- Existing `../../../data/acs_full.feather`, if saving is enabled and the file is present — column/type reference.

Outputs:
- Notebook-only `acs_diagnostics`, geographic coverage/unmatched keys, source level/change comparisons, and inventory comparisons; no diagnostic Feather is written.
- Optional `../../../data/acs_full.feather` — the existing 2010-tract panel, with 2016 dollars inflation-adjusted by 1.307, selected 2024 measures, `smfE` and `sfd_detE` levels for both years, level-change ratios, share/rate differences, existing CVs, separate inventory levels/change, and geographic/source/quality fields. Set `write_panel <- FALSE` to validate without writing.

Schema:
- `schemas/acs_full.md`

Steps:
1. Set up environment (existing packages and canonical/geographic helpers, `R/merge_diagnostics.R`, `here::here()` data path, optional-write control)
2. Import and prepare survey measures (all three native sources and their bundles, county/key checks, 2016 inflation adjustment, geographic crosswalk validation)
3. Merge surveys, select canonical 2024 measures, and calculate changes (original full-join key union, explicit consistent links, geography-selected bundles, existing change/CV formulas, separate inventory ratio)
4. Review geographic coverage and source-selection QA (native/panel denominators, unmatched keys, source counts/shares, missing/unexpected flags, canonical missingness, exact bundle equality, per-field correction summary)
5. Compare 2024 sources and implied changes (diagnostic only): median rent, block-group interpolated rent, and rental inventory on geographically consistent tracts, with subset coverage, source summaries, paired differences, absolute differences, positive-denominator ratios, and Pearson correlations
6. Compare occupied renter units and rental inventory (diagnostic only): all three native input products, then inventory vs. occupied-renter change for the full block-group panel and consistent Census pairs
7. Validate the panel and optionally save (key union, source-aware changes, missingness, flags, distributions; fixed schema-addition allowlist and strict shared-schema/saved-value checks)

**Geographic diagnostic eligibility:** the analyst selected only
`geo_consistent == 1` for all Section 5 source/change and baseline-coverage
diagnostics, using the explicit 2010 and 2020 keys even when the GEOIDs differ.
The single `overall` group denotes that consistent subset, including its rows
with missing measurements or baselines; no geographic-status groups are reported.
The `interp_rent` entries in `source_level_diagnostics` and
`source_change_diagnostics` compare native tract `rentE_24_tract` with preserved
block-group `interp_rent_24_bg_agg`, and the ratios each implies over positive,
inflation-adjusted `rentE_16`. Canonical `interp_rent` is not used as the
block-group source. Available statuses are attached
without dropping panel tracts; repeated split links must agree before reducing
them to one status record. Merge/many-to-many 2010 partners are absent from the
crosswalk, so unresolved panel statuses remain `NA`. Native 2020 coverage reports
all five classes; missing panel mappings are not reclassified as inconsistent.
Alignment coverage distinguishes no consistent link, no Census source record,
and a missing estimate within an existing source record.

**Canonical inventory and source-specific companions:** the panel includes
`rhu_inventoryE_16`, `rhu_inventoryE_24`, `rhu_inventoryPOST`, and
`m_flag_rhu_inventoryPOST`. Inventory adds vacant for rent and rented, not
occupied units to occupied renters; it uses the saved upstream estimate directly,
with no inventory MOE/CV. `acs_source_24`, `geo_consistent`, `relationship_class`,
and the consistent-link `tr2020_id` provide provenance. `acs_source_24` is
`"tract"` only for flag 1 and `"bg_agg"` otherwise, independently of source-record
or measure availability. Relevant 2024 quality flags follow the selected source;
unavailable aggregate censoring flags remain missing.

**Structure counts retained as levels:** the panel adds `smfE_16`, `smfE_24`,
`sfd_detE_16`, and `sfd_detE_24`. Small multifamily `smfE` is the upstream sum
`sfd_attE + duplexE + quadplexE`; `sfd_detE` counts detached single-family units.
The shared measurement list carries both counts from all three Step 2 inputs.
The 2016 levels retain their source values, and the 2024 levels follow the
geographic hierarchy. Zeros, fractional aggregate counts, and selected-source
missingness are preserved. Like `mf5E` and `nsfaE`, these are levels only, with
no new change measures, flags, MOEs, CVs, or inflation adjustment. Input checks
require numeric, finite, nonnegative observed counts; Section 7 reports each
level's missingness and numeric distribution.

The analyst chose to keep `pct_miss_rent`, `pct_tc_rent`, and `pct_miss_hval`
under their existing names and values as block-group diagnostics, including on
Census-selected/unresolved rows. They do not describe selected Census quality;
downstream quality rules remain unchanged. Canonical `interp_rent` follows the
geographic hierarchy: native tract median gross rent (`rentE_24_tract`, also
selected into `rentE_24`) for consistent tracts, and the existing block-group
interpolation for all other rows, including missing/unexpected status. Missing
selected values remain missing, with no availability fallback.
`merge_2024_field_map()` in `R/merge_helpers.R` maps the
preserved `interp_rent_24_bg_agg` source and native tract rent to the unsuffixed
canonical name; `04_merge.Rmd` §3.2 applies selection. No new tract interpolation
or interpolated-rent MOE/CV is constructed. `interp_rentPOST` divides that
selected value by positive, inflation-adjusted `rentE_16`; no change CV is added.
The original `post_id` continues to mean block-group
input membership: a retained 2016 tract may receive Census values and changes
through a consistent link despite lacking a block-group record.

Change diagnostics retain the established 2024/positive-2016 ratio definition,
using inflation-adjusted rent and each count concept's own baseline. The saved
`rhuPOST` remains occupied-renter change. Inventory-minus-occupied counts and
inventory/occupied ratios use the documented Step 2 estimates directly; shares
with inventory below occupied units use paired observations as denominator.
Undefined ratios/correlations and empty-group summaries are `NA`. No inventory
MOE/CV, geographic allocation, or changed-boundary measurement pairing is added.

Run `Rscript --vanilla tests/test_merge_diagnostics.R` for synthetic geography,
missingness/denominator cases, actual notebook chunks using temporary inputs,
whole-bundle selection, no-fallback cases in both directions, canonical changes,
hierarchical interpolated-rent levels/changes, all-field correction counts,
inventory, structure-count levels, schema migration, and guarded save/reload
checks. An analyst can run all diagnostics with writing disabled. Enable
`write_panel <- TRUE` in setup and
rerun from there only when the existing canonical panel should be written;
replacement is announced. Only documented hierarchy/inventory/flag additions
and the four `smfE` / `sfd_detE` levels are permitted against a prior panel;
shared column order/types and saved-value
checks remain strict. No prior reference is reported as not checked.

Analyst validation of assembly and the panel (after regenerating the revised stage-1 inputs):

- The earlier geographic extension alone used cached statewide inputs. With
  the revised stage-1 contract, generate the new inputs first, then validate
  stage 2 with the source-specific parity rules above. Stage 4 consumes those
  revised filenames and the Step 3 crosswalk. Assembly checks run with
  `Rscript tests/test_rental_inventory.R` and `Rscript tests/test_income_censoring.R`.
  They exercise synthetic inventory, both tract keys, configured county coverage,
  native-2020 tract flags/derived measures/income retention, strict/narrow parity,
  and actual save/reload chunks for all three filenames in a temporary directory. Full notebook execution,
  canonical output regeneration, and empirical inventory review remain analyst-run.
- Before running, preserve the prior step-2 outputs and set `parity_reference_dir`
  in stage 2 to that directory for repeatable comparisons. It is configured as
  `../../../data/parity_reference`; saving candidates in `data_dir` does not
  replace those snapshots. Missing references explicitly leave parity unverified.
- Inspect county counts separately for all three Step 2 products and the final panel: all 14 target
  counties must be populated, including the Bay Area, with no unintended
  destination counties. Stage 4 inherits the county set validated by stage 2.

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
- `socal_parity_16` and `socal_parity_2024_bg_aggregated` compare every shared output column, reporting
  changed values and added/removed keys. Each changed cell is classified as
  `verified_income_correction`, `boundary_review`, or `unexpected`, with counts
  in `difference_summary` and the complete values in `differences`. For
  geographically unaffected tracts, only changed `med_hhincE`/`med_hhincCV` cells
  matching both the expected legacy reference and corrected candidate may pass.
  Expectations use uncensored source incomes and the existing household weights
  (2024 block groups); both CV expectations use the reference income MOE and existing formula.
  Candidate MOEs, all other shared columns, and tract membership remain subject to
  ordinary parity. The existing tolerance is unchanged, and the helper remains
  strict on shared values when `expected_income = NULL`; schema differences
  require the explicit allowlist above. Review boundary differences with
  `socal_boundary_contributions_2024_bg_aggregated`, which identifies newly included sources and
  their weights/allocated counts. Use unchanged inputs for a valid comparison.
- Review raw and post-censoring rent missingness/top-codes by county. No empirical
  missingness threshold is imposed; unexplained county anomalies require review.
- Inspect `inventory_missing_sources_*` for source/target IDs and missing
  components, and `inventory_county_qa_*` for incomplete and zero-contributor
  counts, using suffixes `16`, `2024_bg_aggregated`, and `2024_tract` for the three products.
  Required source estimate/MOE columns must be numeric; weights
  and observed contributing estimates must be finite and nonnegative, with
  weights in [0, 1]. Output `is.na(rhu_inventoryE)` must agree exactly with the
  keyed completeness diagnostic. Complete inventory must equal its three component
  totals. Inspect each `inventory_reconciliation_*`: source-first and target-first
  totals must agree over **complete targets only**, without renormalizing weights.
  Incomplete targets remain separately reported. §5.6 repeats inventory checks
  after reloading and verifies all saved values, original allocation pairs/weights,
  and occupied-count reconciliation.
- Inspect `panel_membership`/`validated_panel_membership` and, after an enabled write,
  `saved_panel_membership` for one-period-only tracts;
  these use original input keys, independently of the output's constant `base_id`.
  Shared column names/order/types are checked against prior Step 2 files when
  available, with only the allowed migration; panel and save/reload schema
  checks remain strict. The panel filename and key union are unchanged; its schema
  adds documented geography/provenance, selected-source quality flags, and inventory
  levels/change. Source-comparison fields remain in notebook diagnostics.
- Review `source_selection_qa` for assigned-source counts/shares, missing and
  unexpected geographic flags, and canonical missingness. Every mapped bundle
  must pass `hierarchy_equality`; inspect median-rent, interpolated-rent, and
  inventory cases with missing selected values and observed alternatives.
  Confirm `interp_rent` equals native tract `rentE_24` for consistent tracts and
  the preserved block-group interpolation for every other row, including matching
  missingness. Missing/unexpected geographic flags remain unchanged, while those
  rows now select block-group measurements. `acs_source_24` must cover every row;
  the defensive `unassigned` count must be zero. Validation checks
  `interp_rentPOST` against the canonical selected value over positive `rentE_16`.
  Review inventory and rent changes alongside final key uniqueness, row counts,
  unchanged 2016 values, and the saved schema/reload checks.
- After rerunning Step 4 from setup with the existing Step 2/3 inputs, inspect
  `hierarchy_correction_qa`: one row per mapped field counts rows not positively
  flagged consistent, observed block-group values, canonical missingness
  before/after, and observed block-group values incorrectly missing canonically
  before/after. **Before** is the old rule reconstructed on this run's inputs;
  **after** is the corrected canonical result. Every
  `n_bg_observed_canonical_missing_after` must be zero, and
  `n_canonical_missing_after` must equal `n_not_consistent - n_bg_observed`.
  Counts are computed at runtime; previously reported empirical counts are
  diagnostic evidence, not fixed assertions. The correction requires only
  Step 4 regeneration; Codex validation uses synthetic inputs and temporary outputs.
- Review `geography_coverage`, `geography_unmatched`, `alignment_coverage`, and
  `native_tract_measure_coverage` before interpreting paired results. Inspect
  `source_level_diagnostics`, `source_change_diagnostics`, `baseline_coverage`,
  `inventory_level_diagnostics`, and `inventory_change_diagnostics` for coverage,
  undefined denominators, discrepancies, and inventory below occupied units.
  Section 5 tables should contain only consistent tract keys and one `overall`
  group; inspect the added `interp_rent` comparisons at both levels and changes.
  Section 6 retains its native-source and full-panel/consistent-subset denominators.
  Missingness shares use full labeled universes; no empirical threshold is imposed.

Income is retained independently of missing or top-coded rent, following the
analyst decision; see the [income correction and acceptance checks](notes/income_censoring.md).
The inspection's dollar-MOE discrepancy remains a separate research decision;
its executable behavior is unchanged. This cleaning-stage
expansion does not expand downstream analysis filters or supporting data. See
the stage's interface in [the shared pipeline document](../../PIPELINE.md).
