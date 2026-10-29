# Schema: `acs_step2_2024_block_group_aggregated.feather`

## 1. Dataset contract

| Property | Contract |
|---|---|
| Producer | [02a_build_measures_from_block_groups.Rmd](../02a_build_measures_from_block_groups.Rmd), with [R/assemble_helpers.R](../R/assemble_helpers.R), [R/bg_aggregation_qa.R](../R/bg_aggregation_qa.R), and [R/geography_qa.R](../R/geography_qa.R). |
| Output | `../../../data/acs_step2_2024_block_group_aggregated.feather`, relative to the repository root. |
| Role / status | Step 2 source for [04_assemble_tract_panel.Rmd](../04_assemble_tract_panel.Rmd): canonical 2024 measurement bundles where `!(geo_consistent %in% 1)`, including missing/unexpected flags; source-comparison diagnostics elsewhere. Selection has no availability fallback. |
| Row grain | One row per 2010-vintage destination tract represented in the county-filtered crosswalk, including targets represented only by zero-weight links. |
| Primary key | `tr2010_id`: unique, nonmissing character GEOID matching `^06[0-9]{9}$`; state (2) + county (3) + tract (6) digits, preserving leading zeros. |
| Geographic scope | California destinations in the 14 counties below; contributing sources are not county-filtered. |
| Temporal scope | 2020–2024 ACS 5-year estimates on 2020 block groups, allocated to 2010 tracts. Dollar measures retain the source 2024 dollar basis; no inflation adjustment here. |

`step2_target_counties()` defines Southern California as Los Angeles (`037`),
Orange (`059`), Riverside (`065`), San Bernardino (`071`), and Ventura (`111`);
the Bay Area comprises Alameda (`001`), Contra Costa (`013`), Marin (`041`),
Napa (`055`), San Francisco (`075`), San Mateo (`081`), Santa Clara (`085`),
Solano (`095`), and Sonoma (`097`). All county codes use state FIPS `06`.

## 2. Inputs and provenance

Paths below are relative to the repository root.

| Input | Source grain / key | Role |
|---|---|---|
| `../../../data/acs_step1_2024_block_group.feather` ([schema](acs_step1_2024_block_group.md)) | Statewide California 2020 block group; `bg2020_id` | ACS counts, income, rent, and MOEs from `01_import_acs.Rmd`. |
| `../../../data/xwalk_bg24_tr10.feather` ([schema](xwalk_bg24_tr10.md)) | Unique (`bg2020_id`, `tr2010_id`) allocation pair | NHGIS links and population, household, housing-unit, and renter-unit allocation fractions. |
| `../../../data/parity_reference/acs_step2_24.feather` (optional) | Prior 2010 tract; `tr2010_id` | Preserved Southern California parity reference only; supplies no production measurements. Missing reference means parity not checked. |

## 3. Construction rules

The dictionary uses these formulas. Aggregation operands are **source BG
values**; derived ratios use **aggregated tract values**.

- **`S_w(x)`** = `sum(x[w > 0] * w[w > 0])`, with strict completeness (§6).
  Subscripts `pop`, `hh`, `hu`, and `renthu` denote `wt_pop`, `wt_hh`, `wt_hu`,
  and `wt_renthu`. Counts are not rounded or renormalized.
- **`W(x, w)`** = `matrixStats::weightedMean(x, w, na.rm = TRUE)`.
  Normalize by effective weights for available source values.
  Income estimates use `hhE * wt_hh` and require complete contributing `hhE`;
  income MOEs use `rhuE * wt_renthu` and require complete contributing `rhuE`.
  Source income is retained independently of rent.
- **`Q_b(m)`** = `sqrt(sum((m * rel_wt_b)^2, na.rm = TRUE))`, where
  `rel_wt_rhu = rhuE * wt_renthu / S_renthu(rhuE)`,
  `rel_wt_hu = huE * wt_hu / S_hu(huE)`, and
  `rel_wt_pop = popE * wt_pop / S_pop(popE)`. Each result requires complete
  counts for its relative-weight base; zero-total exceptions are in §6.
