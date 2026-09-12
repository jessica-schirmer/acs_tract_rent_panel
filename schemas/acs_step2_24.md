# Schema: `acs_step2_2024_block_group_aggregated.feather`

**Produced by:** `02_assemble.Rmd` (Step 2) · **Source:** `acs_step1_2024_block_group.feather` + `xwalk_bg24_tr10.feather`

**Grain:** one row per 2010-vintage California tract **in the five Southern
California plus nine Bay Area counties** configured in [02_assemble.Rmd](../02_assemble.Rmd)
§1.3 (`target_counties`, shared by all three Step 2 products), built by weight-aggregating
2020 block groups to 2010 tracts.
**Key:** `tr2010_id` (unique, non-missing).

The production filename replaces `acs_step2_24.feather`; existing data and
historical parity references retain that legacy name. `03_merge.Rmd` is unchanged
and requires a follow-up input-filename update before it consumes this output.
The separate [2024 tract-source product](acs_step2_2024_tract.md) retains
`tr2020_id`; it is not compared with this product.

Selection is by destination tract county. All source block groups contributing
through the crosswalk are retained, including sources outside the target
counties. The original allocation fractions are preserved; excluding non-target
destinations does not renormalize them. These retained fractions also apply to
the new `rhu_inventoryE` measure.

## Aggregation method

Block-group estimates are aggregated to 2010 tracts using the NHGIS allocation
weights, by measure type (see the §2.5 decision block):

- **Counts** → weighted sums (`wt_renthu` for renter measures, `wt_hu` for
  housing-unit/structure measures, `wt_pop` for population, `wt_hh` for households).
- **Medians/means** → weighted means of the block-group estimates.
- **Margins of error** → `sqrt(sum((MOE * rel_wt)^2))` using relative weights.

`rentE` / `lqcrentE` are censored (`>= 3500` → `NA`) **before** aggregation.

## Aggregated count estimates (weighted sums)

`huE`, `rhuE`, `rhu_lrE`, `rhu_lr2E`, `rhu_baseE`, `hhE`, `popE`, `tot_vacE`,
`tot_vac_baseE`, `pop_blkE`, `pop_hspE`, `pop_aaE`, `pop_raceE`, `pop_ethnE`,
`sfd_detE`, `sfd_baseE`, `mf5E`, `rhucashE`, `grentcat1E`–`grentcat24E`.

`mf5E` (units in 5+ structures) is renamed from `mfE` after aggregation. The
following are weight-aggregated (`wt_hu`) **in the notebook** rather than by
`calc_agg_vars()`, then joined onto the tract table:
`vac_forrentE`, `vac_forsaleE`, `ohuE`, `smfE` (small multifamily:
`sfd_attE + duplexE + quadplexE`).

## Rental inventory

| column | type | description |
|---|---|---|
| `rhu_inventoryE` | numeric | Sum of three independently renter-weighted components: renter-occupied (`rhuE`, B25003_003), vacant for rent (`vac_forrentE`, B25004_002), and rented, not occupied (`vac_rentedE`, B25004_003). |

`calc_rental_inventory()` works on retained source allocation rows, before
collapsing them to tracts. **Every component uses `wt_renthu`**:

```r
sum(source_component[wt_renthu > 0] * wt_renthu[wt_renthu > 0])
```

A contributing source is a retained allocation with `wt_renthu > 0`. Weights
must be finite fractions in [0, 1]; retained fractions are not renormalized.
Source estimate/MOE columns must be numeric. Observed contributing estimates
must be finite and nonnegative. **Any contributing `NA` or `NaN` in any of the
three estimates makes `rhu_inventoryE = NA_real_`.** Component sums retain
`sum()`'s default `na.rm = FALSE`; no partial inventory or missing-to-zero
substitution is allowed. Missing rent, income, or MOEs have no effect on
completeness. Zero-weight links contribute zero and do not affect completeness,
including when their estimates are missing. Targets with no positive-weight
contributors have zero component totals and inventory, `n_contributing = 0`,
and `inventory_incomplete = FALSE`.

The notebook retains `inventory_rhuE`, `inventory_vac_forrentE`,
`inventory_vac_rentedE`, contributing-source/missing-component counts, and
`inventory_incomplete` in diagnostics. Only `tr2010_id` and `rhu_inventoryE`
are joined one-to-one onto the production table; **inventory is the only added
2024 output column**. Neither the diagnostic components/flags nor an inventory
MOE/CV enters this output.

The existing `vac_forrentE` above uses **`wt_hu`** for `pctrvacE`; the separate
`inventory_vac_forrentE` diagnostic uses **`wt_renthu`** for inventory. Existing
vacancy rates, occupied `rhuE`, cash/low-rent/bin counts, rent/income calculations,
weights, MOEs, CVs, and flags retain their calculations. Inventory is never
derived from the existing vacancy-rate input or used as a rent denominator.

