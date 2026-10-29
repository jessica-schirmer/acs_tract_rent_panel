# Validation of `interp_rent` as the 2024 tract rent measure

Reviewed 2026-09-11 at commit `b4ab25e8d95a11fc0811ae33d8df8539cad07ea1`.
The [block-group rent weighting audit](2024_block_group_rent_weighting_audit.md)
is authoritative on the estimator choice; this note evaluates the requested
empirical conditions and consequences of that choice.

## 1. Conclusion

**Proceed with `interp_rent` as the canonical approximate 2024 tract median,
with explicit resolution and high-rent coverage caveats.** No bin-mapping,
source-completeness, allocation-reconciliation, or saved-value implementation
problem was found in the data examined.

- All **407,640 bin counts from 16,985 contributing source block groups** are
  present, finite, nonnegative, and integer-valued. All source distributions
  sum exactly to their cash-renter totals; all **5,513 target tracts** reconcile
  within floating-point precision.
- `interp_rent` is observed for **4,939 tracts (89.59%)**. The **574 missing
  values (10.41%)** comprise **521 medians in the $3,500+ category** and **53
  tracts with zero cash renters**. This high-rent exclusion is consequential.
- **88.84% of observed estimates** interpolate within a bin with implemented
  width **$499**. Bin width measures resolution, not a confidence interval or
  formal error bound.
- Against the existing `rentE` index ((rentE_24 in the panel): a renter-unit-weighted average of available, uncensored
    block-group median gross rents), the common-sample median level difference
  is small, but disagreement has substantial tails. On **4,822 comparable
  panel tracts**, the downstream log-change correlation is **0.8397**, and
  **332 tracts (6.89%)** change the estimated direction of real rent growth.

These checks support the implementation as an approximate median; they do not
establish household-level accuracy or an uncertainty estimate for it.

## 2. Data, scope, and reproduction checks

The analysis used the existing files under `../../../data/`, selected only
rent-related columns, and ran targeted calculations in memory. It did not run
or knit an entire notebook, download new ACS observations, or regenerate data.
The only repository write is this note.