- **`D(p, m_n, m_d, d)`** = `sqrt(pmax(0, m_n^2 - p^2 * m_d^2)) / d`
  when `d != 0`, otherwise `NA`: the implemented share-MOE formula.
- **`CV(x)`** = `(xM / 1.645) / xE`, with zero/missing rules in §6.
  MOEs use the source 90% confidence basis; CVs and shares are unscaled ratios.

Source B25064 classification preserves genuine `3500` estimates using finite
MOE and a complete non-top distribution; `3501` is upper censoring, and `99`
is a lower-interval code. Other missing/conflicting evidence is retained in
source preparation. `rhu_miss_rent` and `pct_miss_rent` use missing **cleaned BG
source rent**, including censoring, with unchanged renter weights and denominator.
The analyst approved correcting their old `>= 3500` source rule. The obsolete
`pct_tc_rent` component-exposure share and `pct_m_rent` decomposition are removed.
Neither component medians nor highest-bin mass determine final-tract status.
Lower-quartile rent retains its separate `>= 3500` censor. No source mean of
rent, lower-quartile rent, or house value is saved.

### Rental inventory

`rhu_inventoryE = S_renthu(rhuE) + S_renthu(vac_forrentE) + S_renthu(vac_rentedE)`:
renter-occupied (B25003_003), vacant for rent (B25004_002), and rented but
unoccupied (B25004_003) units. All three components use renter weights and
must be complete. Persisted `vac_forrentE` instead uses housing-unit weights
for vacancy rates and cannot substitute for inventory's vacancy component.
Inventory is not a rent denominator; no inventory MOE/CV is produced.

### Interpolated rent

Require complete `rhucashE` and all 24 `grentcat*E` counts, with `rhucashE > 0`.
Choose the first bin whose cumulative count reaches `rhucashE / 2`. For an
interior bin, `interp_rent = lower + (upper - lower) * (rhucashE / 2 - prior_cumulative) / bin_count`,
using the inclusive dollar bounds in §5 (e.g. $1,000–1,249 has width 249).
Rent and status come from this same allocated distribution. Bin 24 means
`top_coded`, numeric rent NA, and a $3,500 bound in 2024 dollars. Exactly half
reached below bin 24 is not top-coded. Bin 1, zero renters, or incomplete
counts give `unavailable_other`; inconsistent totals (absolute tolerance `1e-6`)
or no positive contributors give `unresolved`. Invalid negative/nonfinite counts
are also unresolved in the helper; producer count validation stops them first.
No tolerance alters the median threshold. All non-observed statuses have
numeric rent NA, and unavailable/unresolved flags and bounds are NA.

## 4. Join / allocation contract

- Filter crosswalk **destinations** to the target counties; retain every link,
  including sources outside those counties. The crosswalk is many-to-many;
  joining ACS on its unique `bg2020_id` must preserve allocation pairs and row
  count. Full-source sums across all destinations equal one within `1e-6`;
  retained fractions may sum to less than one and are never renormalized.
- Before the ACS join, `bg_reference_2024` freezes original pairs, four weights,
  target IDs, and positive contributors by family. Any positive weight requires
  a matching ACS row, independently of estimate missingness. Unmatched links
  are allowed only when all four weights are zero; they retain their targets.
- Supplemental counts, inventory, and the rent/metadata bundle join
  on `tr2010_id` with identical unique key sets and no row multiplication.
  Every `merge_df()` tract join must have `merge == "both"`; only the final
  `left_id`, `right_id`, and `merge` tags persist.
- Step 4 joins this product on `tr2010_id`. Geographically consistent rows use
  the [native 2024 tract source](acs_step2_2024_tract.md). Block-group rent-quality
  shares remain source-specific diagnostics even where canonical measurements
  come from that native tract source.

## 5. Columns

All **91 persisted columns** are listed below, grouped for readability; select
by name. `E` denotes an estimate, `M` its named MOE, and `CV` a coefficient of
variation. Structure counts measure housing units, not buildings.

