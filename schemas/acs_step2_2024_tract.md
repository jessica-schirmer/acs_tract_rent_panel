# Schema: `acs_step2_2024_tract.feather`

**Produced by:** `02_assemble.Rmd` §4 (Step 2) · **Source:** `acs_step1_2024_tract.feather`

**Grain:** one row per native 2020-vintage California tract in the five Southern
California and nine Bay Area counties configured by `target_counties` in §1.3.
**Key:** `tr2020_id` (11-digit character, unique and non-missing).

This direct tract-source product uses no crosswalk or allocation. It is separate
from the [2024 block-group-aggregated product](acs_step2_24.md), which is keyed
by `tr2010_id`. Step 2 processes them separately. Step 4 selects this product
for canonical measurements through explicit `geo_consistent == 1` links,
including different-GEOID pairs, and retains native-source and paired diagnostics.
Estimates, uncertainty, and available quality flags follow the same source;
missing selected values are never filled from block-group aggregates. Canonical
inventory/change and provenance fields are described in the [panel schema](acs_full.md).

## Base columns and censoring

All columns from the [2024 tract input](acs_step1_2024_tract.md) carry through,
including estimate/MOE pairs, `tr2020_id`, `NAME`, logical `rent_id = TRUE`,
`rhu_lrE`, and `rhu_lr2E`. Source columns retain their storage types and order.
The three bedroom-rent pairs (`rent1bdrE/M`, `rent2bdrE/M`, `rent3bdrE/M`) and
the 2024 low-rent counts (categories 1–18 / 1–20) remain unchanged. B25111/B25113
measures removed upstream are not reintroduced.

Only `rentE` and `lqcrentE` are censored: values `>= 3500` become `NA` after
capturing top-code flags. Median house value is flagged at `>= 2000000` without
censoring its estimate. Bedroom rents are not censored by this tract workflow.

**Income retention:** `med_hhincE` and `med_hhincM` retain their source values and
missingness independently of missing/top-coded rent. There is no income
aggregation or separate income threshold. `med_hhincCV` uses the unchanged
formula `(med_hhincM / 1.645) / med_hhincE`; source income and its resulting CV
are checked independently of parity-reference availability.

## Added structure, share, and uncertainty measures

All added estimates, MOEs, and CVs below are numeric. Definitions match the
[2016 tract path](acs_step2_16.md) and the existing shared helpers.

| Column | Definition |
|---|---|
| `mf5E` | `mf_5_9E + mf_10_19E + mf_20_49E + mf_50E` |
| `smfE` | `sfd_attE + duplexE + quadplexE` |
| `nsfaE` | `smfE + mf5E`; excludes detached single-family, mobile homes, and other units |
| `pctrhuE` | `rhuE / huE` |
| `pctvacE` | `tot_vacE / tot_vac_baseE` |
| `pctblkE`, `pctaaE` | `pop_blkE / pop_raceE`, `pop_aaE / pop_raceE` |
| `pcthspE` | `pop_hspE / pop_ethnE` |
| `pctsfdE` | `sfd_detE / sfd_baseE` |
| `pctrvacE` | `vac_forrentE / (rhuE + vac_forrentE)` |
| `pctsvacE` | `vac_forsaleE / (ohuE + vac_forsaleE)` |
| `pctrhuM`, `pctblkM`, `pcthspM` | Existing derived share-MOE formulas from `calc_cv()` |
| `rentCV`, `med_hhincCV`, `med_hvalCV` | `(M / 1.645) / E` for the corresponding dollar measure |
| `pctrhuCV`, `pctblkCV`, `pcthspCV`, `rhuCV`, `huCV`, `popCV` | Existing share/count CV formulas; missing when the corresponding estimate is zero |

Shares and vacancy rates are missing for non-positive or missing denominators.
The existing MOE/CV formulas and their missing-value behavior are retained.
No interpolated rent, block-group missing/top-coded-rent shares, or inventory
MOE/CV is added to this direct tract product. In Step 4, this product's
post-censoring `rentE` serves as the tract-source counterpart for canonical
`interp_rent` on geographically consistent tracts. Every other row uses the
block-group interpolation, including missing/unexpected geographic flags.
Original statuses remain intact for QA. Missing selected values are never filled
from the other source, and `interp_rentPOST` uses the selected value over positive,
inflation-adjusted 2016 median rent. No tract interpolation is constructed.

## Added flags

Flags use the existing numeric double 0/1 encoding. Top-code and zero flags
retain `NA` for missing source estimates; missing flags always have a value.

| Columns | Meaning |
|---|---|
| `tc_flag_rent`, `tc_flag_lqcrent`, `tc_flag_med_hval` | Source estimate meets the threshold above; captured before censoring |
| `m_flag_rent`, `m_flag_lqcrent`, `m_flag_rhu`, `m_flag_rhucash`, `m_flag_med_hval` | Estimate is missing after rent censoring |
| `zero_flag_rhu`, `zero_flag_rhucash`, `zero_flag_med_hval` | Estimate is zero |

## Added rental inventory and validation

`rhu_inventoryE` (numeric) is the direct sum `rhuE + vac_forrentE + vac_rentedE`
from B25003_003, B25004_002, and B25004_003. Each unique source tract contributes
with unit weight. Any required estimate missing as `NA` or `NaN` makes inventory
`NA`; no partial subtotal or missing-to-zero substitution is allowed. Missing
rent, income, or source MOEs do not affect completeness. Required estimate/MOE
columns must be numeric, and observed estimates must be finite and nonnegative.

Only the key and inventory estimate are joined one-to-one onto the production
table, preserving every existing column and row. The separate diagnostic table
retains component totals (`inventory_rhuE`, `inventory_vac_forrentE`,
`inventory_vac_rentedE`), contributing/missing counts, and `inventory_incomplete`.
Every direct tract has one contributor, including a tract whose components
are all zero. Existing occupied `rhuE` and rate denominators retain their meanings.

Before saving and after reloading (§5.6), inventory missingness must match its
keyed completeness diagnostic and complete inventories must equal their three
component totals. Source-first and target-first sums reconcile over complete
targets only; incomplete targets and missing components are reported separately.
Native key membership, county coverage, and saved schema/values are also checked.

The optional parity reference is only `acs_step2_2024_tract.feather` in the
preserved reference directory. `compare_socal_parity(key = "tr2020_id")` uses
strict schema/order/type/value checks and the existing numeric tolerance,
without migration, legacy income-correction, or allocation-boundary exceptions.
Missing references explicitly mean **parity not checked**.
