# Schema: `acs_step2_16.feather`

**Produced by:** `02_assemble.Rmd` (Step 2) · **Source:** `acs_step1_2016_tract.feather`

**Grain:** one row per 2010-vintage California tract **in the five Southern
California plus nine Bay Area counties** configured in [02_assemble.Rmd](../02_assemble.Rmd)
§1.3 (`target_counties`, shared by both vintages).
**Key:** `tr2010_id` (unique, non-missing).

This file is the 2012–2016 tract table restricted to those 14 counties, with
top-code/missing/zero flags, structure-type aggregates, rental inventory, and
share/CV measures added.

## Base columns

All columns from `acs_step1_2016_tract.feather` carry through — see
[acs_step1_2016_tract.md](acs_step1_2016_tract.md) for the full `<name>E` / `<name>M` measure list, plus
`tr2010_id`, `NAME`, `rhu_lrE`, `rhu_lr2E`, and `rent_id`. Note that `rentE` and
`lqcrentE` are **censored** here: values `>= 3500` are set to `NA` (top-code
removal). See the §2.4 / §3.2 decision blocks in the notebook.

The revised input removes `rentmv1yr`, `rentmv5yr`, `rentyrblt`,
`rentyrblt_14_16`, `rentyrblt_10_13`, `rentyrblt_00_09`, and `rentyrblt_90_99`
(each estimate/MOE pair), and adds `vac_rentedE/M` (B25004_003, rented, not
occupied). These pass-through changes also apply to this output; the three
bedroom-rent pairs remain. `compare_socal_parity(schema_migration = "2016")`
permits only these seven pair removals and the additions `vac_rentedE`,
`vac_rentedM`, and `rhu_inventoryE` against older snapshots. Actual differences
are reported in `schema_changes`; shared columns retain strict order, type,
and value checks, with the existing income-correction rules. The default
`schema_migration = NULL` and save/reload schema checks remain strict.
See the [stage-1 migration](../README.md#stage-1-input-migration).

## Added rental inventory

| column | type | description |
|---|---|---|
| `rhu_inventoryE` | numeric | Renter-occupied units plus vacant for rent plus rented, not occupied: `rhuE + vac_forrentE + vac_rentedE`. |

The source estimates are B25003_003, B25004_002, and B25004_003, respectively.
Each unique 2010 tract is its own source with unit weight. **Any `NA` or `NaN`
in a required estimate makes inventory `NA`**; no partial subtotal or zero
substitution is allowed. Missing rent, income, or source MOEs do not affect
inventory completeness. Required estimate/MOE columns must be numeric, and
observed contributing estimates must be finite and nonnegative.

The [2024 counterpart](acs_step2_24.md#rental-inventory) allocates each of the
same components with `wt_renthu`. A retained link contributes only when
`wt_renthu > 0`; zero-weight links contribute zero and do not affect completeness.
A target without positive-weight contributors has zero components and inventory,
`n_contributing = 0`, and `inventory_incomplete = FALSE`. Every 2016 target has
one contributor because its unit weight is positive.

Component totals (`inventory_rhuE`, `inventory_vac_forrentE`,
`inventory_vac_rentedE`), missing-component counts, and `inventory_incomplete`
remain in notebook diagnostics. Only the key and `rhu_inventoryE` are joined
one-to-one onto the output, preserving its other columns and rows. Pre-save and
reload checks in §4.6 validate keyed missingness and reconcile complete-target
totals separately from incomplete targets, including when inventory is absent
from a reference. No inventory MOE/CV is added. `rhuE` and all existing rent
denominators remain occupied-renter measures. Step 3 keeps its existing selection;
`rhuPOST` remains occupied-renter change.

## Added structure-type aggregates

| column | type | description |
|---|---|---|
| `mf5E` | numeric | Multifamily units in 5+ structures: `mf_5_9E + mf_10_19E + mf_20_49E + mf_50E` (renamed from `mfE`). |
| `smfE` | numeric | Small multifamily: `sfd_attE + duplexE + quadplexE`. |
| `nsfaE` | numeric | Non-single-family **attached** units: `smfE + mf5E`; excludes single-family detached, mobile homes, and other units. |

## Added share measures

| column | type | description |
|---|---|---|
| `pctrhuE` | numeric | Renter-occupied share of housing units (`rhuE / huE`). |
| `pctvacE` | numeric | Vacant share (`tot_vacE / tot_vac_baseE`). |
| `pctblkE` | numeric | Black share of population (`pop_blkE / pop_raceE`). |
| `pcthspE` | numeric | Hispanic share (`pop_hspE / pop_ethnE`). |
| `pctaaE` | numeric | Asian share (`pop_aaE / pop_raceE`). |
| `pctsfdE` | numeric | Single-family-detached share (`sfd_detE / sfd_baseE`). |
| `pctrvacE` | numeric | Rental vacancy rate (`vac_forrentE / (rhuE + vac_forrentE)`); `NA` if denominator ≤ 0. |
| `pctsvacE` | numeric | For-sale vacancy rate (`vac_forsaleE / (ohuE + vac_forsaleE)`); `NA` if denominator ≤ 0. |

## Added margin-of-error / coefficient-of-variation measures

| column | type | description |
|---|---|---|
| `pctrhuM`, `pctblkM`, `pcthspM` | numeric | Derived MOEs for the corresponding share measures (ratio MOE formula). |
| `rentCV`, `med_hhincCV`, `med_hvalCV` | numeric | CVs for median rent / income / value (`(M/1.645)/E`). |
| `pctrhuCV`, `pctblkCV`, `pcthspCV` | numeric | CVs for the corresponding shares. |
| `rhuCV`, `huCV`, `popCV` | numeric | CVs for renter units / housing units / population. |

## Data-quality flag columns (0/1 integers)

| column pattern | description |
|---|---|
| `tc_flag_rent`, `tc_flag_lqcrent`, `tc_flag_med_hval` | 1 if top-coded (rent/lqcrent `>= 3500`; median value `>= 2,000,000`). |
| `m_flag_rent`, `m_flag_lqcrent`, `m_flag_rhu`, `m_flag_rhucash`, `m_flag_med_hval` | 1 if the estimate is missing (`NA`). |
| `zero_flag_rhu`, `zero_flag_rhucash`, `zero_flag_med_hval` | 1 if the estimate is zero. |

**Income retention:** `censor_tc_vars()` leaves `med_hhincE` unchanged, preserving
its source values and missingness regardless of missing or top-coded `rentE` or
`lqcrentE`. No income-value threshold is applied. `med_hhincCV` uses the retained
income estimate in its existing formula. This corrects the previous unintended
loss of available income wherever `rentE` was missing or top-coded. See the
[income-censoring decision and validation](../notes/income_censoring.md) for the
analyst rule, regression checks, and output acceptance checks.
