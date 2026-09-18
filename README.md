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
union, `target_counties`, are centralized in `step2_target_counties()` in `R/geography_qa.R`. All three
products use those counties while retaining their documented tract vintages.
The 2024 block-group allocation retains all source
block groups contributing to those 2010 tracts, including sources outside the
target counties, with the original NHGIS fractions (no renormalization).

01_acs.Rmd - import selected variables from the 2012-2016 ACS (tracts) and 2020-2024 ACS (tracts and block groups); import cross-walk for 2024 block groups to 2010 tracts
02a_aggregate_2024_block_groups.Rmd - aggregate 2020-2024 block groups to 2010 tracts, with inventory and diagnostics
02b_prepare_tract_sources.Rmd - prepare native 2016 and 2024 tract measures, with inventory, flags, and diagnostics
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
1. Set up environment (packages, explicit block-group exclusions, shared helpers and `R/acs_input_qa.R`, relative data paths)
2. Define the target ACS variables to extract
3. Import and prepare the 2012-2016 ACS tract data (download, check MOE, rename ID, save)
4. Import and prepare the 2020-2024 ACS block-group data (using the available subset; validate keys, request-derived fields, and numeric types before saving)
5. Import and prepare the 2020-2024 ACS tract data (using the full tract list)
6. Import and prepare the geographic crosswalks (bg2020->tr2010, tr2000->tr2010; validate BG allocation pairs/weights and report statewide ACS/crosswalk coverage)
7. Validate all five saved outputs (required/omitted columns, row preservation, key uniqueness, missingness, flag encoding, numeric distributions; exact BG/crosswalk readback)

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
The derived low-rent counts are retired in all three products; every source
rent bin remains. Stage 2 consumes both 2024 inputs separately: block groups are
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

**Step 1 BG input hardening:** §4 asserts a nonmissing, unique, character
12-digit BG key immediately after wide extraction and again before saving.
Required estimate/MOE columns are derived from `block_group_vars`, using the
first alias per Census code; all must be numeric. Numeric `NA`/`NaN` estimates
remain valid source missingness. §6.1 explicitly reads crosswalk GEOIDs as
character, checks their 12-/11-digit formats and pair uniqueness, and requires
all four allocation weights to be numeric, finite, and within `[0,1]`. Each
source's weights across all destinations must sum to one within the existing
`1e-6` tolerance. Failures stop before the crosswalk is saved; weights and links
are never adjusted.

After the next full Step 1 run, inspect `xbg_weight_sums` and the separate
`bg_coverage_24$acs_only` / `$crosswalk_only` tables in §6.1. The printed coverage
summary counts distinct BGs, groups discrepancies by source state/county, and
shows at most ten IDs in each direction; `$crosswalk_only_links` retains full
unmatched links and weights for review. Statewide coverage differences remain
diagnostic, including cross-state sources; they neither filter inputs nor
determine target-tract completeness. Failed structural or weight-sum assertions
remain fatal independently of coverage. Step 2 applies the separate contributor and count checks described below.

Confirm both exact-readback checks pass in §7.6: row counts, keys and row order,
column names/order, storage types/classes, and every value must equal the
validated in-memory inputs. Crosswalk weights compare exactly, with no numeric
tolerance. Continue reviewing ACS missingness and numeric distributions in §7.
Run `Rscript --vanilla tests/test_acs_input_qa.R` for inexpensive notebook parsing,
synthetic input/coverage failures, and temporary CSV/Feather round trips. These
tests do not call the API or regenerate canonical data.

**Stage-2 parity compatibility is implemented through a narrow allowlist.**
`compare_socal_parity()` stays strict by default (`schema_migration = NULL`).
The notebook opts into fixed migrations for all three products:

| Vintage / `schema_migration` | Permitted additions relative to older references | Permitted removals |
|---|---|---|
| 2016 / `"2016"` | `vac_rentedE`, `vac_rentedM`, `rhu_inventoryE` | Estimate/MOE pairs for `rentmv1yr`, `rentmv5yr`, `rentyrblt`, `rentyrblt_14_16`, `rentyrblt_10_13`, `rentyrblt_00_09`, `rentyrblt_90_99`; `rhu_lrE`, `rhu_lr2E` |
| 2024 block-group aggregated / `"2024"` | `rhu_inventoryE` | The 12 cleanup fields listed below |
| 2024 native tract / `"2024_tract"` | None | `rhu_lrE`, `rhu_lr2E` |