The [configured sample](../02a_build_measures_from_block_groups.Rmd#13-set-data-directory-and-target-counties) is the five Southern California
and nine Bay Area counties, selected by **destination 2010 tract**. Of 29,740
statewide crosswalk rows, 19,807 point to the target tracts. Following the
notebook, one unmatched source link with all four allocation weights equal to
zero is excluded, leaving **19,806 links** and **16,985 distinct source block
groups** from the statewide cache of 25,607. All retained links match a source;
the join preserves the link count and every target tract. Original allocation
weights are used without renormalization. Of these links, 17,782 have positive
renter weights and 2,024 have zero renter weights.

The saved 2024 and 2016 tract tables each have 5,513 unique, nonmissing keys.
Their union in `acs_full.feather` has 5,514: `06037930401` is 2024-only and
`06037137000` is 2016-only. All target-tract shares below use **5,513**, not the
panel union. Comparisons use their explicitly stated common samples and give
each tract equal weight; quantiles use R's default type 7.

**Reproduction checks:** Reallocated each of the 24 bin estimates, `rhucashE`,
and `rhuE` with `sum(source_count * wt_renthu, na.rm = TRUE)`. Recomputed the
existing censored-source weighted mean using `matrixStats::weightedMean`,
called the unchanged [calc_interp_rent()](../R/assemble_helpers.R#L394), and
reconstructed its selected-bin diagnostics. Checked saved coverage shares and
the panel's two rent levels, inflation-adjusted baseline, and two rent ratios.
All **36 column comparisons passed**, including missingness patterns, with
tolerance `1e-10 * max(1, abs(saved), abs(recomputed))`. Bin counts, cash totals,
both rent estimates, and panel rent measures reproduced exactly; the only
nonzero comparison difference was at most `3.33e-16` in the decomposition of
the missing-source-median share.

## 3. Bin-definition validation

The [2024 Census B25063 variable definitions](https://api.census.gov/data/2024/acs/acs5/groups/B25063.html)
confirm `rhucashE = B25063_002E`, the cash-renter total. The 24 cash-rent bins
are `_003E` through `_026E`; `_027E` is no-cash rent and is excluded.
[Stage 1's mapping](../01_import_acs.Rmd#22-specify-variables-to-extract) and the helper's range table match the
published category order. The helper converts category suffixes to integers
and sorts them numerically, so categories 10–24 follow category 9 correctly.
The saved aggregation supplies exactly the 24 estimate columns, without MOEs
or duplicate source aliases.

In the table, `k` identifies **`grentcat{k}E`**. Closed-category ranges are
also the exact `(lower, upper)` endpoints used by the implementation. Median
counts require positive cash-renter totals; zero-cash tracts have no median bin.

| k | Census estimate | Published monthly rent range / implemented endpoints ($) | Median tracts | % of all 5,513 |
|---:|---|---|---:|---:|
| 1 | `B25063_003E` | <100; stored `(0, 99)`, interpolation suppressed | 0 | 0.00 |
| 2 | `B25063_004E` | 100–149 | 1 | 0.02 |
| 3 | `B25063_005E` | 150–199 | 0 | 0.00 |
| 4 | `B25063_006E` | 200–249 | 0 | 0.00 |
| 5 | `B25063_007E` | 250–299 | 1 | 0.02 |
| 6 | `B25063_008E` | 300–349 | 2 | 0.04 |
| 7 | `B25063_009E` | 350–399 | 1 | 0.02 |
| 8 | `B25063_010E` | 400–449 | 0 | 0.00 |
| 9 | `B25063_011E` | 450–499 | 2 | 0.04 |
| 10 | `B25063_012E` | 500–549 | 2 | 0.04 |
| 11 | `B25063_013E` | 550–599 | 3 | 0.05 |
| 12 | `B25063_014E` | 600–649 | 4 | 0.07 |
| 13 | `B25063_015E` | 650–699 | 2 | 0.04 |
| 14 | `B25063_016E` | 700–749 | 2 | 0.04 |
| 15 | `B25063_017E` | 750–799 | 7 | 0.13 |
| 16 | `B25063_018E` | 800–899 | 18 | 0.33 |
| 17 | `B25063_019E` | 900–999 | 21 | 0.38 |
| 18 | `B25063_020E` | 1,000–1,249 | 131 | 2.38 |
| 19 | `B25063_021E` | 1,250–1,499 | 354 | 6.42 |
| 20 | `B25063_022E` | 1,500–1,999 | 1,551 | 28.13 |
| 21 | `B25063_023E` | 2,000–2,499 | 1,506 | 27.32 |
| 22 | `B25063_024E` | 2,500–2,999 | 849 | 15.40 |
| 23 | `B25063_025E` | 3,000–3,499 | 482 | 8.74 |
| 24 | `B25063_026E` | ≥3,500; stored `(3500, NA)`, interpolation suppressed | 521 | 9.45 |

**No source-variable/range or ordering mismatch was found.** Two endpoint
conventions should remain explicit. Census labels the first category “less
than $100”; the helper's zero lower endpoint is an implementation convention,
not a separately published lower endpoint, and that category is never
interpolated. Closed bins use printed integer endpoints, giving widths 49,
99, 249, or 499 rather than 50, 100, 250, or 500. Using the next category's
lower endpoint as the upper boundary would change a finite-bin estimate by
at most $1 at the same interpolation fraction; this is a numerical convention,
not a category-mapping error. No alternate endpoint estimator was produced.

## 4. Source completeness and cash-total reconciliation

Across the **16,985 retained source groups**, each of the 24 bin columns has
**0 missing, 0 negative, 0 nonfinite, and 0 noninteger estimates**: 0 of
407,640 cells invalid or missing. There are **0 incomplete/invalid source
distributions (0%)**. All 16,985 cash totals are also present, finite,
nonnegative, integer-valued, and equal the sum of their bins. The 583 sources
with zero cash renters have valid all-zero distributions.

Consequently **0 target tracts (0%)** receive an incomplete or invalid
positive-weight source distribution. There are no missing or invalid retained
renter allocation weights. The current `na.rm = TRUE` causes **no silent
missing-as-zero loss in these inputs**. It remains a future-input risk: missing
bins and cash totals are discarded independently, and reconciliation alone
could miss jointly absent components. Completeness needs its own check on
subsequent refreshes.

Define `D = sum(allocated bins) - allocated rhucashE`, and relative discrepancy
as `abs(D) / rhucashE` for positive cash totals.

| Discrepancy | N | Mean | Median | P90 | P95 | P99 | Maximum |
|---|---:|---:|---:|---:|---:|---:|---:|
| Absolute allocated-unit difference, `abs(D)` | 5,513 | 6.40e-15 | 0 | 0 | 2.84e-14 | 2.27e-13 | 9.09e-13 |
| Absolute relative difference, fraction | 5,460 | 9.29e-18 | 0 | 0 | 1.21e-16 | 1.99e-16 | 3.93e-16 |

**5,197 tracts (94.27%) reconcile exactly**. The remaining **316 (5.73%)**
differ only at floating-point scale; **5,513 (100%)** are within `1e-8`
allocated unit. All 5,460 positive-total tracts are also within `1e-10`
relative difference. The 53 zero-total tracts reconcile exactly; their relative
discrepancy is undefined, not assigned zero.

There is **no material discrepancy**. The tiny allocated differences are
consistent with floating-point summation of fractional allocations, given
exact source reconciliation. Replacing the denominator by the bin total for
this numerical diagnostic changes **0 median-bin assignments**, and changes
finite interpolated rents by at most **$1.13e-12**. All observed estimates have
finite interpolation fractions in `[0, 1]` and lie inside the selected interval.

## 5. Missingness and interpolation resolution

| `interp_rent` result/reason | Tracts | % of all 5,513 | % of 574 missing |
|---|---:|---:|---:|
| Observed, median in a finite interior bin | 4,939 | 89.59 | — |
| Median in bottom category, < $100 | 0 | 0.00 | 0.00 |
| Median in top category, ≥ $3,500 | 521 | 9.45 | 90.77 |
| Zero cash renters | 53 | 0.96 | 9.23 |
| Incomplete/invalid component data | 0 | 0.00 | 0.00 |
| Other implementation/data reason | 0 | 0.00 | 0.00 |
| **All missing** | **574** | **10.41** | **100.00** |

Zero cash renters take precedence over the helper's incidental first-bin
selection when its threshold is zero. There are no positive-total tracts
without a median-bin assignment. Missing source **medians** are distinct from
missing source **bins**: 3,119 sources (18.36%) have missing `rentE`, and another
1,701 (10.01%) have `rentE >= 3500` before censoring; their bin distributions
remain complete and contribute to `interp_rent`.

High-end missingness is geographically uneven: top-bin medians account for
**53/158 San Mateo tracts (33.54%)**, **16/56 Marin tracts (28.57%)**, and
**98/372 Santa Clara tracts (26.34%)**, compared with **139/2,346 Los Angeles
tracts (5.92%)**. The finite-estimate sample therefore excludes a substantial
part of some high-rent counties.

The full median-bin distribution is in §3. Among the **4,939 observed rents**:

| Implemented bin width ($) | Tracts | % of observed rents |
|---:|---:|---:|
| 49 | 27 | 0.55 |
| 99 | 39 | 0.79 |
| 249 | 485 | 9.82 |
| 499 | 4,388 | 88.84 |

Width has mean **$468.83**, minimum **$49**, and **median, P75, P90, and maximum
all $499**. The four $1,500–$3,499 categories dominate and materially limit
resolution. Dollar-level or decimal-valued interpolation output should not be
interpreted as dollar-level measurement precision. The 521 top-category medians
have no finite interpolation width and are excluded from these width summaries;
there are no bottom-category medians. Width quantifies bin resolution only;
it does not measure sampling error, allocation error, or within-bin uncertainty.

## 6. Existing-measure comparisons

### 6.1 Definitions and comparison samples

There is **one existing comparable alternative tract gross-rent measure**:
`rentE` in stage 2, carried as `rentE_24` in the panel. It is the weighted
average of available source block-group B25064 medians after values `>= 3500`
are censored, with weights `rhuE * wt_renthu`. These are all renter units,
including no-cash units; unavailable medians and their weights are excluded.
`interp_rent` instead uses all allocated cash-rent bin counts and their cash
total. The existing `lqcrentE` measures a lower **contract-rent quartile**, not
the same gross-rent median target, so it is not treated as a second alternative.
No new rent estimator was constructed.

| Availability | Tracts | % of all 5,513 |
|---|---:|---:|
| Observed `interp_rent` | 4,939 | 89.59 |
| Observed alternative `rentE` | 5,052 | 91.64 |
| Both 2024 levels observed | 4,839 | 87.77 |
| Both levels and a positive observed common 2016 baseline | 4,822 | 87.47 |

There are **100 tracts** with an interpolated rent but no alternative index,
and **213 tracts** with an alternative index but a top-bin interpolated median.
The latter indexes range from **$495 to $3,481** (median **$2,920**); they do not
resolve the reconstructed distribution's $3,500+ median. These groups are
excluded from pairwise numerical comparisons, so the common-sample statistics
do not describe the full consequences of changing coverage.

### 6.2 2024 rent levels

All statistics here use the **same 4,839 tracts**. Dollar difference is
`rentE - interp_rent`; percent difference is
`100 * (rentE - interp_rent) / interp_rent`. Positive differences mean the
alternative is higher. Rents are monthly amounts in 2024 dollars.

| Measure | Mean | SD | P05 | P25 | Median | P75 | P95 |
|---|---:|---:|---:|---:|---:|---:|---:|
| `interp_rent`, $ | 2,166.26 | 565.40 | 1,329.80 | 1,755.27 | 2,118.17 | 2,548.99 | 3,196.51 |
| Alternative `rentE`, $ | 2,139.14 | 528.40 | 1,325.56 | 1,751.21 | 2,106.76 | 2,511.39 | 3,066.04 |
| Alternative minus interpolated, $ | -27.11 | 208.43 | -319.85 | -57.22 | -1.68 | 33.98 | 193.27 |
| Difference relative to `interp_rent`, % | -0.40 | 10.69 | -12.86 | -2.61 | -0.08 | 1.67 | 9.84 |

Pearson correlation is **0.9296** and Spearman rank correlation **0.9436**.
The alternative is higher in **2,325 tracts (48.05%)** and lower in **2,514
(51.95%)**; none tie within $1e-8. Absolute differences have **median $44.40,
mean $103.15, P90 $252.06, and P95 $401.16**. **493 tracts (10.19%)** differ
by more than $250, and **587 (12.13%)** differ by more than 10% of
`interp_rent`. Signed differences range from **-$2,561.80 to +$2,156.91**.

Coverage groups use the existing `pct_tc_rent` and the verified raw-missing
component `pct_miss_rent - pct_tc_rent`, reconstructed from source data.
“Present” means a positive share of allocated renter units, with a numerical
tolerance of `1e-12`. These indicators describe source medians, not bin
completeness. All four groups below partition the common level sample.

| Source-median coverage | Tracts | Mean difference ($) | Mean absolute difference ($) | % alternative lower |
|---|---:|---:|---:|---:|
| Complete coverage | 2,905 | 7.50 | 51.29 | 43.58 |
| Missing medians only | 1,184 | 18.77 | 135.26 | 48.99 |
| Censored medians only | 473 | -232.24 | 246.78 | 90.27 |
| Both missing and censored medians | 277 | -236.01 | 264.52 | 87.00 |

Disagreement is also larger at the high end. Among **462 tracts with
`interp_rent` of $3,000–$3,499**, the alternative is lower in **85.71%**;
mean difference is **-$235.38** and mean absolute difference **$247.18**.
For **1,536 tracts at $1,500–$1,999**, those differences are **+$20.90** and
**$66.68**. These are descriptive associations, consistent with the prior
audit's coverage mechanism, not a causal attribution of all disagreement.

Two inspected extremes make the coverage issue concrete. In `06075030500`,
`interp_rent = $2,876.80`, while `rentE = $315`: the only retained source
median is $315; the other two are missing or censored, representing **59.65%**
of allocated renter units. Conversely, `06075023200` has `interp_rent = $728.09`
and `rentE = $2,885`; **79.22%** of allocated renter units have missing source
medians, leaving one observed source median for the index. All source bins
for both tracts are complete and reconcile.

### 6.3 2016–2024 rent change, including the downstream log outcome

The [panel definition](../R/merge_helpers.R#L150) uses the existing tract
B25064 `rentE` baseline, already censored in stage 2 and multiplied by **1.307**
to express it in 2024 dollars. With that identical baseline `B` for each tract:

- `interp_rentPOST = interp_rent / B` and `rentPOST = rentE_24 / B`, for `B > 0`.
- The [downstream rent model](../../../analysis/tract_rent_acs/01_fe_rent.Rmd#L544)
  constructs both `log_interp_rentPOST` and `log_rentPOST` using natural logs,
  and [uses `log_rentPOST` as its outcome](../../../analysis/tract_rent_acs/01_fe_rent.Rmd#L845).
  Both existing definitions are therefore reported, with emphasis on logs.

Of the 4,839 level-pair tracts, 17 lack a usable baseline: 16 have missing or
censored baseline rent and one is absent from the 2016 table. The **4,822
remaining tracts** define every comparison below. Across all target tracts,
4,904 interpolated change ratios and 5,031 alternative change ratios are
observed, before restricting to this common sample. No new absolute-change or
growth-classification definition is introduced.

| Change measure | Mean | SD | P05 | P25 | Median | P75 | P95 |
|---|---:|---:|---:|---:|---:|---:|---:|
| `interp_rentPOST` | 1.1639 | 0.1953 | 0.8688 | 1.0573 | 1.1586 | 1.2632 | 1.4643 |
| Alternative `rentPOST` | 1.1555 | 0.2033 | 0.8409 | 1.0458 | 1.1543 | 1.2609 | 1.4498 |
| Alternative minus interpolated ratio | -0.0084 | 0.1030 | -0.1487 | -0.0298 | -0.0010 | 0.0192 | 0.1092 |
| `log_interp_rentPOST` | 0.1375 | 0.1724 | -0.1406 | 0.0557 | 0.1472 | 0.2336 | 0.3814 |
| Alternative `log_rentPOST` | 0.1288 | 0.1806 | -0.1732 | 0.0447 | 0.1435 | 0.2318 | 0.3714 |
| Alternative minus interpolated log change | -0.0087 | 0.1002 | -0.1356 | -0.0264 | -0.0009 | 0.0166 | 0.0937 |

Ratio Pearson correlation is **0.8673**; log-change Pearson correlation is
**0.8397**. The mean absolute ratio difference is **0.0527**, equivalent to
**5.27 percentage points** of cumulative real growth. The mean absolute
log-change difference is **0.0479**, with median **0.0209** and P90 **0.1161**.
The log-change difference equals `log(rentE_24 / interp_rent)` because the
common baseline cancels; discrepancies in the 2024 estimators therefore carry
directly into the model outcome.

For direction, growth means a ratio above 1 (log change above 0), and decline
means below 1. Neither measure has an exact zero-change case in this sample.

| Direction using `interp_rent` | Direction using alternative | Tracts | % of 4,822 |
|---|---|---:|---:|
| Decline | Decline | 631 | 13.09 |
| Growth | Growth | 3,859 | 80.03 |
| Decline | Growth | 110 | 2.28 |
| Growth | Decline | 222 | 4.60 |

Thus **332 tracts (6.89%) reverse direction**. In 99 of these, both estimates
are more than 5% away from no change in opposite directions; reversals are
not exclusively infinitesimal movements around zero. This 5% check is a
descriptive sensitivity diagnostic, not a new classification rule.

Rankings also change: Spearman correlation is **0.8798** for both ratios and
logs. The absolute rank displacement has **median 169 places**, **P75 427**,
and **P90 938.9**, corresponding to **3.51, 8.86, and 19.48 percentile points**
on this sample. **1,074 tracts (22.27%)** move at least 10 percentile points;
**468 (9.71%)** move at least 20. Percentile displacement is
`100 * abs(rank_alternative - rank_interp) / (4822 - 1)`, with average ranks
for ties. These quantify sensitivity without assigning new growth classes.

The inspected cleaning and downstream rent-model code defines **baseline rent
quintiles**, not rent-growth classes. On a fixed sample, the common baseline
is unchanged, so those baseline classifications are unchanged; membership
could change if a subsequent analysis reselects its sample and recomputes
cutpoints. No downstream model or sample was rerun here.

The change disagreements track source-median coverage. Direction reversal is
**88/2,898 (3.04%)** with complete coverage, **107/1,177 (9.09%)** with missing
medians only, **85/471 (18.05%)** with censored medians only, and **52/276
(18.84%)** with both. The two groups involving censoring have mean alternative
minus interpolated log-change differences of approximately **-0.092** each.

## 7. Recommended next step

Proceed with the existing `interp_rent` / `interp_rentPOST` pair as the
canonical **approximate tract-median** measures, while documenting the
resolution and retaining explicit treatment of top-bin and zero-cash cases.
The 521 top-bin cases identify a $3,500+ category in the reconstructed
distribution; they do not supply point estimates. A downstream adoption should
report their exclusion or otherwise use an explicitly chosen treatment, and
should report resulting county/sample coverage. Substituting the surviving
`rentE` index for these cases would mix the two estimators.

Carry the existing alternative as a clearly labeled sensitivity measure.
The common-sample level and growth comparisons above justify examining how
future substantive results respond to estimator and sample choice. Preserve
the assumptions already established in the audit: allocation within source
block groups and linear interpolation inside the median bin. Do not use
`rentM`, `rentCV`, or the alternative index's propagated uncertainty as an
MOE/CV for `interp_rent`.

No correction is needed to the checked bin mappings or allocation arithmetic.
This task changes neither the canonical measure nor any implementation.

## Reproducibility record

Read the documented stage-1, crosswalk, stage-2, and panel schemas before the
audit. The targeted R session used R 4.5.1, arrow 21.0.0.1, dplyr 1.1.4,
tidyr 1.3.1, stringr 1.5.2, and matrixStats 1.5.0 from the installed environment;
no dependencies were installed or changed. The county and variable mappings
were read from the existing notebook chunks. The median category was the
first numerically ordered cumulative bin reaching `rhucashE / 2`; widths and
within-bin fractions were read/reconstructed from the unchanged helper. All
summaries, correlations, signed differences, coverage groups, and ranks use
the formulas and sample denominators stated above. The audit was deterministic.

**Subsequent stage-1 migration (2026-09-12):** The historical
`acs_step1_24.feather` in the table below has the current counterpart
`acs_step1_2024_block_group.feather`, with a revised variable contract. A new
`acs_step1_2024_tract.feather` is now consumed separately on native 2020 tracts
in Step 2; that path does not calculate interpolated rent. This audit used
the original block-group cache; filenames, hashes, and results below still
identify those original inputs, not regenerated outputs. See the
[migration instructions](../README.md#stage-1-input-migration).

Input MD5 hashes were checked before and after the calculations and were
unchanged. They identify the exact saved data behind this note:

| File under `../../../data/` | Rows | MD5 |
|---|---:|---|
| `acs_step1_24.feather` | 25,607 | `3d12cf728499b6dd7ce6f221d7858928` |
| `xwalk_bg24_tr10.feather` | 29,740 | `6aad3833d4cafd307651eb04800021c1` |
| `acs_step2_24.feather` | 5,513 | `ca0d768300134f3774362f893109d48e` |
| `acs_step2_16.feather` | 5,513 | `424da05278e6cc34ee5dc17526515834` |
| `acs_full.feather` | 5,514 | `59edfd047d1882d361521cbb8d145741` |

Stage-1/crosswalk files were last modified 2026-06-11; the three downstream
files were last modified 2026-09-11. File timestamps identify local snapshots,
not ACS publication dates. Published-bin validation used the linked 2024
Census metadata, accessed 2026-09-11.