Valid-value conventions: **Count** = nonnegative, potentially fractional double;
**Dollars** = nonnegative source-dollar amount; **Share** = unscaled ratio
(1 = 100%); **MOE** = nonnegative uncertainty in the estimate's units;
**CV** = nonnegative ratio with no upper bound. All inherit §6 missingness rules.
These are expected domains, not universal range assertions; §7 identifies
checks. Shares are expected in [0, 1], but are not clipped.

| Column | Type | Source / construction | Description | Valid values / missingness |
|---|---|---|---|---|
| `tr2010_id` | character | Crosswalk destination ID | 2010 tract key | §1 key constraints |
| `huE` | numeric | `S_hu(huE)` | Total housing units | Count |
| `rhuE` | numeric | `S_renthu(rhuE)` | Renter-occupied units | Count |
| `rhu_baseE` | numeric | `S_renthu(rhu_baseE)` | Total occupied units, tenure-table base | Count |
| `hhE` | numeric | `S_hh(hhE)` | Total households | Count |
| `popE` | numeric | `S_pop(popE)` | Total population | Count |
| `tot_vacE` | numeric | `S_hu(tot_vacE)` | Vacant housing units | Count |
| `tot_vac_baseE` | numeric | `S_hu(tot_vac_baseE)` | Total housing units, occupancy-status base | Count |
| `pop_blkE` | numeric | `S_pop(pop_blkE)` | Black or African American alone population | Count |
| `pop_hspE` | numeric | `S_pop(pop_hspE)` | Hispanic or Latino population | Count |
| `pop_aaE` | numeric | `S_pop(pop_aaE)` | Asian alone population | Count |
| `pop_raceE` | numeric | `S_pop(pop_raceE)` | Total population, race-table base | Count |
| `pop_ethnE` | numeric | `S_pop(pop_ethnE)` | Total population, Hispanic-origin base | Count |
| `sfd_detE` | numeric | `S_hu(sfd_detE)` | Single-family detached units | Count |
| `sfd_baseE` | numeric | `S_hu(sfd_baseE)` | Total units, structure-table base | Count |
| `mf5E` | numeric | `S_hu(mf_5_9E + mf_10_19E + mf_20_49E + mf_50E)`; source subtotal `mfE` renamed | Units in structures with 5+ units | Count |
| `smfE` | numeric | `S_hu(sfd_attE + duplexE + quadplexE)` | Attached single-family and units in 2–4-unit structures | Count |
| `nsfaE` | numeric | `smfE + mf5E` | Attached single-family and all multifamily units; excludes detached, mobile, and other units | Count |
| `vac_forrentE` | numeric | `S_hu(vac_forrentE)` | Vacant-for-rent units for vacancy rates | Count |
| `vac_forsaleE` | numeric | `S_hu(vac_forsaleE)` | Vacant-for-sale-only units | Count |
| `ohuE` | numeric | `S_hu(ohuE)` | Owner-occupied units | Count |
| `rhu_inventoryE` | numeric | Three renter-weighted components (§3) | Rental housing inventory | Count; missing if any component incomplete |
| `rhucashE` | numeric | `S_renthu(rhucashE)` | Renter units paying cash rent | Count |
| `grentcat1E` | numeric | `S_renthu(grentcat1E)` | Cash-rent units: monthly gross rent < $100 | Count |
| `grentcat2E` | numeric | `S_renthu(grentcat2E)` | Gross rent $100–149 | Count |
| `grentcat3E` | numeric | `S_renthu(grentcat3E)` | Gross rent $150–199 | Count |
| `grentcat4E` | numeric | `S_renthu(grentcat4E)` | Gross rent $200–249 | Count |
| `grentcat5E` | numeric | `S_renthu(grentcat5E)` | Gross rent $250–299 | Count |
| `grentcat6E` | numeric | `S_renthu(grentcat6E)` | Gross rent $300–349 | Count |
| `grentcat7E` | numeric | `S_renthu(grentcat7E)` | Gross rent $350–399 | Count |
| `grentcat8E` | numeric | `S_renthu(grentcat8E)` | Gross rent $400–449 | Count |
| `grentcat9E` | numeric | `S_renthu(grentcat9E)` | Gross rent $450–499 | Count |
| `grentcat10E` | numeric | `S_renthu(grentcat10E)` | Gross rent $500–549 | Count |
| `grentcat11E` | numeric | `S_renthu(grentcat11E)` | Gross rent $550–599 | Count |
| `grentcat12E` | numeric | `S_renthu(grentcat12E)` | Gross rent $600–649 | Count |
| `grentcat13E` | numeric | `S_renthu(grentcat13E)` | Gross rent $650–699 | Count |
| `grentcat14E` | numeric | `S_renthu(grentcat14E)` | Gross rent $700–749 | Count |
| `grentcat15E` | numeric | `S_renthu(grentcat15E)` | Gross rent $750–799 | Count |
| `grentcat16E` | numeric | `S_renthu(grentcat16E)` | Gross rent $800–899 | Count |
| `grentcat17E` | numeric | `S_renthu(grentcat17E)` | Gross rent $900–999 | Count |
| `grentcat18E` | numeric | `S_renthu(grentcat18E)` | Gross rent $1,000–1,249 | Count |
| `grentcat19E` | numeric | `S_renthu(grentcat19E)` | Gross rent $1,250–1,499 | Count |
| `grentcat20E` | numeric | `S_renthu(grentcat20E)` | Gross rent $1,500–1,999 | Count |
| `grentcat21E` | numeric | `S_renthu(grentcat21E)` | Gross rent $2,000–2,499 | Count |
| `grentcat22E` | numeric | `S_renthu(grentcat22E)` | Gross rent $2,500–2,999 | Count |
| `grentcat23E` | numeric | `S_renthu(grentcat23E)` | Gross rent $3,000–3,499 | Count |
| `grentcat24E` | numeric | `S_renthu(grentcat24E)` | Gross rent ≥ $3,500 | Count |
| `med_hhincE` | numeric | `W(med_hhincE, hhE * wt_hh)` | Household-weighted mean of BG median household incomes | Dollars; requires complete `hhE` |
| `interp_rent` | numeric | Median-bin interpolation (§3) | Interpolated median monthly gross rent | Dollars; interior bins only |
| `pctrvacE` | numeric | `vac_forrentE / (rhuE + vac_forrentE)` | Rental vacancy rate | Share |
| `pctsvacE` | numeric | `vac_forsaleE / (ohuE + vac_forsaleE)` | For-sale vacancy rate | Share |
| `pctrhuE` | numeric | `rhuE / huE` | Renter-occupied share of all housing units | Share |
| `pctvacE` | numeric | `tot_vacE / tot_vac_baseE` | Vacant share of housing units | Share |
| `pctblkE` | numeric | `pop_blkE / pop_raceE` | Black alone share of population | Share |
| `pcthspE` | numeric | `pop_hspE / pop_ethnE` | Hispanic or Latino share of population | Share |
| `pctaaE` | numeric | `pop_aaE / pop_raceE` | Asian alone share of population | Share |
| `pctsfdE` | numeric | `sfd_detE / sfd_baseE` | Detached single-family share of units | Share |
| `med_hhincM` | numeric | `W(med_hhincM, rhuE * wt_renthu)` | Weighted mean of source income MOEs | MOE; requires complete `rhuE` |
| `rhuM` | numeric | `Q_rhu(rhuM)` | Renter-occupied-unit MOE | MOE; missing if `rhuE = 0` |
| `rhu_baseM` | numeric | `Q_hu(rhu_baseM)` | Occupied-unit-base MOE | MOE |
| `tot_vacM` | numeric | `Q_hu(tot_vacM)` | Vacant-unit MOE | MOE |
| `tot_vac_baseM` | numeric | `Q_hu(tot_vac_baseM)` | Occupancy-status-base MOE | MOE |
| `pop_blkM` | numeric | `Q_pop(pop_blkM)` | Black alone population MOE | MOE |
| `pop_hspM` | numeric | `Q_pop(pop_hspM)` | Hispanic or Latino population MOE | MOE |
| `pop_aaM` | numeric | `Q_pop(pop_aaM)` | Asian alone population MOE | MOE |
| `pop_raceM` | numeric | `Q_pop(pop_raceM)` | Race-table population-base MOE | MOE |
| `sfd_detM` | numeric | `Q_hu(sfd_detM)` | Detached-unit MOE | MOE |
| `sfd_baseM` | numeric | `Q_hu(sfd_baseM)` | Structure-table-base MOE | MOE |
| `huM` | numeric | `Q_hu(huM)` | Total-housing-unit MOE | MOE; missing if `huE = 0` |
| `popM` | numeric | `Q_pop(popM)` | Total-population MOE | MOE; missing if `popE = 0` |
| `pctrhuM` | numeric | `D(pctrhuE, rhuM, rhu_baseM, rhu_baseE)` | Renter-share MOE | MOE; denominator differs from estimate |
| `pctblkM` | numeric | `D(pctblkE, pop_blkM, pop_raceM, pop_raceE)` | Black-share MOE | MOE |
| `pcthspM` | numeric | `D(pcthspE, pop_hspM, pop_raceM, pop_raceE)` | Hispanic-share MOE | MOE; denominator differs from estimate |
| `med_hhincCV` | numeric | `CV(med_hhinc)` | Income coefficient of variation | CV; unguarded zero estimate (§6) |
| `pctrhuCV` | numeric | `CV(pctrhu)` | Renter-share coefficient of variation | CV |
| `pctblkCV` | numeric | `CV(pctblk)` | Black-share coefficient of variation | CV |
| `pcthspCV` | numeric | `CV(pcthsp)` | Hispanic-share coefficient of variation | CV |
| `rhuCV` | numeric | `CV(rhu)` | Renter-unit coefficient of variation | CV |
| `huCV` | numeric | `CV(hu)` | Housing-unit coefficient of variation | CV |
| `popCV` | numeric | `CV(pop)` | Population coefficient of variation | CV |
| `rhu_miss_rent` | numeric | `S_renthu(if_else(is.na(rentE), rhuE, 0))` after censoring | Renter units in BGs with missing/censored source rent | Count |
| `pct_miss_rent` | numeric | `rhu_miss_rent / rhuE` | Share of renter units with missing/censored source rent | Share; [0, 1] within `1e-10`, or missing |
| `tc_flag_rent_24` | double | Final allocated median bin | Confirmed upper censoring | 1 top-coded; 0 observed; NA unavailable/unresolved |
| `rent_status_24` | character | Same distribution as `interp_rent` | Final tract rent classification | observed / top_coded / unavailable_other / unresolved; never NA |
| `rent_censor_bound_24` | double | Final median in bin 24 | Lower bound, 2024 dollars | 3500 for top_coded; NA otherwise |
| `rent_median_bin` | integer | First cumulative count >= half | Final median category | 1–24; NA if incomplete/invalid/zero/no contributors |
| `rent_status_reason` | character | Distribution/contributor evidence | Why rent is observed, censored, or missing | interior_distribution_median / median_in_open_top_bin / median_in_excluded_bottom_bin / incomplete_distribution / zero_cash_rent_units / cash_bin_total_conflict / invalid_distribution / no_positive_weight_sources |
| `rhu_id` | logical | Added by `calc_agg_vars()` | Aggregation-row tag | Always `TRUE` |
| `left_id` | logical | Final `merge_df()` | Row present on left of interpolated-rent join | Always `TRUE` |
| `right_id` | logical | Final `merge_df()` | Row present on right of interpolated-rent join | Always `TRUE` |
| `merge` | character | Final `merge_df()` | Interpolated-rent join status | Always `"both"` |