The block-group removal list is `rhu_lrE`, `rhu_lr2E`, `rentE`, `rentM`, `rentCV`,
`lqcrentE`, `lqcrentM`, `med_hvalE`, `med_hvalM`, `med_hvalCV`, `hu_miss_hval`, and
`pct_miss_hval`. Weighted median household income, its MOE/CV, and its panel
change measures are retained. Native tract dollar estimates and uncertainty
remain in their Step 2 products; the existing 2016 native panel fields remain.
Step 2 drops obsolete low-rent columns from older inputs and rejects retired
output fields even when no reference exists. See the
[cleanup record](docs/measure_cleanup.md) for the exact panel removals and
separate analysis-consumer migration needs.

Actual additions/removals appear in `schema_changes`; unlisted differences fail.
Shared columns retain strict order, storage type/class, and value checks,
including the existing income-correction and geographic classifications.
Inventory is validated independently before saving and after reloading even
when absent from a reference. Save/reload schema checks remain strict for every
column. Preserve all reference snapshots; a missing reference remains **parity
not checked**. Step 4 selects canonical 2024 bundles by geography and adds separate inventory
levels/change; `rhuPOST` remains occupied-renter change.


## Step 2: Assemble 2016 tract and separate 2024 block-group/tract measures
Notebooks: [02a_aggregate_2024_block_groups.Rmd](02a_aggregate_2024_block_groups.Rmd) and
[02b_prepare_tract_sources.Rmd](02b_prepare_tract_sources.Rmd). Either can run first; each reads, validates,
and writes only its own products. Step 4 consumes all three products with unchanged schemas.

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
- `../../../data/acs_step2_2024_tract.feather` — 2020-2024 ACS tract-source measures (`tr2020_id`), with direct inventory, retained native dollar and bedroom-rent pairs, top-code/missing/zero flags, structure, share, vacancy-rate, and CV measures.

All three outputs cover the configured Southern California and Bay Area counties.

Schema:
- `schemas/acs_step2_2016_tract.md`
- `schemas/acs_step2_2024_block_group_aggregated.md`
- [2024 tract-source schema](schemas/acs_step2_2024_tract.md)

Steps in 02a:
1. Set up environment, shared county configuration, and the block-group parity reference.
2. Assemble 2020–2024 ACS block-group measures to 2010 tracts: select and check allocations, capture income expectations, censor, aggregate, interpolate, construct inventory, validate parity, and save.
3. Validate the reloaded block-group output, including reference-based contributor integrity, count/dependent completeness, rent-share decomposition, county coverage, and inventory reconciliation (§3.6).

**2024 BG contributor/count hardening:** `02a` constructs a locked reference
before joining ACS, containing all original target links, four weights, target
IDs, and positive-weight contributors by family. Cross-county sources and split
fractions remain intact; full-source weights still reconcile without
renormalization. Missing/duplicate/substituted/unexpected links, changed weights,
missing positive-weight ACS rows, lost targets, and inconsistent diagnostics fail.
Unmatched links with four exact zero weights remain as noncontributing rows,
including targets represented entirely by those links.

Every ordinary/supplemental additive count uses `strict_weighted_sum()`:
positive-weight `NA`/`NaN` makes only the affected aggregate missing; observed
zeros are valid; zero-weight missing values have no effect; reference-confirmed
empty sets yield numeric zero. Population/race/ethnicity uses `wt_pop`, households
`wt_hh`, housing/vacancy/owner/structure counts `wt_hu`, and renter/base/cash/all
24 rent-bin counts plus `rhu_miss_rent` use `wt_renthu`. The latter retains
`if_else(is.na(rentE), rhuE, 0)` after censoring. Source structure additions and
`mfE` → `mf5E` stay unchanged. Inventory retains its three renter-weighted
components, independently checked against the reference.

`bg_count_qa_2024` retains keyed family/measure diagnostics and full missing-source
tables; county/family summaries and bounded incomplete examples are printed.
Complete groups reconcile numerically and incomplete groups must be missing,
including after Feather reload. Optional `expected_count_corrections` supplies
keyed, source-derived legacy/corrected values to parity; only individually
verified count corrections and their natural dependent changes are accepted.
Strict defaults, schema checks, income handling, and geographic review remain.
No new columns/types or filenames are introduced, and reference snapshots stay intact.

