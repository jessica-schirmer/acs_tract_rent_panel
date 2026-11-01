# QA guide: block-group crosswalks and aggregation

## Notebook 1: crosswalk validation and completeness limits

**Applies to:** [01_import_acs.Rmd](../01_import_acs.Rmd), especially §§6.1, 7.2, and 7.6.
This notebook imports the NHGIS 2020 block-group-to-2010-tract crosswalk and
writes `xwalk_bg24_tr10.feather` for the 2024 ACS aggregation.

**Notebook 1 validates the imported crosswalk's structure, allocation totals,
and preservation. A successful run does not independently prove that the
original NHGIS file contains every required BG-to-tract link.**

1. **IDs, allocation pairs, and weights (§6.1).**
   `assert_bg_crosswalk()` in [R/acs_input_qa.R](../R/acs_input_qa.R) requires
   nonmissing character IDs with 12 digits for BGs and 11 digits for tracts,
   unique `(bg2020_id, tr2010_id)` pairs, and numeric, finite allocation weights
   in `[0, 1]`. Missing required columns or invalid join flags also fail.
   These are assertions: violations stop execution before saving.

2. **Full-source weight sums (§6.1).**
   The helper groups by `bg2020_id` and separately sums `wt_pop`, `wt_hh`,
   `wt_hu`, and `wt_renthu` across **all destination tracts**. Each sum must be
   within `1e-6` of one; otherwise execution stops. The results remain in
   `xbg_weight_sums`. No links are dropped and no weights are renormalized.
   These are sums for each source BG, not sums of incoming weights for a tract.

   For example, if a BG has links weighted `0.6` and `0.4`, losing the `0.4`
   link would leave a sum of `0.6` and fail. If every row for that BG were
   already absent from the imported file, there would be no group to sum,
   so this check alone could not detect that omission.

3. **BG coverage against ACS (§6.1).**
   `bg_coverage_diagnostics()` compares distinct BG IDs using two `anti_join()`
   operations. `bg_coverage_24$acs_only` contains ACS BGs absent from the
   crosswalk; `$crosswalk_only` contains crosswalk BGs absent from ACS.
   `$summary` and `$by_county` report counts, and `$crosswalk_only_links`
   retains the unmatched crosswalk links and weights. **These coverage
   differences are diagnostic only: they do not cause notebook 1 to fail.**
   A BG absent from both inputs would not appear in either difference table.

4. **Preservation through processing and saving (§§6.1, 7.2, 7.6).**
   Row counts must match the imported count. After Feather reload,
   `assert_step1_readback()` requires exact equality with the validated
   in-memory crosswalk: keys, row order, column names/order, storage types,
   and every value. Weight equality at readback is exact, without the source-sum
   tolerance. The notebook also repeats the structural and weight-sum checks.

There is no independent comparison against a complete 2010 destination-tract
universe or an independently established set of geographic links. Weight sums
and exact readback cannot establish whether the original file omitted or
misassigned a geographic relationship.

Notebook `02a` uses this imported crosswalk to define its frozen reference of
expected contributors. Its checks detect subsequent lost links and missing
required ACS records. They do not independently establish the completeness of
the original NHGIS crosswalk. In the guidance below, an "original allocation
link" means a link present in that imported reference.

## Notebook 2a: contributor integrity and missing estimates

**Applies to:** [02a_build_measures_from_block_groups.Rmd](../02a_build_measures_from_block_groups.Rmd)
(Step 2a), which aggregates 2024 ACS block groups to 2010 tracts and writes
`acs_step2_2024_block_group_aggregated.feather`.

**Missing required count estimates produce missing aggregates. Missing required
contributor records or lost allocation links cause an error.**

| Situation | Notebook behavior |
|---|---|
| A contributing BG's ACS record exists, but a required count is `NA` or `NaN`. | That tract's affected count becomes `NA_real_`. Missing estimates alone do not cause an error. |
| An original allocation link is lost, or a BG with any positive allocation weight has no matching ACS record. | Execution stops with an error, even if the tract still has other contributing BGs. |
| An original allocation link is retained, its ACS record is absent, and all four allocation weights are exactly zero. | The link is retained as an exempt, noncontributing row. It does not affect count totals or completeness. |