## 6. Missingness and special-value rules

- **Counts:** any `NA` or `NaN` on a positive weight makes that count `NA_real_`;
  observed zeros are valid. Zero-weight missing values are ignored; a
  reference-confirmed empty contributor set gives zero. Structure subtotals
  use ordinary addition, so any missing component makes that source subtotal
  missing. `rhu_miss_rent` requires `rhuE` only where source rent is missing or
  censored. Inventory requires all three contributing estimates; missing rent,
  income, or MOEs does not affect its completeness.
- **Income:** `W` omits missing source values and their weights. Complete
  contributing weight-base counts are necessary but insufficient: all missing
  values, zero usable weight, or missing effective weights can leave `NA`/`NaN`.
  There is no income censoring or imputation.
- **MOEs:** incomplete weighting-base counts force `Q` to `NA`. Otherwise,
  missing products are omitted without renormalizing relative weights;
  all missing products sum to zero. At zero base totals, `rhuM`, `huM`, and
  `popM` are missing; unguarded count MOEs can be zero. MOE missingness is not
  generally coupled to its named estimate's missingness.
- **Ratios:** share/rate estimates are `NA` for nonpositive or missing
  denominators. Share MOEs use `D`'s nonzero guard and clamp negative radicands
  to zero. CVs are missing for zero estimates except `med_hhincCV`, whose
  unguarded division can yield `Inf` or `NaN`. Missing required counts propagate
  through dependent measures, including income CV's household/renter counts.