**Dependent-measure hardening (Pass 3):** `interp_rent` now requires complete
`rhucashE` and all 24 rent bins, including bins after the median. Its category
endpoints, interpolation formula, censoring, and zero-cash-renter rules remain.
Pre-censoring rent shares and `tc_flag_rent_24` require complete renter counts;
complete zero denominators retain missing shares and flag zero. Relative weights
use strict count denominators. Income estimates require complete household
counts; income MOEs require complete renter counts. Count MOEs require the base
counts used by their relative weights. Missing income/MOE inputs retain their
existing treatment when required counts are complete.

`bg_dependent_qa_2024` traces required counts for totals, shares/rates, flags,
income, MOEs, CVs, and interpolation, reusing contributor/completeness metadata.
Populated results with incomplete required counts fail after joins, before save,
and after readback. Full missing-source details remain outside the Feather.
`rent_share_incomplete_2024` records cases where all rent shares must be missing.
The existing independent count reconciliation is retained and anchored to an
original-source snapshot plus immutable crosswalk weights; it never reuses the
production sum helper. Parity verifies both historical and corrected values for
the newly gated cells, including income, MOEs, rent shares, and flags. Native
tract calculations, Step 4, package dependencies, and canonical files are unchanged.

Run `Rscript --vanilla tests/test_bg_aggregation_qa.R` for contributor/count tests,
BG inventory helper/chunk checks, temporary Feather readback, parsing, and focused
shared-parity compatibility. `tests/test_rental_inventory_bg.R` is the narrower
BG-only inventory entry point; neither executes the native-tract notebook.
Run `Rscript --vanilla tests/test_income_censoring.R` for income regressions.
Full notebook execution and empirical acceptance remain analyst-run. See the
[hardening status and acceptance checks](docs/step1_step2_bg_qa_hardening_plan.md).

Steps in 02b:
1. Set up environment, shared county configuration, and the two tract parity references.
2. Prepare 2012–2016 ACS tract measures, retaining income expectations, flags, derived measures, inventory, parity, and saving.
3. Prepare 2020–2024 ACS tract-source measures on native keys, retaining source income, flags, derived measures, inventory, parity, and saving.
4. Validate both reloaded native tract outputs, including key membership, county coverage, flag encoding, numeric distributions, exact saved schema/values, and inventory reconciliation (§4.6).

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
Occupied-renter counts, rent denominators, and cash/bin counts now propagate
required source missingness as described above. Censoring, retained allocation
weights, and derived formulas remain; dependent values require complete counts.
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
their retained names. Schema links use the current descriptive filenames.

The explicit `parity_reference_files` map in §1.4 keeps historical reference
filenames `acs_step2_16.feather` and `acs_step2_24.feather` under the preserved
reference directory. The new tract product uses only its own optional
`acs_step2_2024_tract.feather` reference. Missing references mean **parity not
checked**, and are never replaced with another product. Its comparison uses
`key = "tr2020_id"` and `schema_migration = "2024_tract"`, permitting only the
two low-rent removals; shared schema/values remain strict, without income or boundary exceptions. Pre-censoring source income and its existing CV formula are checked
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
5. Compare 2024 sources and implied changes (diagnostic only): native versus block-group interpolated rent, and rental inventory on geographically consistent tracts, with subset coverage, source summaries, paired differences, absolute differences, positive-denominator ratios, and Pearson correlations
6. Compare occupied renter units and rental inventory (diagnostic only): all three native input products, then inventory vs. occupied-renter change for the full block-group panel and consistent Census pairs
7. Validate the panel and optionally save (key union, source-aware changes, missingness, flags, distributions; fixed schema-addition/removal allowlists and strict shared-schema/saved-value checks)

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
or measure availability. Retained renter-count missing/zero flags and the rent
top-code flag follow the selected source. Flags solely tied to retired fields are removed.

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

The analyst chose to keep `pct_miss_rent` and `pct_tc_rent`
under their existing names and values as block-group diagnostics, including on
Census-selected/unresolved rows. They do not describe selected Census quality;
downstream quality rules remain unchanged. Canonical `interp_rent` follows the
geographic hierarchy: native tract median gross rent (`rentE_24_tract`) for consistent tracts, and the existing block-group
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
and the four `smfE` / `sfd_detE` levels, plus the fixed cleanup removals, are permitted against a prior panel;
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
  and retained as exempt noncontributing rows only when all four weights are
  finite and exactly zero. Missing sources with any positive or missing/invalid
  weight still fail validation. All original targets survive, including those
  represented entirely by exempt links; all-zero links grant no boundary exception. Full source weights sum to one within `1e-6`; retained weights
  can sum below one and must remain identical to their original fractions.
  Assertion failures stop notebook execution.
  [Note: conditions met when both Step 2 notebooks run without error.]
