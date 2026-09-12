# Audit: 2024 block-group-to-tract rent weighting

Reviewed 2026-09-11 at commit `b4ab25e`. Scope: the rent calculations in
[02_assemble.Rmd](../02_assemble.Rmd#L299), starting with available ACS source
estimates and crosswalk allocations; earlier-vintage inspection was limited to
conceptual comparability.

**Finding:** Geographic allocation and the `rentE` calculation correctly implement
the documented renter-unit-weighted average of available block-group medians,
including split block groups. That average is defensible as a descriptive rent
index, but does not generally estimate the tract median or mean household rent.
The separate `interp_rent` follows a defensible approximate-median approach.
Rent MOE aggregation does not match the notebook's stated formula.

The apparent substantive target is **2020–2024 median monthly gross rent among
cash-paying renter-occupied units within each 2010 tract**. This inference follows
the source variable, `rent = B25064_001`, and its use against the earlier tract
median. B25064's universe excludes no-cash-rent units. However, §2.5 explicitly
chooses an average of source medians, while §2.6 calls it “weighted median rent.”
The intended research quantity therefore needs to distinguish a tract median
from the documented index. ([Source definitions](../schemas/acs_step1_2016_tract.md),
[Census B25064](https://data.census.gov/table/ACSDT5Y2024.B25064).)

For source block group $b$ and destination tract $t$, define

- $a_{bt}$: `wt_renthu`, the fraction of the source's renter units allocated to $t$;
- $N_b$: `rhuE`, all renter-occupied units, including no-cash-rent units;
- $C_b$: `rhucashE`, cash-paying renter units;
- $m_b$: uncensored `rentE`, the block-group median gross rent;
- $q_{bt}=a_{bt}N_b$, and $S_t=\{b:m_b\text{ is nonmissing and }m_b<3500\}$.

For finite nonnegative counts and positive available weight, the **documented
and implemented index formula** is

$$
\widehat R_t=
\frac{\sum_{b\in S_t}q_{bt}m_b}{\sum_{b\in S_t}q_{bt}}.
$$

[censor_tc_vars()](../R/assemble_helpers.R#L265) first sets `rentE >= 3500` to
`NA`; [calc_agg_vars()](../R/assemble_helpers.R#L278) then uses
`weightedMean(rentE, w = rhuE * wt_renthu, na.rm = TRUE)`. Missing/censored
medians and their weights leave both numerator and denominator. The denominator
is thus the available-rent subset, although saved tract `rhuE` sums all allocated
renter units. No available positive weight yields a missing/undefined result,
not zero rent. A missing weight attached to an observed median makes the result
missing; `na.rm = TRUE` does not simply discard such weights. This follows the
installed `matrixStats` 1.5.0 documentation for `weightedMean`.
`lqcrentE` uses the same averaging rule on available block-group contract-rent
quartiles, with its own missing/censoring subset.

The related shares are

$$
\mathrm{pct\_m\_rent}_t=\frac{\sum_bq_{bt}1[m_b\text{ missing}]}{\sum_bq_{bt}},
\qquad
\mathrm{pct\_tc\_rent}_t=\frac{\sum_bq_{bt}1[m_b\ge3500]}{\sum_bq_{bt}},
$$

and `pct_miss_rent` is their sum after censoring; zero total renter units gives
`NA`. Count sums use `na.rm = TRUE`. These describe units in block groups with
missing/censored **medians**, not the share of individual rents unobserved or
above $3,500. They flag coverage loss but do not correct it.
([Share helpers](../R/assemble_helpers.R#L236).)

**Split-geography implementation is sound for this index.** Grouping is by
destination `tr2010_id`; each allocation contributes $a_{bt}N_b$ once, with
the source median unchanged. A hypothetical 100-renter source split 25%/75%
contributes 25/75 units, not 100 to each tract. Original fractions are preserved
when destinations are restricted, and pair uniqueness is asserted. `_agg`
summary names preserve the source `rhuE` vector during calculation. Precomputed
`rel_wt_rhu = q_bt / sum(q_bt)` is not used for `rentE` or `rentM`.
([Allocation checks](../02_assemble.Rmd#L197),
[weight preservation](../02_assemble.Rmd#L319).)

**Statistical limits remain.** Medians cannot generally be combined by averaging;
even changing to a weighted median of source medians would not recover the pooled
median. Census explicitly distinguishes nonaggregable medians from aggregable
distribution counts. Using $N_b$ also weights a cash-rent statistic by a broader
universe; $a_{bt}C_b$ would align an average-of-medians index with cash renters,
but would still not produce a tract median. Excluding high-median block groups
selects on rent itself and lowers the index relative to retaining their true
medians; it also removes their lower-rent households. General missingness has
no assured bias direction. ([Census median guidance](https://www.census.gov/programs-surveys/acs/technical-documentation/user-notes/2016-01.html).)

For a **tract median**, the distribution-based rule would instead be

$$
\widehat F_t(x)=\frac{\sum_b a_{bt}C_bF_b(x)}{\sum_b a_{bt}C_b},
\qquad \widehat M_t=\inf\{x:\widehat F_t(x)\ge0.5\},
$$

where $F_b$ is the source cash-rent distribution. The existing
[calc_interp_rent()](../R/assemble_helpers.R#L394) approximates this using B25063
bins. With source bin counts $n_{bk}$, it computes

$$
B_{tk}=\sum_ba_{bt}n_{bk},\quad H_t=\sum_ba_{bt}C_b,\quad
k^*=\min\{k:\sum_{j\le k}B_{tj}\ge H_t/2\},
$$
$$
\mathrm{interp\_rent}_t=L_{k^*}+(U_{k^*}-L_{k^*})
\frac{H_t/2-\sum_{j<k^*}B_{tj}}{B_{tk^*}}.
$$

The code uses printed bin endpoints (e.g., 1,000–1,249, width 249), and returns
`NA` for the bottom/top category or no cash renters. Missing/censored `rentE`
does not remove a source's bin counts: the $3,500+ bin remains in the cumulative
distribution and denominator. This logic and implementation agree for complete,
nonnegative counts with $H_t=\sum_kB_{tk}>0$. Because cash totals and bins each
use `sum(..., na.rm = TRUE)`, missing counts contribute zero independently;
completeness and reconciliation are necessary conditions, not established
empirical results of this audit. ([Census B25063 definitions](https://api.census.gov/data/2024/acs/acs5/groups/B25063.html).)

Both approaches assume that the crosswalk's renter allocation represents the
2020–2024 sources and that the relevant rent composition is shared across each
source's destination pieces. The binned median additionally assumes a uniform
distribution within the selected bin. These are reasonable interpolation
assumptions, not observed rents for the intersections. NHGIS defines these as
modeled allocation fractions; Census illustrates estimating medians from pooled
bins while warning that they need not match published medians.
([NHGIS crosswalk methodology](https://www.nhgis.org/geographic-crosswalks),
[Census handbook, p. 11](https://www.census.gov/content/dam/Census/library/publications/2019/acs/acs_state_local_handbook_2019.pdf#page=16).)

**The rent uncertainty calculation has a separate mismatch.**
[rentM_agg](../R/assemble_helpers.R#L292) averages source MOEs $e_b$:
`weightedMean(rentM, w = rhuE * wt_renthu, na.rm = TRUE)`, using the subset with
available MOEs, independently of available medians. Censoring leaves `rentM`
unchanged. The notebook instead specifies root-sum-of-squares. For the index,
with fixed weights, independent source estimates, and MOEs available for every
contributing median, that approximation would be

$$
\mathrm{MOE}(\widehat R_t)\approx
\sqrt{\sum_{b\in S_t}(\alpha_{bt}e_b)^2},\qquad
\alpha_{bt}=q_{bt}/\sum_{j\in S_t}q_{jt}.
$$

It must use the point estimate's subset and denominator, not the pre-censoring
`rel_wt_rhu`. Even this approximation omits uncertainty in counts/allocations
and is not an MOE for `interp_rent`.

**Panel comparability is incomplete.** The earlier `rentE` is a direct tract
B25064 median, censored at tract level and subsequently inflation-adjusted.
The 2024 index averages block-group medians and can remain observed after
high-rent source contributions disappear. Therefore `rentPOST` mixes
aggregation methods and censoring levels. `interp_rentPOST` is conceptually
closer, but still compares an interpolated median with a published median;
common geography and dollar units do not eliminate that difference.
([Panel definitions](../schemas/acs_full.md).) Census also documents changes to
underlying contract-rent processing limits in 2020 and 2024 and advises caution
with high-rent comparisons; these are distinct from the code's $3,500 censoring
rule for published medians. Their local effect was not measured here.
([Census rent processing note](https://www.census.gov/programs-surveys/acs/technical-documentation/user-notes/2025-06.html).)

**Smallest recommended action:** retain the geographic allocation arithmetic.
The analyst must choose between the descriptive index and a tract-median
approximation, and decide acceptable coverage loss. If a median is required,
use the already-produced `interp_rent`/`interp_rentPOST`, after targeted checks
of bin completeness, nonnegativity, and cash-total reconciliation; do not
silently redefine `rentE` or reuse its MOE. If the index is intended, label it
explicitly, decide whether to use cash-renter weights, and correct `rentM` to
use matching contributors and normalized weights under stated uncertainty
assumptions. Missing MOEs for contributing medians should be flagged, not
silently omitted. No proposed change was implemented.

Validation was limited to source/schema inspection, installed function/help
inspection, and primary-source definitions. These resolved the implementation
questions without empirical diagnostics. No notebook was run, no data were
read or regenerated, and the only repository write was this note.