- **Component coverage:** `pct_miss_rent` requires complete positive allocated
  renter counts; zero or incomplete denominator gives NA. The numerator requires
  renter counts where corrected BG source rent is missing. Its units and meaning
  remain component coverage, independent of final-tract status and source selection.
- `tc_flag_rent_24` and its bound depend on cash-renter/bin counts, not `rhuE`.
  Zero cash renters yield unavailable status and a missing flag. Raw B25064 evidence
  remains in Step 1; detailed BG-level reasons stay in allocation diagnostics,
  while the persisted status/reason/bin describe only the final tract distribution.

## 7. Validation contract

### Fail-fast invariants

Checkpoints refer to the producing notebook. Count/inventory reconciliation
uses `1e-10` relative tolerance with a unit floor; readback is exact.

| Checkpoint | Required condition |
|---|---|
| Inputs and allocations, §2.2 | Unique nonmissing ACS keys and allocation pairs; valid character link IDs; four finite weights in [0, 1]; full-source sums within `1e-6` of one; retained sums no greater than full sums within tolerance. All target-county ACS sources appear in the crosswalk. |
| Contributors, §§2.2–2.5, 2.8, 3.6 | Exact original keyed links/weights and target set preserved; every positive-weight link has an ACS row; unmatched links have four zero weights. Contributing counts are numeric and observed values finite/nonnegative; diagnostics agree with the reference. |
| Tract joins/geography, §§2.5–2.8, 3.1, 3.5 | Original unique target set preserved and all tract joins complete; inventory join preserves prior rows/columns. Destination IDs are California tracts with exactly the configured county set. No fixed empirical row count. |
| Counts/dependencies/inventory, §§2.5–2.8, 3.6 | Complete counts reconcile to independent source totals; incomplete counts and dependent cells are missing. Inventory source estimate/MOE columns must be numeric. Inventory missingness equals component incompleteness; complete inventory equals its three components; zero-contributor inventory is zero. Source-first/target-first inventory reconciles over complete targets only. |
| Optional parity, §2.8 | Shared column names/order/types agree. `schema_migration = "2024"` permits inventory and rent metadata additions, retired rent-share removals, and the fields below. The final-median flag may move with its bundle; other shared order/types remain strict. Unexpected value changes or unaffected-tract membership changes fail; verified income/count/rent corrections require reference and candidate to match source-derived expectations. |
| Saved output, §§3.1, 3.3, 3.6 | Exact in-memory/readback equality of rows, values, column names/order, types/classes; removed fields absent; numeric flags are double 0/1/missing. Count/dependent/inventory checks repeat independently of parity availability. |
| Rent metadata/coverage, §3.5 | Valid status/flag/bound/value combinations; coverage agrees with corrected source missingness and unchanged weights/denominator within `1e-10`; observed shares finite in [0, 1]. |