An **incomplete contributor set** therefore causes an error. **Incomplete count
values within an intact contributor set** cause missing aggregates. A successful
run confirms the contributor checks passed; it does not imply every estimate is
observed.

Completeness is assessed separately for each count using its allocation weight.
Every strictly positive weight requires the corresponding source value, however
small the weight. Missing values at zero weight are ignored, and observed source
zeros are valid. Other counts for the same tract can remain observed.

| Allocation weight | Count family |
|---|---|
| `wt_pop` | Population and race/ethnicity counts |
| `wt_hh` | Household count |
| `wt_hu` | Housing, vacancy, owner-occupied, and structure counts |
| `wt_renthu` | Renter counts/base, cash-rent count, all 24 rent bins, and `rhu_miss_rent` |

For `rhu_miss_rent`, the required source count is
`if_else(is.na(rentE), rhuE, 0)` after censoring. Missing `rhuE` affects this
numerator only when source rent is missing or censored. Rental inventory
separately requires all three components (`rhuE`, `vac_forrentE`, `vac_rentedE`)
on positive `wt_renthu` links; any missing component makes inventory missing.

A target with no expected positive-weight contributors for a family receives
numeric zero for its additive counts. The original crosswalk reference establishes
this status, so lost contributors cannot be mistaken for an empty contributor
set. Targets represented entirely by exempt all-zero links survive. Exempt links
and zero-contributor flags require no separate routine manual review once the
assertions pass; they are useful when investigating a particular zero-valued tract.

The missing-value rule is implemented by `strict_weighted_sum()`, called from
`calc_agg_vars()` in [R/assemble_helpers.R](../R/assemble_helpers.R) and the
notebook's supplemental aggregation in §2.5. Contributor and completeness checks
live in [R/bg_aggregation_qa.R](../R/bg_aggregation_qa.R). The notebook checks
original links and weights after joining (§2.2), before aggregation (§2.5), and
again during saved-output validation (§3.6). Duplicate, substituted, or unexpected
pairs, changed weights, lost targets, and inconsistent diagnostics also fail.

To assess whether the missing-value change affected tract measures, inspect
`expected_count_corrections_2024` in §2.8. It compares legacy missing-dropping
sums with corrected sums using identical current sources and weights across all
target counties. Each row identifies a changed tract/measure, with `legacy` and
`corrected` values, including natural changes in dependent measures. **Zero rows
means none of the compared measures changed.** `NULL` means the comparison was
not constructed; it is not a zero-change result. It can be calculated independently:

```r
expected_count_corrections_2024 <- bg_count_parity_expectations(
  acs_2024_bg_allocations, bg_reference_2024
)
View(expected_count_corrections_2024)
```

`socal_parity_2024_bg_aggregated` is the existing comparison against preserved
Southern California outputs. It recognizes verified count corrections, but an
additional manual review of historical/boundary differences is a separate task
from assessing the effect of this missing-value change.

For investigation, §2.5 retains `bg_count_qa_2024$measure` and `$missing_sources`,
plus `bg_county_family_qa_2024`. Inventory has separate missing-component and
county diagnostics. These tables remain outside the production Feather.

Dependent formulas require their own complete count inputs. In particular,
`calc_interp_rent()` uses `rent_distribution()` in
[R/rent_metadata.R](../R/rent_metadata.R) and requires the cash-renter total
`rhucashE` and **all 24 rent bins**, including bins above the median. Missing
any of these yields missing numeric rent and `unavailable_other` with reason
`incomplete_distribution`; a positive total and consistent bin sum are also
required for an observed median. See the
[current construction rules](../schemas/acs_step2_2024_block_group_aggregated.md#3-construction-rules)
for endpoint and unresolved-distribution cases.

`pct_miss_rent` measures allocated renter coverage associated with missing or
censored **cleaned BG source rent**. It remains a BG diagnostic even where
Step 4 selects native tract rent. The year-specific `tc_flag_rent_24` instead
describes the final tract median; it is not a component-exposure share. The
old `pct_tc_rent` / `pct_m_rent` decomposition and `rent_share_deferred_2024`
review instructions are superseded by the
[rent-metadata contract](../schemas/acs_full.md#6-missingness-and-special-value-rules).
