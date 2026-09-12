# Audit: 2024 rental housing unit aggregation

Reviewed 2026-09-11 at commit `1e07d96`. Scope: renter **count estimates** in
[02_assemble.Rmd](../02_assemble.Rmd#L151), from available block-group counts and
crosswalk fractions through the saved 2010-tract counts. This assessment does
not validate the separate rent statistics, share measures, or MOEs/CVs.

**Conclusion: correct with caveats.** Allocating and summing counts is sound
for estimating renter-occupied units on consistent 2010 tract geography,
and the implementation matches it. Targeted checks found no duplication,
unexplained count loss, or inflation. Recomputed renter counts matched all
5,513 saved tracts exactly. The qualifications are geographic interpolation
assumptions and a latent missing-count issue: `na.rm = TRUE` can produce partial
totals or turn entirely missing contributions into zero. No missing source
counts were found among the retained sources in the audited cache.

**Intended quantity and source definitions.** `rhuE` estimates the number of
**renter-occupied housing units during the 2020–2024 ACS five-year period**
within each selected 2010 tract. It uses `B25003_003E`; the B25003 table universe
is occupied housing units. Renter occupancy includes units occupied without
payment of rent and excludes vacant units available for rent. Thus this is an
occupied-rental count, rather than the entire rental inventory or a year-end
2024 census. The variable mapping and period appear in
[01_acs.Rmd](../01_acs.Rmd#22-specify-variables-to-extract) and its
[2024 extraction](../01_acs.Rmd#41-download-2024-acs-block-group-estimates).
([Census B25003](https://api.census.gov/data/2024/acs/acs5/groups/B25003.html),
[Census tenure definitions](https://www2.census.gov/programs-surveys/acs/tech_docs/subject_definitions/2024_ACSSubjectDefinitions.pdf).)

Related rental counts use the same allocation arithmetic: `rhucashE` is
`B25063_002E`; `grentcat1E`–`grentcat24E` are `B25063_003E`–`B25063_026E` cash-rent
bins. `rhu_lrE` sums bins 1–18 (gross rent below $1,250), and `rhu_lr2E` sums
bins 1–20 (below $2,000). These are cash-renter subsets, not all renters.
([Source derivation](../01_acs.Rmd#42-derive-low-rent-housing-unit-counts),
[Census B25063](https://api.census.gov/data/2024/acs/acs5/groups/B25063.html).)

**Implemented calculation.** For source block group $b$, target tract $t$,
source renter estimate $N_b$, and $a_{bt}=\texttt{wt\_renthu}$, the calculation
with complete counts is:

$$
q_{bt}=a_{bt}N_b,\qquad
\widehat N_t=\sum_{b:(b,t)\text{ retained}}q_{bt}.
$$

NHGIS defines `wt_renthu` as the expected fraction of the **source block
group's renter-occupied units** in the destination. This is the 2020-block-group
to 2010-tract crosswalk, applied to 2020–2024 ACS counts. Fractions refer to each
source's total across destinations. The supplied fraction is applied directly
to the ACS count; there is no further division by a tract total. The crosswalk
import only renames/selects columns.
([NHGIS weight definitions and method](https://www.nhgis.org/geographic-crosswalks),
[crosswalk import](../01_acs.Rmd#61-crosswalk-2024-block-groups-to-2010-tracts).)

[calc_agg_vars()](../R/assemble_helpers.R#L278) groups by `tr2010_id` and computes
`rhuE_agg = sum(rhuE * wt_renthu, na.rm = TRUE)`, then renames it `rhuE`.
The cash, low-rent, and bin counts use the same formula with their own source
counts. `_agg` names prevent summary values from replacing source vectors
during aggregation. `rel_wt_rhu`, created separately for uncertainty
calculations, does not enter these point counts. Fractional estimates are
retained without rounding.

**Split geography, selection, and keys.** Each source–target allocation receives
the fraction once. For example, cached source `060014204012` has 259 renter
units and splits between `06001420400` and `06001422000` with fractions
0.3956834532 and 0.6043165468. Its contributions are 102.4820143788 and
156.5179856212, summing to 259. Across retained sources, 2,195 have multiple
target links; 743 have positive renter fractions to multiple targets. Zero
fractions explain why these counts differ.

Selection uses the destination tract's state/county, preserving all matched
sources allocating there, including sources outside the 14 target counties.
Original fractions are not renormalized after destination filtering.
[The notebook](../02_assemble.Rmd#L197) asserts unique source IDs, unique
`(bg2020_id, tr2010_id)` pairs, no join multiplication, and exact fraction
preservation. Later tract joins assert unique, fully matched tract keys.
The cached IDs are character GEOIDs with the expected 12-/11-digit lengths.
There were 19,807 selected links; the sole unmatched link,
`320030057033` → `06071010300`, had all four weights exactly zero. The authorized
exception removes it, leaving 19,806 unique matched pairs from 16,985 sources
and preserving every destination tract. No target-county ACS source was absent
from the crosswalk.

**Missingness and zeros.** Missing/nonfinite/out-of-range crosswalk weights and
unmatched nonzero links stop the notebook before aggregation. In contrast,
missing source counts are not rejected: `sum(..., na.rm = TRUE)` omits their
products, including `NA * 0`. A tract with observed and missing positive-weight
contributions receives only the observed subtotal; one with all contributions
missing receives zero. This can understate renter totals and makes missingness
indistinguishable from a real zero. The low-rent source helper also uses
`rowSums(..., na.rm = TRUE)`, so missing bins can already become partial/zero
source counts. ([Count sums](../R/assemble_helpers.R#L311),
[low-rent helper](../R/helpers.R#L23).)

The retained cache contained **no missing, infinite, or negative** renter,
cash-renter, no-cash-renter, low-rent, or rent-bin counts. Source cash plus
no-cash counts equaled `rhuE`; cash bins and both low-rent bin sums reconciled
exactly. There were 470 source block groups with zero renter units and 52
zero-renter destination tracts. Known zeros correctly contribute zero;
undefined relative weights for a zero-total tract do not change its point
count. Missing or censored **rent** does not remove renter **counts**:
[censor_tc_vars()](../R/assemble_helpers.R#L265) leaves those counts unchanged.

**Conservation and reconciliation.** For complete counts,

$$
\sum_{t\in T}\widehat N_t
=\sum_bN_b\left(\sum_{t\in T}a_{bt}\right).
$$

Full-source conservation is expected when all destinations are retained, up to
crosswalk rounding. The narrow read-only check produced:

| Check | Result |
|---|---:|
| Renter total in the 16,985 matched sources | 4,137,361 |
| Allocated to all destinations for those sources | 4,137,360.999999939 |
| Allocated to selected destinations | 4,136,040.062707798 |
| Allocation to excluded destinations | 1,320.937292142 |
| Maximum source renter-fraction sum error | approximately `1e-10` |
| Maximum per-source count conservation error | `7.54e-8` units |
| Absolute difference between tract-first and source-first retained sums | `5.59e-9` units |
| Maximum saved-versus-recomputed tract difference | 0 |

Eleven matched sources have renter fractions excluded by destination selection;
the excluded allocation explains the total difference. Rounding errors are
well within the notebook's `1e-6` source-fraction tolerance. All 5,513 saved
values matched for each of `rhuE`, `rhucashE`, `rhu_lrE`, and `rhu_lr2E`.
There is no unexplained systematic loss or inflation in these cached counts.
The existing [tract reconciliation](../02_assemble.Rmd#L454) repeats the same
`na.rm = TRUE` formula; it alone cannot detect missing-count omission.

**Panel comparability.** The earlier measure is the same `B25003_003E` universe
from the 2012–2016 ACS, observed directly at 2010-tract level and retained
through stage 2. The two `rhuE` counts are conceptually comparable. The 2024
estimate additionally assumes that the crosswalk's renter distribution
represents the 2020–2024 source counts within split block groups; geographic
allocation error remains even when conservation is exact. Applying renter
fractions to cash/low-rent subsets further assumes their distribution follows
all renters within each source. Earlier low-rent thresholds are below $1,000
and $1,500, versus $1,250 and $2,000 in 2024, so their intended real-threshold
comparability is approximate. ([Earlier extraction](../01_acs.Rmd#31-download-2016-acs-tract-estimates),
[shared variable mapping](../01_acs.Rmd#22-specify-variables-to-extract),
[earlier preparation](../02_assemble.Rmd#L745),
[threshold definitions](../schemas/acs_step1_2016_tract.md),
[2016 B25003](https://api.census.gov/data/2016/acs/acs5/groups/B25003.html).)

**Recommended next step.** Retain the renter-count formula: it is correct for
the audited inputs, and no count-calculation correction is required. Optional
QA improvements are to assert finite, nonnegative source counts wherever
`wt_renthu > 0`, check bin completeness before low-rent summation, and retain
the source-first reconciliation above. If missing counts occur, the smallest
protective change is to stop and report the affected sources/tracts before
aggregation; accepting partial totals would require an explicit analyst rule.
These suggestions were not implemented.

Validation used schema/code inspection, Census/NHGIS definitions, and narrow
column reads of `acs_step1_24.feather`, `xwalk_bg24_tr10.feather`, and
`acs_step2_24.feather`. Small R calculations confirmed the missing/zero behavior.
The installed R 4.5.1, dplyr 1.1.4, and arrow 21.0.0.1 were used without changing
dependencies; no local `renv.lock` or activation file was present. No full
notebook ran, no canonical output was regenerated, and file hashes confirmed
the three Feathers were unchanged. This note is the only repository write.

**Subsequent stage-1 migration (2026-09-12):** The audit's original
`acs_step1_24.feather` is retained as historical data. Its current counterpart,
`acs_step1_2024_block_group.feather`, requires regeneration for the revised
variable contract. Stage 2 now also consumes `acs_step1_2024_tract.feather` in
its separate native-2020 tract path. This note's empirical findings
refer to the original cached inputs. See the [migration and parity compatibility](../README.md#stage-1-input-migration).

**Subsequent Step 2 inventory implementation (2026-09-12):** Both original products
add `rhu_inventoryE` from renter-occupied, vacant-for-rent, and rented-not-occupied
estimates. All block-group components use retained `wt_renthu` fractions; any missing
estimate on a positive-weight link makes inventory `NA`. Zero-weight links
do not affect completeness, and zero-contributor targets have zero inventory.
The occupied `rhuE` formula audited above and the separate `wt_hu` vacancy-rate
inputs remain unchanged. Source validation, completeness diagnostics, and
complete-target reconciliation are now implemented for inventory; the original
empirical findings and broader low-rent/bin suggestions above remain historical.
The narrow parity migration reports only the agreed schema additions/removals
and preserves shared-column checks. Synthetic tests passed; full execution,
canonical output regeneration, and empirical inventory review remain analyst-run.

The subsequently added 2024 tract-source inventory uses direct tract sums with
the same missingness rule. See the [current output names and separate validation](../README.md#stage-2-output-naming-and-references).
