# Income censoring: analyst decision and correction

Historical notebook references below describe `02_assemble.Rmd` before its split.
Current successors are [02a_aggregate_2024_block_groups.Rmd](../02a_aggregate_2024_block_groups.Rmd)
(block-group aggregation, §2) and [02b_prepare_tract_sources.Rmd](../02b_prepare_tract_sources.Rmd)
(native tract preparation, §§2–3). Historical section/line numbers and findings
are retained; successor links do not imply that those line numbers still apply.

**Status:** Implemented following the analyst's decision in
[task_spec_04_confirm_plan.md](../task_spec_04_confirm_plan.md) and subsequent
authorization to implement the plan. Median household income is retained
independently of missing or top-coded rent. Production outputs have not been
written. The assembly parity checks now verify this approved correction against
the preserved references. Cached-input assembly and complete Southern California
difference-table validation passed; downstream panel/sample acceptance remains
analyst-run. Step 2 now also implements rental inventory and the narrow schema
migration described below; the dated cached-input findings in this note remain
historical and do not validate regenerated inventory outputs.

**Subsequent Step 2 tract-source addition:** The 2024 direct tract path now
retains source income independently and validates it on `tr2020_id`. Its parity
is strict; the historical income-correction exceptions below apply only to the
2016 and block-group products. Current filenames and diagnostic suffixes are
listed in the [output migration](../README.md#stage-2-output-naming-and-references).
Historical filenames and empirical results below remain unchanged.

**Subsequent BG count-completeness hardening:** `02a` now requires complete
positive-weight household counts for aggregated income and complete renter
counts for its income MOE; the income CV requires both. The weighted-mean and
CV formulas, available-income treatment, and independence from rent censoring
remain. Corrected parity expectations apply these count gates; historical
findings below predate this change. See the [current BG schema](../schemas/acs_step2_2024_block_group_aggregated.md).

**Files changed:** [R/assemble_helpers.R](../R/assemble_helpers.R),
[R/geography_qa.R](../R/geography_qa.R),
[tests/test_income_censoring.R](../tests/test_income_censoring.R), this note,
[02_assemble.Rmd](../02a_aggregate_2024_block_groups.Rmd) (income expectations, parity calls, and prose),
[acs_step2_16.md](../schemas/acs_step2_16.md),
[acs_step2_24.md](../schemas/acs_step2_24.md), and the income-status passage in
[README.md](../README.md).

The [inspection](../docs/acs_tract_bay_area_inspection.md) establishes the issue.
This investigation concerns only its rent/income interaction.

## Previous behavior

Before the correction, `censor_tc_vars()` evaluated these assignments in order:

```r
mutate(rentE = ifelse(rentE >= 3500, NA, rentE),
       lqcrentE = ifelse(lqcrentE >= 3500, NA, lqcrentE),
       med_hhincE = ifelse(rentE >= 2000000, NA, med_hhincE))
```

The old income expression saw the updated `rentE`. Its condition was never `TRUE`:
rent is either below 3500 (`FALSE`) or missing (`NA`). `ifelse(NA, NA, income)`
returns `NA`, so the absence of a true condition does **not** make it inactive.

| Original rent condition | Previous result for available `med_hhincE` |
|---|---|
| Non-missing `rentE < 3500`, including zero | Retained unchanged, irrespective of income's value. |
| `rentE >= 3500`, including exactly 3500 | Set to `NA` after rent is censored. |
| Missing `rentE` | Set to `NA`. |
| Missing or top-coded `lqcrentE` alone, with `rentE < 3500` | Retained unchanged. |

Already missing income stays missing. The helper does not consult renter counts
or apply a threshold to income itself. No rows are dropped.

The calls in [02_assemble.Rmd](../02a_aggregate_2024_block_groups.Rmd) applied this rule to 2024
block-group allocation rows in §2.4, before tract aggregation, and directly to
2016 tracts in §3.2. In 2024, `calc_agg_vars()` uses
`weightedMean(med_hhincE, w = hhE * wt_hh, na.rm = TRUE)`. Under the old helper,
newly missing income contributions were excluded. This could alter a tract's
income while leaving it non-missing, or leave a missing aggregate if all usable
contributions were lost. The correction restores those income contributions.

## Evidence reviewed before the analyst decision

| Project evidence | What it establishes |
|---|---|
| Previous [2016 step-2 schema](../schemas/acs_step2_16.md), introduced in commit `0a9ed5e` | Called the expression a "Known quirk (carried unchanged from source logic)" and claimed income was effectively not censored. This was a description of presumed execution, not an explicit decision to retain all available income. It overlooked missing-condition propagation. |
| Notebook §2.4 and §3.2 decision prose before Task 03A | Explained censoring rent at 3500, but supplied no rationale or policy for income depending on rent. |
| Previous [2024 step-2 schema](../schemas/acs_step2_24.md) | Describes rent censoring before aggregation and weighted means of income, but does not state the income exclusion. |
| [01_acs.Rmd](../01_acs.Rmd) and [step-1 schemas](../schemas/acs_step1_2016_tract.md) | Import `rent` from `B25064_001` and `med_hhinc` from `B19013_001`; the revised tract and block-group lists retain these same codes for both years and grains. The project adds no upstream rule tying income availability to rent. |
| Helper and focused history | The same income expression appears in the initial notebook (`25da173`) and its extraction to `R/assemble_helpers.R` (`0a9ed5e`). These changes supply no income-censoring rationale. The 2,000,000 threshold also appears in median-house-value flagging; that is not evidence for an income threshold or authorization to change another variable. |
| [R/merge_helpers.R](../R/merge_helpers.R) | Carries income and its CV into both vintages, inflation-adjusts 2016 dollar measures, and derives the income change ratio. This establishes downstream dependencies, not the desired censoring rule. |

Task 03A established execution but could not establish the intended research
rule from the repository. It corrected the documentation and preserved the
calculation pending an analyst decision. The subsequent explicit decision below
resolved that ambiguity and authorized this correction.

## Analyst decision and implementation

**Approved rule:** Median household income must not become missing solely
because rent is missing or top-coded. Its available source values and existing
missingness are retained. No independent income-censoring rule was found in the
project code, and no new income threshold or missing-value rule is introduced.

The income correction in [censor_tc_vars()](../R/assemble_helpers.R) removed
`med_hhincE = ifelse(rentE >= 2000000, NA, med_hhincE)`. The current shared helper retains only the separate lower-quartile assignment:

```r
mutate(lqcrentE = ifelse(lqcrentE >= 3500, NA, lqcrentE))
```

This shared helper now leaves income unchanged for 2016 tracts and for 2024
block-group allocation rows before aggregation. In 2024, all available income
contributions retain their existing `hhE * wt_hh` weights; missing source
income is still omitted by `na.rm = TRUE`. An aggregate with all source incomes
missing remains missing. The aggregation and CV formulas are unchanged.

Median gross rent now uses the [source-evidence classification](../README.md#rent-metadata-migration);
this shared helper only censors lower-quartile rent at 3500. Median
house value still receives its existing top-code flag at 2,000,000 without
censoring the estimate. Other variables and derived-rent eligibility rules are
unchanged.

## Outputs and expected impact

On an analyst rerun, the following existing outputs may change. No canonical
output has been regenerated as part of this implementation.

| Output under `../../../data/` | Potentially affected variables |
|---|---|
| `acs_step2_16.feather` | `med_hhincE` and `med_hhincCV` for tracts with available source income and missing/top-coded source rent. |
| `acs_step2_24.feather` | Household-weighted `med_hhincE` and its `med_hhincCV` wherever restored income contributions affect a tract estimate or its missingness. |
| `acs_full.feather` | `med_hhincE_16`, `med_hhincE_24`, `med_hhincCV_16`, `med_hhincCV_24`, `med_hhincPOST`, `moe_med_hhincPOST`, and `med_hhincPOSTCV`. The 2016 estimate is carried in inflation-adjusted dollars. |

The change-ratio uncertainty measures above depend on income estimates through
their existing formulas. Listing that dependency does not propose changing
MOE aggregation. Removing only the income assignment leaves source income
MOEs, their existing aggregation, rent measures, other columns, keys, and row
counts unchanged. Downstream analyses using income levels, growth, CV filters,
or complete-case selection may inherit the change. The assembly comparison below
measures Southern California income/CV differences; downstream sample and panel
effects have not been measured.

## Parity checks for the approved correction

`compare_socal_parity()` previously labeled tracts unaffected solely by geography
and failed if any of their output cells changed. Legitimate income restorations
and weighted-income changes therefore failed even when all other measures
matched. The numerical tolerance was not the cause.

The optional `expected_income` table is uniquely keyed by `tr2010_id` and holds
`legacy_med_hhincE`, `corrected_med_hhincE`, `legacy_med_hhincCV`, and
`corrected_med_hhincCV`. The notebook builds it before censoring:

- **2016:** corrected income is the source estimate; legacy income excludes
  estimates whose source rent is missing or at least 3500.
- **2024:** both estimates use the existing household allocation weights and
  `weightedMean(..., w = hhE * wt_hh, na.rm = TRUE)`. Only the legacy estimate
  excludes income contributions with missing/top-coded source rent.
- **Both vintages:** expected CVs use the reference `med_hhincM` and the existing
  `(med_hhincM / 1.645) / income` formula. The reference-MOE join is many-to-one
  and must preserve the destination tract keys. The candidate MOE remains an
  ordinary parity column, so changing it cannot authorize an income/CV exception.

A changed income or CV cell qualifies only when **both** its reference and
candidate match the legacy and corrected expectations. Comparisons use the
existing missing-value handling (including `NA`/`NaN`) and unchanged tolerance
`1e-10 * max(1, abs(prior), abs(candidate))`. Income columns are never skipped.
With `expected_income = NULL`, all geographically unaffected changes still fail.

The complete `differences` table retains every changed cell and classifies it as
`verified_income_correction`, `boundary_review`, or `unexpected`;
`difference_summary` counts cells by allocation, classification, and variable.
Verified corrections remain marked changed in the tract audit. They do not
alter geographic boundary IDs. The existing boundary-review behavior is
preserved, while unexplained changes and added/removed keys in geographically
unaffected tracts still fail. Key checks remain strict. With the later Step 2
inventory change, parity now compares every **shared** column, retaining strict
order, type, and value checks, plus these fixed optional schema migrations:

- `schema_migration = "2016"` permits additions `vac_rentedE`, `vac_rentedM`,
  and `rhu_inventoryE`, and removal of estimate/MOE pairs for `rentmv1yr`,
  `rentmv5yr`, `rentyrblt`, `rentyrblt_14_16`, `rentyrblt_10_13`,
  `rentyrblt_00_09`, and `rentyrblt_90_99`.
- `schema_migration = "2024"` permits only the `rhu_inventoryE` addition.

Actual additions/removals appear in `schema_changes`; unlisted changes fail.
`schema_migration = NULL` remains strict. These options do not relax the income
expectations or geographic classifications. Inventory is independently checked
against its three source components before saving and after reloading, including
when absent from a reference. Save/reload schema comparisons remain strict.

References load from the configured `../../../data/parity_reference` before
saving candidates to `../../../data/`. Preserve those snapshots. Missing
references explicitly remain **PARITY NOT CHECKED**; no expectation or pass is
fabricated. Income expectations and parity diagnostics never enter production
output schemas.

## Targeted validation

Run the focused [regression script](../tests/test_income_censoring.R) from the
repository root:

```sh
Rscript tests/test_income_censoring.R
```

It exercises the actual censoring, aggregation, and CV helpers using synthetic
inputs, with a frozen copy of the old censoring helper for regression comparisons.
The script reads no data files and writes no outputs; it reads the notebook's
two expectation chunks to test their actual code with synthetic inputs.
Coverage includes:

- Fourteen source-value cases spanning missing, zero, below-boundary, at-boundary,
  and above-boundary rent; independent lower-quartile rent censoring; and
  available, missing, zero, and large income. Large-value cases are synthetic
  probes, not empirical ACS ranges or new censoring thresholds.
- Exact preservation of source income, including the numeric type of an
  all-missing income column.
- Four synthetic tract groups with mixed rent availability, entirely
  missing/censored rent, entirely missing source income, and unaffected income.
  Nonuniform household allocation weights are included.
- Exact agreement of every other helper-output column with the old helper,
  including house values, flags, MOEs, keys, and row order. After aggregation
  and CV calculation, every column except `med_hhincE` and `med_hhincCV` must
  still agree, including types and row counts.
- Strict parity for identical or reordered inputs without an exception; verified
  restorations and weighted income/CV changes that remain visible in diagnostics.
- Rejection of incorrect candidate or reference income/CVs, unrelated rent,
  count, flag, label, and MOE changes, altered schemas or membership, and missing
  or duplicate output/expectation keys. Absent or malformed expectation columns
  cannot authorize changes.
- Tolerance on both sides of an exception, missing source income, `NA`/`NaN`,
  restored zero income with infinite CV, and zero income/MOE with missing CV.
- Unchanged boundary cell/membership review and explicit unchecked results when
  references are missing.

**Validation performed:** The income-retention assertion failed against the old
helper and all checks passed after the correction using R 4.5.1, dplyr 1.1.4,
matrixStats 1.5.0, and stringr 1.5.2. The mixed-rent tract's synthetic income
changes from 60,000 to 120,000. The tract with entirely missing/censored rent
changes from missing income to 130,000. The all-source-income-missing tract
remains missing and the unaffected tract retains 105,000. These are validation
fixtures, not estimates of empirical impact.

R syntax checks passed for both helpers, the extended test script, and notebook
code extracted with `knitr::purl()`. The production income correction remains
limited to removing the income assignment; the added notebook calculations and
parity helper changes are diagnostics. The merge helper is unchanged. No ACS API
request was made and no production output was written.

## Cached-input assembly validation (2026-09-11)

Executed the notebook's assembly and validation code using the existing step-1
Feathers and crosswalk, with references from `../../../data/parity_reference`.
The two save chunks were skipped and reload validation used the in-memory
candidates. This verifies the calculations and assertions, not a Feather
write/read round trip. Input and reference file hashes were unchanged.

Both vintages have 5,513 candidate tracts with exactly the reference key sets and
schemas. All 14 configured counties are present. The complete Southern
California comparison covers 3,925 tracts in each vintage, with no membership
changes or unexplained cell differences:

| Vintage / geographic group | Changed income cells | Changed CV cells | Result |
|---|---:|---:|---|
| 2016 / unaffected | 46 | 46 | All are verified income restorations and CVs. |
| 2024 / unaffected | 1,596 | 1,589 | All are verified: 240 income restorations and 1,356 numeric income changes. |
| 2024 / boundary | 2 | 2 | All four changed cells also match the income expectations. |

The full difference tables contain 92 changed cells for 2016 and 3,189 for 2024.
Seven 2024 tracts have changed income but unchanged missing CVs because their
reference and candidate income MOEs are missing. The four existing 2024 boundary
tracts retain their geographic classification: two are unchanged and two have
only verified income/CV corrections. These snapshots produce no additional
`boundary_review` differences. All compared non-income columns, including income
MOEs, agree within the existing tolerance.

For example, tract `06037101110` changes from 86,147.8104196816 to
87,248.6225247525 in 2024 income, and its CV changes from 0.175761419944881 to
0.173543845694642; both sides match their independent expectations. The counts
above describe the current inputs and references, not hardcoded acceptance
thresholds. Production saving and downstream panel/sample review remain separate
analyst-run steps.

## Analyst-run acceptance checks

Compare candidate results with a preserved pre-correction baseline using
identical step-1 inputs, destination counties, crosswalk weights, and all other
transformations. Keep candidate outputs separate from canonical outputs until
accepted.

1. For 2016, count available incomes lost under the old helper separately for
   originally missing rent and rent `>= 3500`, by county. Verify those source
   incomes are now retained, original missing income stays missing, and all
   other income values agree.
2. For 2024, report affected source block groups and allocation rows separately,
   along with their allocated household weights. Compare income missingness and
   numeric tract estimates, including tracts whose income remains available in
   both versions. Check a mixed-contribution tract and a tract with all income
   contributions excluded under the old rule. Changes must follow the same
   household-weighted mean using all available income contributions.
3. Compare the income/CV and income-change columns listed above, including
   missing-to-available transitions and numeric differences by county. Verify
   that 2016 inflation adjustment and the downstream formulas are unchanged.
4. Confirm identical output keys, row counts, shared columns/types, geography,
   weights, and all shared non-income-related values, including rent measures and existing
   income MOEs. Review any downstream sample changes due to income availability
   or CV thresholds before accepting revised analytical results. Inspect
   `schema_changes` for only the listed migration and independently validate
   inventory completeness and complete-target reconciliation in Step 2 §5.6.
5. Inspect every `socal_parity_16$differences` and `socal_parity_24$differences`
   row. Every geographically unaffected difference must be a
   `verified_income_correction`; investigate anything else before accepting
   outputs. Review boundary differences against `socal_boundary_contributions`
   without reclassifying income-affected tracts as boundary cases.