- `socal_parity_16` and `socal_parity_2024_bg_aggregated` compare every shared output column, reporting
  changed values and added/removed keys. Each changed cell is classified as
  `verified_income_correction`, `verified_count_correction` (BG only),
  `boundary_review`, or `unexpected`, with counts in `difference_summary` and
  complete values in `differences`. For geographically unaffected tracts, each
  approved income/count correction must match both source-derived legacy
  reference and corrected candidate expectations.
  Expectations use uncensored source incomes and the existing household weights
  (2024 block groups); corrected income/CV expectations also require complete
  household/renter counts, retaining the reference MOE when its counts are complete.
  Count expectations use validated BG sources and unchanged downstream formulas;
  dependent corrections include shares/rates, interpolated rent, count-weighted
  income/MOEs, CVs, and the rent top-code flag. Every cell must match both
  expectations; unrelated changes and tract membership retain ordinary parity.
  The existing tolerance is unchanged,
  and the helper stays strict when both optional expectation arguments are `NULL`; schema differences
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
  Incomplete targets remain separately reported. 02a §3.6 and 02b §4.6 repeat inventory checks
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
  must pass `hierarchy_equality`; inspect interpolated-rent and
  inventory cases with missing selected values and observed alternatives.
  Confirm `interp_rent` equals native tract `rentE_24_tract` for consistent tracts and
  the preserved block-group interpolation for every other row, including matching
  missingness. Missing/unexpected geographic flags remain unchanged, while those
  rows now select block-group measurements. `acs_source_24` must cover every row;
  the defensive `unassigned` count must be zero. Validation checks
  `interp_rentPOST` against the canonical selected value over positive `rentE_16`.
  Review inventory and rent changes alongside final key uniqueness, row counts,
  unchanged 2016 values, and the saved schema/reload checks.
- After rerunning Step 4 from setup with cleaned Step 2 inputs and the existing Step 3 crosswalk, inspect
  `hierarchy_correction_qa`: one row per mapped field counts rows not positively
  flagged consistent, observed block-group values, canonical missingness
  before/after, and observed block-group values incorrectly missing canonically
  before/after. **Before** is the old rule reconstructed on this run's inputs;
  **after** is the corrected canonical result. Every
  `n_bg_observed_canonical_missing_after` must be zero, and
  `n_canonical_missing_after` must equal `n_not_consistent - n_bg_observed`.
  Counts are computed at runtime; previously reported empirical counts are
  diagnostic evidence, not fixed assertions. The hierarchy correction itself needs only
  Step 4; this cleanup also requires regenerated Step 1/2 products. Codex validation uses synthetic inputs and temporary outputs.
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
The retained income-MOE weighting discrepancy remains a separate research decision;
its executable behavior is unchanged. Other retired dollar-MOE findings remain
historical evidence, not current output contracts. This cleaning-stage
expansion does not expand downstream analysis filters or supporting data. See
the stage's interface in [the shared pipeline document](../../PIPELINE.md).

### Step 2 split acceptance

The notebook split preserves the post-cleanup calculations, operation order within
each product, filenames, keys, column order/types, values, and missingness.
This describes the historical split. The subsequent contributor/count hardening
above intentionally changes incomplete BG counts and their natural dependent values.
`read_step2_parity_references()` in `R/assemble_helpers.R` reads each notebook's
explicit map, retaining historical filenames, named missing references, and the
existing messages. The split itself left measurement helpers unchanged; the
subsequent hardening adds strict sums and required-count gates for dependent measures.

Before full execution, preserve post-cleanup baseline outputs. Run both notebooks
on identical inputs, in either order, and compare all three products across their
**full key universes**, including row/column order, storage types, values, and
missingness. Southern California reference checks alone do not establish this
refactor's full parity. Review allocation conservation, county coverage, rent-share
decomposition, income retention, inventory reconciliation, and exact save/reload
checks. Full execution and canonical regeneration remain analyst-run.

The four affected synthetic suites are `tests/test_income_censoring.R`,
`tests/test_rental_inventory.R`, `tests/test_tract_change.R`, and
`tests/test_merge_diagnostics.R`. The inventory suite also parses both notebooks,
checks labels/numbering/overviews, and exercises product-specific temporary
Feather saves, reloads, missing/partial references, and failure assertions.