Before saving and after reloading (§5.6), keyed output missingness must equal
`inventory_incomplete`. Every complete target must have finite, nonnegative
inventory equal to its three component totals. Source-first and target-first
totals reconcile over **complete targets only**, with incomplete targets
reported separately by county/vintage and no redistribution of retained weights.
These checks apply independently when a reference lacks inventory or is absent.

`compare_socal_parity(schema_migration = "2024")` permits only the addition
`rhu_inventoryE`, reported in `schema_changes`, with no removals. Shared columns
retain strict order, type, and value checks, including existing income and
geographic rules. The default `schema_migration = NULL` and save/reload schema
checks remain strict. Missing references remain **parity not checked**.
Step 3 keeps its current selection and panel contract; `rhuPOST` still measures
occupied-renter change.

## Aggregated medians/means (weighted means)

`rentE`, `lqcrentE`, `med_hhincE`, `med_hvalE`.

**Income retention:** `censor_tc_vars()` leaves block-group `med_hhincE` unchanged
regardless of missing or top-coded rent, preserving source values and missingness
without adding an income threshold. Income is then aggregated with the unchanged
`weightedMean(med_hhincE, w = hhE * wt_hh, na.rm = TRUE)`. Available income
contributions whose rent is missing or censored are retained; missing source
income is excluded, and an aggregate with all source incomes missing remains
missing. Removing the previous rent-dependent income exclusion can change both
tract income values and missingness. `med_hhincCV` uses the resulting income
estimate in its existing formula. See the
[income-censoring decision and validation](../notes/income_censoring.md).

## Aggregated margins of error (root-sum-of-squares)

`rentM`, `lqcrentM`, `med_hhincM`, `med_hvalM`, `rhuM`, `rhu_baseM`, `tot_vacM`,
`tot_vac_baseM`, `pop_blkM`, `pop_hspM`, `pop_aaM`, `pop_raceM`, `sfd_detM`,
`sfd_baseM`, `huM`, `popM`.

## Derived measures

| column | type | description |
|---|---|---|
| `interp_rent` | numeric | Median rent interpolated within the median gross-rent category; `NA` for open-ended bottom/top categories or no cash-rent units (see §2.6). |
| `nsfaE` | numeric | Non-single-family **attached** units: `smfE + mf5E` (`sfd_att + duplex + quadplex` plus units in 5+ structures); excludes single-family detached, mobile homes, and other units. |
| `pctrvacE` | numeric | Rental vacancy rate: `vac_forrentE / (rhuE + vac_forrentE)`; `NA` if denominator ≤ 0. |
| `pctsvacE` | numeric | For-sale vacancy rate: `vac_forsaleE / (ohuE + vac_forsaleE)`; `NA` if denominator ≤ 0. |
| `rhu_miss_rent` | numeric | Weighted renter units in block groups missing rent (aggregated). |
| `hu_miss_hval` | numeric | Weighted housing units in block groups missing median value. |
| `pct_miss_rent` | numeric | `rhu_miss_rent / rhuE` (share of renter units missing rent). Because rent is censored (`>= 3500` → `NA`) **before** aggregation, this counts both genuinely missing **and** top-coded block groups; it decomposes as `pct_miss_rent ≈ pct_m_rent + pct_tc_rent`. |
| `pct_tc_rent` | numeric | Share of weighted renter units in the tract whose rent is top-coded (`rentE >= 3500`), computed on the **uncensored** block-group rent in §2.3; the top-coded portion of `pct_miss_rent`. `NA` where tract `rhuE = 0`. |
| `pct_miss_hval` | numeric | `hu_miss_hval / huE` (share of units missing median value). |
| `pctrhuE`, `pctvacE`, `pctblkE`, `pcthspE`, `pctaaE`, `pctsfdE` | numeric | Share measures (see `acs_step2_16.md` for definitions). |
| `pctrhuM`, `pctblkM`, `pcthspM` | numeric | Derived share MOEs. |
| `rentCV`, `med_hhincCV`, `med_hvalCV`, `pctrhuCV`, `pctblkCV`, `pcthspCV`, `rhuCV`, `huCV`, `popCV` | numeric | Coefficients of variation. |

## Flag and join-indicator columns

| column | type | description |
|---|---|---|
| `tc_flag_rent_24` | numeric (double, 0/1) | 1 if the tract had any top-coded (`>= 3500`) renter rent before censoring. Existing storage and column name are preserved. |
| `rhu_id` | logical | Constant `TRUE`; tag added during aggregation. |
| `merge`, `left_id`, `right_id` | character / logical | Join indicators retained from the final `merge_df()` steps (interpolated rent and top-code-flag merges). All rows should be `"both"`. |