The fixed parity-removal list, also rejected in current outputs, is:
`rhu_lrE`, `rhu_lr2E`, `rentE`, `rentM`, `rentCV`, `lqcrentE`, `lqcrentM`,
`med_hvalE`, `med_hvalM`, `med_hvalCV`, `hu_miss_hval`, `pct_miss_hval`,
`pct_tc_rent`, `tc_flag_rent`, `m_flag_rent`.

### Analyst-review diagnostics

| Diagnostic | Review expectation |
|---|---|
| `source_weight_qa_2024_bg_aggregated`, `zero_weight_unmatched` | Inspect retained fractions; use zero-link details when investigating zero-valued targets. |
| `bg_count_qa_2024`, `bg_county_family_qa_2024`, `bg_dependent_qa_2024` | Review incomplete measures by county/family and trace missing source IDs; valid contributors do not imply complete estimates. |
| Inventory component/missing-source/county diagnostics | Review incomplete targets separately; complete-target totals do not estimate the entire sample's inventory. |
| Numeric, rent, and income summaries, §§2.8, 3.2–3.5 | Inspect missing interpolation, ranges, nonfinite uncertainty, and implausible shares/rents; no empirical missingness threshold is enforced. |
| `socal_parity_2024_bg_aggregated` | Review schema/value differences and `boundary_review` cases against positive cross-boundary allocations. All-zero links confer no parity exception; absent references remain unchecked. |

Detailed contributor, inventory-component, and parity tables stay in notebook
objects; only the diagnostic/tag fields listed in §5 persist.

## 8. Known limitations / intentional exceptions

- Income is a weighted mean of BG medians, not a tract-distribution median.
  Its estimate uses household weights while its MOE uses renter weights.
  Likewise, `rhu_baseE` uses renter weights and `rhu_baseM` uses relative
  housing-unit weights.
- **Denominator inconsistencies in current code:** `pctrhuE` divides by `huE`,
  but `pctrhuM` uses `rhu_baseE`/`rhu_baseM`; `pcthspE` uses `pop_ethnE`, but
  `pcthspM` uses `pop_raceE`/`pop_raceM`. These formulas are documented without
  harmonization. Different allocation families can also put shares outside
  [0, 1]; only rent-quality shares receive explicit range assertions.
- Missing source MOEs can yield zero aggregate MOEs; zero does not establish
  complete uncertainty information. Count completeness does not establish
  acceptable sampling precision or complete income information.
- Individual attached/small/large-multifamily components and `vac_rentedE`
  are not standalone columns. Source IDs, weights, and detailed completeness
  diagnostics are also absent. Readback checks the produced table rather than
  an independent fixed column allowlist; optional parity adds schema checks.

## 9. Validation and regeneration

- **Focused validation:** `Rscript --vanilla tests/test_bg_aggregation_qa.R`
  covers synthetic BG contributors, counts, dependencies, inventory, and
  temporary readback; `tests/test_income_censoring.R` covers income retention; `tests/test_rent_metadata.R`
  covers distribution boundaries and source classification.
- **Documentation/column audit:** compare §5's 91 unique names with
  `calc_agg_vars()` (24 rent bins and `mfE` → `mf5E`), supplemental/inventory
  joins, `calc_missing_vars()`, `calc_pct_vars()`, `calc_cv(source = "bg_agg")`,
  and final derived/flag/interpolation joins. Check local links and parse
  notebook chunks without executing them.
- **Analyst-run regeneration:** execute `02a_build_measures_from_block_groups.Rmd`
  with current Step 1 files and repository packages. It writes the output
  above and validates readback in §3; handle existing outputs deliberately
  and keep parity snapshots separate. This producer requires no ACS API call
  or native-tract notebook execution.
