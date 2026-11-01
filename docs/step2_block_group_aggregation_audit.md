# Step 2 block-group aggregation audit

Historical notebook references below describe `02_assemble.Rmd` before its split.
Current successors are [02a_build_measures_from_block_groups.Rmd](../02a_build_measures_from_block_groups.Rmd)
(block-group aggregation, §2) and [02b_build_measures_from_tracts.Rmd](../02b_build_measures_from_tracts.Rmd)
(native tract preparation, §§2–3). Historical section/line numbers and findings
are retained; successor links do not imply that those line numbers still apply.

**Audit date:** 2026-09-15. **Authority:** the analyst's intended estimates,
recorded in the [reconciliation table below](#b1-every-intended-estimate).
**Product:** `../../../data/acs_step2_2024_block_group_aggregated.feather`,
2020–2024 ACS block groups allocated to `tr2010_id` (2010 tracts).

This audit uses the current working tree, including the renamed
[block-group Step 2 schema](../schemas/acs_step2_2024_block_group_aggregated.md).
This audit adds only this document; it does not edit existing code,
documentation, schemas, or canonical data. Existing working-tree changes are
preserved, including a concurrent Step 1 edit adding `rhuE` to missingness
diagnostics, which does not affect the source mapping. No API requests or full
notebook/pipeline runs were performed; Step 4 propagation is outside scope.

**Interpretation:** the supplied list defines required estimates. It does not
specify weights, missingness methods, or required MOE/CV companions. Existing
companions are audited separately; their absence is not treated as an
analyst-specified requirement. No intended inclusion is inferred from existing
code.

## A. Executive summary

**The implementation overlaps substantially with the intended list but does not
fulfill the complete contract.** All **39 intended estimates** have source
estimate/MOE columns in the documented and cached Step 1 block-group input.
Only **31** are persisted as individual estimates in Step 2. The eight omissions
are:

- `vac_rentedE`: aggregated only as the separate diagnostic
  `inventory_vac_rentedE`, used in `rhu_inventoryE`.
- `sfd_attE`, `duplexE`, `quadplexE`: used to construct source-level `smfE`,
  but not aggregated or saved individually.
- `mf_5_9E`, `mf_10_19E`, `mf_20_49E`, `mf_50E`: used to construct source-level
  `mfE`, saved after aggregation as `mf5E`, but not saved individually.

There are **no source-field availability blockers (category C)**. The saved
file has **100 columns**, matching the current calculation/save path, including
many unlisted measures, uncertainty fields, diagnostics, and technical columns.
Unlisted measures need a retention decision; this audit does not propose
removing them or treating combined structure counts as substitutes for the
listed components.

**Missingness is measure-specific and incompletely documented.** Ordinary
counts use available-case sums, including zero when all contributing terms are
missing. Inventory alone explicitly propagates missing required estimates on
positive-weight links. Dollar estimates and dollar MOEs use available-case
weighted means. Structure totals first propagate missingness within each source
row, then discard missing source totals. Count MOEs discard missing terms and
can report zero despite entirely missing source MOEs. Raw NHGIS fractions never
change, but weighted means and relative MOE weights involve distinct
normalizations.

The schema largely enumerates the saved fields correctly. Its blanket
root-sum-of-squares description of MOEs conflicts with dollar-MOE code; income
estimate/MOE weights and two share estimate/MOE denominators also differ.
These are research-review issues, not authorized corrections. Adding the eight
missing estimates is the clear follow-up scope; rules for the new standalone
vacancy estimate, companion requirements, and any changes to existing methods
require analyst direction.

### Evidence and validation limits

Read-only inspection found:

| Existing file | Size (bytes) | Rows | Columns | File modification time (local) |
|---|---:|---:|---:|---|
| `acs_step1_2024_block_group.feather` | 6,304,546 | 25,607 | 123 | 2026-09-12 12:53:28 |
| `acs_step2_2024_block_group_aggregated.feather` | 2,642,794 | 5,513 | 100 | 2026-09-15 10:34:39 |

These are observations of this snapshot, not permanent pipeline assumptions.
All 39 intended estimate/MOE pairs were confirmed in the input. Seven actual
Step 2 calculation chunks (§§2.3–2.7), executed only on a two-source synthetic
fixture in memory, reproduced the saved file's complete column list **and
order**. No import, production acceptance/save, or full-data aggregation was
executed. Column agreement does not establish empirical value parity or prove
the provenance of the cached values.

Small helper probes confirmed partial versus all-missing counts/MOEs,
inventory completeness and zero contributors, zero-weight missing sources,
source-level structure missingness, censoring with retained MOEs, and
weighted-mean normalization/missing weights. Environment: R 4.5.1,
`dplyr` 1.1.4, `matrixStats` 1.5.0, `arrow` 21.0.0.1. No dependencies changed.

## B. Reconciliation

### Reading the tables

- **A:** intended estimate/source mapping is implemented and persisted.
  Because the intended list supplies no numerical method, A verifies inclusion
  and construction from the named source; it is not an endorsement of existing
  weights or missingness.
- **B:** intended standalone estimate is absent, despite available source data.
  Use in an aggregate or diagnostic does not satisfy persistence.
- **C:** intended but unavailable; none found.
- **D:** implemented concept or companion not explicitly in the intended list.
  Technical fields are identified separately within D.
- **E review flags** supplement A/B/D rather than obscuring inclusion:
  **E1** undocumented missingness/normalization; **E2** components only or
  diagnostic-only persistence; **E3** estimate/uncertainty method, coverage,
  weight, or denominator inconsistency; **E4** misleading documentation.

Weight abbreviations: **R** = `wt_renthu`, **H** = `wt_hu`, **P** = `wt_pop`,
**HH** = `wt_hh`. ACS codes below identify both source estimate (`E`) and
90% MOE (`M`) fields unless only E is specified. Source aliases are defined in
[the Step 1 mapping](../schemas/acs_step1_2016_tract.md)
and retained by [the block-group schema](../schemas/acs_step1_2024_block_group.md).

Missingness codes, detailed in §D:

| Code | Implemented construction and missingness | Normalization after missing values? |
|---|---|---|
| **S** | `sum(x * allocation, na.rm = TRUE)`; missing products are omitted; all omitted gives 0. | No count rescaling; raw fractions unchanged. |
| **W** | `weightedMean(x, w, na.rm = TRUE)`; missing x and its weight are omitted, then a weighted mean is calculated. Missing w for retained x propagates missingness. | Yes, divide by the surviving effective-weight total; raw fractions unchanged. |
| **C** | Add structure components within each source using `+`, then S on that combined count. | No; a source with any missing component is omitted as a whole. |
| **L** | Step 1 `rowSums(..., na.rm = TRUE)` of available rent bins, then Step 2 S. | No at either step. |
| **I** | Separate component sums only over R > 0, without `na.rm`; any missing contributing component makes inventory missing. | No; zero-contributor targets have zero totals. |
| **U** | Relative-weight root-sum-of-squares, omitting missing products; selected measures have zero-total guards. | Relative weights normalize available base estimates; no subsequent renormalization for missing MOEs. |
| **Q** | A ratio of already aggregated values; return NA for non-positive denominator. | Ratio only; no source-completeness adjustment. |
| **T** | Rent-quality count/share or flag calculated from source rent and allocated renter counts. | S for counts, Q for shares; flag rule described below. |

### B.1 Every intended estimate

All rows are **intended**, and **both E and M source fields are available** in
the schema and current input. “Saved” means both selected by code and present
in the inspected Feather. Companion persistence is addressed separately in B.3.

| Intended estimate | ACS source | Aggregation in code | Weight | Missingness / normalization | Saved? | Current Step 2 documentation | Status / note |
|---|---|---|---|---|---|---|---|
| `popE` | B01003_001 | Direct sum | P | S / no | Yes | Listed; S omitted | A; E1 |
| `med_hhincE` | B19013_001 | Mean of source medians | `hhE * HH` | W / yes | Yes | Available-income rule stated | A; E1/E3: missing effective weights and different MOE weight |
| `grentcat1E` | B25063_003 | Direct sum | R | S / no | Yes | Listed in 1–24 range; S omitted | A; E1 |
| `grentcat2E` | B25063_004 | Direct sum | R | S / no | Yes | Same | A; E1 |
| `grentcat3E` | B25063_005 | Direct sum | R | S / no | Yes | Same | A; E1 |
| `grentcat4E` | B25063_006 | Direct sum | R | S / no | Yes | Same | A; E1 |
| `grentcat5E` | B25063_007 | Direct sum | R | S / no | Yes | Same | A; E1 |
| `grentcat6E` | B25063_008 | Direct sum | R | S / no | Yes | Same | A; E1 |
| `grentcat7E` | B25063_009 | Direct sum | R | S / no | Yes | Same | A; E1 |
| `grentcat8E` | B25063_010 | Direct sum | R | S / no | Yes | Same | A; E1 |
| `grentcat9E` | B25063_011 | Direct sum | R | S / no | Yes | Same | A; E1 |
| `grentcat10E` | B25063_012 | Direct sum | R | S / no | Yes | Same | A; E1 |
| `grentcat11E` | B25063_013 | Direct sum | R | S / no | Yes | Same | A; E1 |
| `grentcat12E` | B25063_014 | Direct sum | R | S / no | Yes | Same | A; E1 |
| `grentcat13E` | B25063_015 | Direct sum | R | S / no | Yes | Same | A; E1 |
| `grentcat14E` | B25063_016 | Direct sum | R | S / no | Yes | Same | A; E1 |
| `grentcat15E` | B25063_017 | Direct sum | R | S / no | Yes | Same | A; E1 |
| `grentcat16E` | B25063_018 | Direct sum | R | S / no | Yes | Same | A; E1 |
| `grentcat17E` | B25063_019 | Direct sum | R | S / no | Yes | Same | A; E1 |
| `grentcat18E` | B25063_020 | Direct sum | R | S / no | Yes | Same | A; E1 |
| `grentcat19E` | B25063_021 | Direct sum | R | S / no | Yes | Same | A; E1 |
| `grentcat20E` | B25063_022 | Direct sum | R | S / no | Yes | Same | A; E1 |
| `grentcat21E` | B25063_023 | Direct sum | R | S / no | Yes | Same | A; E1 |
| `grentcat22E` | B25063_024 | Direct sum | R | S / no | Yes | Same | A; E1 |
| `grentcat23E` | B25063_025 | Direct sum | R | S / no | Yes | Same | A; E1 |
| `grentcat24E` | B25063_026 | Direct sum, including top rent bin | R | S / no | Yes | Same; no bin censoring | A; E1 |
| `rhu_baseE` | B25003_001 | Direct sum of total occupied units | R | S / no | Yes | Listed; renter-weight rule only implicit | A; E1/E3: its MOE uses relative H weights |
| `rhuE` | B25003_003 | Direct sum | R | S / no | Yes | Listed; S omitted | A; E1: differs from strict inventory component |
| `vac_forrentE` | B25004_002 | Supplemental direct sum | H | S / no | Yes | H versus inventory R documented; S omitted | A; E1 |
| `vac_rentedE` | B25004_003 | Only `inventory_vac_rentedE` diagnostic sum | R for diagnostic | I / no for diagnostic; no standalone rule | **No** | Diagnostic-only role documented | B; E2 |
| `sfd_baseE` | B25024_001 | Direct sum | H | S / no | Yes | Listed; S omitted | A; E1 |
| `sfd_detE` | B25024_002 | Direct sum | H | S / no | Yes | Listed; S omitted | A; E1 |
| `sfd_attE` | B25024_003 | Component of source `smfE` only | H on combined count | C / no; no standalone rule | **No** | Named only in combined definition | B; E2 |
| `duplexE` | B25024_004 | Component of source `smfE` only | H on combined count | C / no; no standalone rule | **No** | Same | B; E2 |
| `quadplexE` | B25024_005 | Component of source `smfE` only | H on combined count | C / no; no standalone rule | **No** | Same | B; E2 |
| `mf_5_9E` | B25024_006 | Component of source `mfE` → saved `mf5E` | H on combined count | C / no; no standalone rule | **No** | Named only in combined definition | B; E2 |
| `mf_10_19E` | B25024_007 | Component of source `mfE` → saved `mf5E` | H on combined count | C / no; no standalone rule | **No** | Same | B; E2 |
| `mf_20_49E` | B25024_008 | Component of source `mfE` → saved `mf5E` | H on combined count | C / no; no standalone rule | **No** | Same | B; E2 |
| `mf_50E` | B25024_009 | Component of source `mfE` → saved `mf5E` | H on combined count | C / no; no standalone rule | **No** | Same | B; E2 |

### B.2 Additional implemented and persisted measures

Every row below is **D**, not listed as intended. Every named source field is
available; every output below is produced and present in the Feather. Derived
fields use the already aggregated operands unless explicitly described as
source-first. The schema names all these fields; qualifications identify
documentation or implementation inconsistencies.

| Output / concept | Source fields or operands | Construction / weight | Missingness / normalization | Documentation and E review |
|---|---|---|---|---|
| `huE` | B25001_001E | Direct sum / H | S / no | E1 |
| `hhE` | B11001_001E | Direct sum / HH | S / no | E1 |
| `rhu_lrE` | B25063_003E–020E (`grentcat1E`–18E) | Source low-rent sum, then R | L / no | E1: both available-case steps implicit |
| `rhu_lr2E` | B25063_003E–022E (`grentcat1E`–20E) | Source low-rent sum, then R | L / no | Same |
| `tot_vacE` | B25002_003E | Direct sum / H | S / no | E1 |
| `tot_vac_baseE` | B25002_001E | Direct sum / H | S / no | E1 |
| `pop_blkE` | B02001_003E | Direct sum / P | S / no | E1 |
| `pop_hspE` | B03003_003E | Direct sum / P | S / no | E1 |
| `pop_aaE` | B02001_005E | Direct sum / P | S / no | E1 |
| `pop_raceE` | B02001_001E | Direct sum / P | S / no | E1 |
| `pop_ethnE` | B03003_001E | Direct sum / P | S / no | E1 |
| `rhucashE` | B25063_002E | Direct sum / R | S / no | E1 |
| `vac_forsaleE` | B25004_004E | Supplemental sum / H | S / no | E1 |
| `ohuE` | B25003_002E | Supplemental sum / H | S / no | E1 |
| `smfE` | B25024_003E–005E | Source `sfd_attE + duplexE + quadplexE`, then H sum | C / no | E1: source-component propagation omitted |
| `mf5E` | B25024_006E–009E | Source four-category sum `mfE`, then H sum and rename | C / no | E1; `mfE` is not a second persisted field |
| `nsfaE` | `smfE + mf5E` | Add separately aggregated groups | Inherits C in each group; no new completeness check | E1: groups can cover different source subsets |
| `rhu_inventoryE` | B25003_003E + B25004_002E + B25004_003E | Add independently R-weighted diagnostic components | I / no | Detailed and consistent documentation; no MOE/CV |
| `rentE` | B25064_001E | Mean of source medians / `rhuE * R` | W / yes; source values ≥3500 first set to NA | E1/E3: estimate/MOE source coverage can differ |
| `lqcrentE` | B25057_001E | Mean of source lower quartiles / `rhuE * R` | W / yes; source values ≥3500 first set to NA | Same |
| `med_hvalE` | B25077_001E | Mean of source medians / `huE * H` | W / yes; no BG house-value censoring | E1: available-case mean details omitted |
| `interp_rent` | Aggregated B25063_002E and 003E–026E | Find first bin reaching `rhucashE/2`, then interpolate within bin | No completeness adjustment; NA for edge bins, no cash units, or no median-bin match | E1: incomplete-bin coverage can affect interpolation |
| `pctrhuE` | `rhuE / huE` | Post-aggregation share | Q / ratio | E3: MOE instead uses `rhu_baseE/M` |
| `pctvacE` | `tot_vacE / tot_vac_baseE` | Post-aggregation share | Q / ratio | E1: component availability not aligned |
| `pctblkE` | `pop_blkE / pop_raceE` | Post-aggregation share | Q / ratio | Same |
| `pcthspE` | `pop_hspE / pop_ethnE` | Post-aggregation share | Q / ratio | E3: MOE instead uses `pop_raceE/M` |
| `pctaaE` | `pop_aaE / pop_raceE` | Post-aggregation share | Q / ratio | E1 |
| `pctsfdE` | `sfd_detE / sfd_baseE` | Post-aggregation share | Q / ratio | E1 |
| `pctrvacE` | `vac_forrentE / (rhuE + vac_forrentE)` | Post-aggregation rate; R renter count, H vacancy count | Q / ratio | Different component weights documented; S not explicit |
| `pctsvacE` | `vac_forsaleE / (ohuE + vac_forsaleE)` | Post-aggregation rate, H components | Q / ratio | Denominator guard documented; S not explicit |
| `rhu_miss_rent` | Post-censoring missing `rentE`, B25003_003E | Sum renter units with missing/censored rent / R | S / no | Missing versus censored meaning documented; missing counts omitted |
| `hu_miss_hval` | Missing `med_hvalE`, B25001_001E | Sum housing units with missing value / H | S / no | E1; house-value top codes are not included automatically |
| `pct_miss_rent` | `rhu_miss_rent / rhuE` | Post-aggregation quality share | Q / ratio | Includes raw missing and censored rent, as documented |
| `pct_miss_hval` | `hu_miss_hval / huE` | Post-aggregation quality share | Q / ratio | E1: missing housing counts excluded from both sums |
| `pct_tc_rent` | Uncensored B25064_001E ≥3500; B25003_003E | Top-coded allocated renter units / total allocated renter units | T: S then Q | Distinction from genuine source missingness documented |
| `tc_flag_rent_24` | `pct_tc_rent` | 1 iff nonmissing share >0; otherwise 0 | T; missing share becomes flag 0 | E4: schema's “any top-coded” wording misses positive-contribution condition |

The rent-category counts, cash-rent counts, and low-rent counts are **not**
censored when source median rent is missing or ≥3500. `interp_rent` therefore
does not inherit `rentE`'s censoring or available-source set. No production
analytic measure is passed through from the separate 2024 tract product.

### B.3 Uncertainty companions

All fields in this table are saved. Each source M is available in Step 1.
Companions are audited as **D (not explicitly specified)**; E3/E4 identify
actual inconsistencies, without assuming every intended estimate requires an MOE.

Let `uR = rhuE*R / sum(rhuE*R, na.rm=TRUE)`, `uH = huE*H /
sum(huE*H, na.rm=TRUE)`, and `uP = popE*P / sum(popE*P, na.rm=TRUE)` on source
allocation rows within a target. U is `sqrt(sum((source_M*u)^2, na.rm=TRUE))`.
Guards use these source-base totals, not the completeness of the source M.

| Saved MOE; saved CV if any | Source M / construction | Weight and missingness | Documentation / review |
|---|---|---|---|
| `rentM`; `rentCV` | B25064_001M | W with `rhuE*R`; estimate censoring does not censor M | E3/E4: documented RSS, implemented mean |
| `lqcrentM` | B25057_001M | W with `rhuE*R`; estimate censoring does not censor M | Same; no `lqcrentCV` |
| `med_hhincM`; `med_hhincCV` | B19013_001M | W with **`rhuE*R`**, while estimate uses **`hhE*HH`** | E3/E4: weight mismatch and documented RSS |
| `med_hvalM`; `med_hvalCV` | B25077_001M | W with `huE*H` | E3/E4: documented RSS, implemented mean |
| `rhuM`; `rhuCV` | B25003_003M | U / uR; NA if allocated renter total =0 | RSS stated; omission/zero rules absent (E1) |
| `rhu_baseM` | B25003_001M | U / **uH**, no guard; estimate uses R | E1/E3 |
| `tot_vacM` | B25002_003M | U / uH, no guard | E1 |
| `tot_vac_baseM` | B25002_001M | U / uH, no guard | E1 |
| `pop_blkM`; used in `pctblkM` | B02001_003M | U / uP, no guard | E1 |
| `pop_hspM`; used in `pcthspM` | B03003_003M | U / uP, no guard | E1 |
| `pop_aaM` | B02001_005M | U / uP, no guard | E1 |
| `pop_raceM` | B02001_001M | U / uP, no guard | E1 |
| `sfd_detM` | B25024_002M | U / uH, no guard | E1 |
| `sfd_baseM` | B25024_001M | U / uH, no guard | E1 |
| `huM`; `huCV` | B25001_001M | U / uH; NA if allocated housing total =0 | E1 |
| `popM`; `popCV` | B01003_001M | U / uP; NA if allocated population total =0 | E1 |
| `pctrhuM`; `pctrhuCV` | `sqrt(pmax(0, rhuM^2 - pctrhuE^2*rhu_baseM^2))/rhu_baseE` | Post-aggregation; NA if `rhu_baseE=0`; missing operands propagate | E3: estimate denominator is `huE` |
| `pctblkM`; `pctblkCV` | `sqrt(pmax(0, pop_blkM^2 - pctblkE^2*pop_raceM^2))/pop_raceE` | Post-aggregation; NA if `pop_raceE=0`; missing operands propagate | Formula only implicitly documented |
| `pcthspM`; `pcthspCV` | `sqrt(pmax(0, pop_hspM^2 - pcthspE^2*pop_raceM^2))/pop_raceE` | Post-aggregation; NA if `pop_raceE=0`; missing operands propagate | E3: estimate denominator is `pop_ethnE` |

All nine CVs use `(M / 1.645) / E`. `rentCV`, `med_hhincCV`, and
`med_hvalCV` have no zero-estimate guard: zero estimates can yield `Inf` or
`NaN`. The other six CVs return NA at zero estimates. None tests source
completeness beyond the already aggregated E/M. Negative share-MOE radicands
are clamped to zero; missing operands remain missing.

**Companions not saved:** all 24 `grentcat*M`; `vac_forrentM`, `vac_rentedM`;
the seven omitted structure categories' M fields; `hhM`, `rhucashM`, `ohuM`,
`vac_forsaleM`, `pop_ethnM`. There are no MOEs for low-rent, combined structure,
inventory, interpolation, or vacancy-rate measures, and no other CVs beyond
the nine listed. No BG `m_flag_*`, `zero_flag_*`, `tc_flag_lqcrent`, or
`tc_flag_med_hval` fields enter the output. These are observations, not inferred
requirements. The absence of `pop_ethnM` matters when reviewing `pcthspM`'s
different denominator bundle.

### B.4 Technical fields and notebook-only measures

The following five technical fields complete the 100-column persisted contract.
Their D classification does not imply that identifiers should be removed.

| Saved field | Origin / behavior | Documented? |
|---|---|---|
| `tr2010_id` | Crosswalk destination key, retained through grouping and joins; unique/nonmissing assertions | Yes |
| `rhu_id` | Logical constant TRUE created by `calc_agg_vars()` | Yes |
| `merge` | Character indicator recreated by `merge_df()`; final joins must all be `"both"` | Yes |
| `left_id` | Logical TRUE indicator for membership in final join's left input | Yes |
| `right_id` | Logical TRUE indicator for membership in final join's right input | Yes |

These relevant intermediate concepts are **not saved**. They do not enlarge
the persisted contract:

| Diagnostic / intermediate | Source and construction | Missingness / weight adjustment | Documentation |
|---|---|---|---|
| `inventory_rhuE` | B25003_003E, separate sum over R >0 | I component rule / no renormalization | Explicit |
| `inventory_vac_forrentE` | B25004_002E, separate sum over R >0 | I component rule; different weight and completeness from saved `vac_forrentE` | Explicit |
| `inventory_vac_rentedE` | B25004_003E, separate sum over R >0 | I component rule; does not persist intended `vac_rentedE` | Explicit; B/E2 for standalone omission |
| `n_contributing` | Count of links with R >0 | Zero allowed; ignores zero-weight rows | Explicit |
| `n_missing_rhuE` | Count of missing renter estimates on R >0 | Includes NA/NaN only on contributors | Explicit as a family |
| `n_missing_vac_forrentE` | Same for for-rent vacancies | Same | Same |
| `n_missing_vac_rentedE` | Same for rented vacancies | Same | Same |
| `inventory_incomplete` | Any of the three missing counts >0 | False for zero contributors; only final inventory forced missing | Explicit |
| `pct_m_rent` | Raw missing-rent renter share, before censoring | S then Q; no imputation of missing renter counts | Explicit as diagnostic; removed before final share join |
| `rel_wt_rhu` | Allocated source `rhuE` / target available renter total | Normalized base estimates; missing base → missing relative weight | Definition stated; missingness implicit |
| `rel_wt_hu` | Allocated source `huE` / target available housing total | Same | Same |
| `rel_wt_pop` | Allocated source `popE` / target available population total | Same | Same |

Other notebook-only checks include source/retained weight totals, boundary
`allocated_pop/hh/hu/rhu`, raw county rent shares, legacy/corrected income
E/CV expectations (using the prior-output MOE), allocated-count reconciliation,
and inventory county/reconciliation summaries. `calc_pct_tc_m()` discards its
internal `rhuE_tot`, `rhu_m_rent`, and `rhu_tc_rent` counts. Interpolation's
median-bin index, counts, cumulative count, threshold, bounds, proportion, and
width are also temporary. Printed distribution summaries and the commented,
`eval=FALSE` missing-rent appendix are not production fields.

Available but otherwise unused BG source concepts (`pop_rent`, `mobhm`,
`oth_units`, `rhutot`, `rhunocash`, including their E/M pairs), `NAME`, and
source/crosswalk join flags do not survive aggregation. They are neither
intended-list omissions nor additional implemented tract measures.

## C. Implementation map

Line numbers refer to the audited working tree; chunk/function names provide
stable search targets. There is no single final column allowlist: the output
is assembled through summarization and joins, then written in full.

| Location | Contract-defining action |
|---|---|
| [01_acs.Rmd](../01_import_acs.Rmd), §§1.2, 2.2 (lines 113–126, 178–278) | Defines bedroom-rent exclusions, `tract_vars`, and derived `block_group_vars`; excludes no intended measure. Duplicate-code aliases resolve to first rent-bin aliases. |
| `01_acs.Rmd`, §§4.1–4.4 (lines 369–434); [R/helpers.R](../R/helpers.R), `rent_cat_sum()` (line 22) | Downloads E/M pairs; derives source low-rent counts with available-case row sums; saves the BG input. |
| [02_assemble.Rmd](../02a_build_measures_from_block_groups.Rmd), §§2.1–2.2 (lines 203–346) | Reads full BG input and crosswalk; selects destination counties, joins contributing sources, validates keys/weights. Does not select a narrow source-variable list. |
| `02_assemble.Rmd`, §2.3 (lines 369–409); [R/assemble_helpers.R](../R/assemble_helpers.R), `calc_rel_wt()` (343), `calc_pct_tc_m()` (376) | Builds relative MOE weights; raw missing/top-code shares. Saves only key, `pct_tc_rent`, and derived flag in the later join table. |
| `02_assemble.Rmd`, §2.4 (lines 437–474); `censor_tc_vars()` (405) | Keeps optional income expectations separate; censors rent/lower quartile; builds source `mfE` and `smfE` with ordinary `+`. |
| `R/assemble_helpers.R`, `calc_agg_vars()` (418–527); notebook §2.5 | Defines ordinary count, dollar E/M, count-MOE, and missing-count selections. Only `starts_with("grentcat") & ends_with("E")` is dynamic; current input yields exactly 24 bins. Adds `rhu_id`; drops residual `_agg` columns after renaming. |
| `02_assemble.Rmd`, `aggregate-supplemental-2024-bg-aggregated` (535–555) | Renames `mfE` to `mf5E`; separately H-sums `vac_forrentE`, `vac_forsaleE`, `ohuE`, `smfE`; joins all four. |
| `calc_rental_inventory()` (206–270); notebook `rental-inventory-2024-bg-aggregated` (581–615) | Applies positive-weight completeness rule; selects **only key and `rhu_inventoryE`** from the diagnostic table for the production join. |
| `calc_interp_rent()` (534–591), `calc_missing_vars()` (598), `calc_pct_vars()` (609), `calc_cv()` (628); notebook §2.6 (650–674) | Selects key plus interpolated rent; derives shares/MOEs/CVs; adds `nsfaE` and vacancy rates. |
| `merge-flags-2024-bg-aggregated` (679–692); `merge_df()` (60–82) | Joins top-code share/flag and interpolation; reconstructs join indicators. No subsequent production-variable selection. |
| `acceptance-2024-bg-aggregated` and `save-2024-bg-aggregated` (718–735); `save_data()` (47–50) | Checks geography, inventory and optional parity; writes the **entire** `acs_2024_bg_aggregated_interp` via `arrow::write_feather()`. |
| Notebook §§5.1, 5.5–5.6 (1291 onward); [R/geography_qa.R](../R/geography_qa.R), `assert_same_schema()`, `compare_socal_parity()` | Checks reloaded names/order/types against the in-memory output, rent-share decomposition, inventory, and values. Optional prior-schema migration allows only `rhu_inventoryE` as a BG addition. It does not compare against the analyst list. |

Geography is destination-selected: all sources allocating to the 14 configured
counties are retained, including outside sources. Matched zero-weight links
remain. Unmatched links may be excluded only if **all four** weights are finite
and exactly zero, with target membership preserved; other unmatched links stop
execution. Missing source records are therefore not silently treated like
missing field values. Original finite [0,1] allocation fractions are preserved.

## D. Missingness summary

### D.1 Available-case counts and precomputed totals

All ordinary count estimates in B.1/B.2 use S, without a completeness flag or
rescaling. A genuinely missing positive-weight observation is dropped.
`NA * 0` is also missing but is discarded by `na.rm=TRUE`; neither it nor an
observed zero-weight row contributes. All missing products, all zero weights,
or observed zeros can each yield the same saved zero. No accompanying flag
distinguishes these cases.

Low-rent source counts already discard missing bins in Step 1 (L). In contrast,
`smfE` and `mfE` use source-level `+`: one missing category makes that source's
whole combined count missing, including its otherwise observed categories.
The later available-case sum drops that whole source contribution. Thus
`nsfaE = smfE + mf5E` may combine groups calculated from different subsets;
all missing source totals can still yield zero. This is not equivalent under
missingness to separately aggregating and then adding every structure category.

### D.2 Strict positive-contributor completeness

Only inventory uses I. Component missingness propagates separately into its
diagnostic total; any missing required contributor makes final inventory NA.
Other component diagnostics can remain observed. Zero-weight rows are filtered
**before** multiplication/summing and do not affect completeness. No positive
contributors gives zero components/inventory and `inventory_incomplete=FALSE`.
Missing MOEs do not affect inventory, although all three E/M source pairs must
exist and have numeric types. Observed contributing estimates must be finite
and nonnegative; invalid weights or observed contributing values stop execution.

Consequently, saved `rhuE` can remain a partial available-case count while
`inventory_rhuE` and `rhu_inventoryE` are missing. Saved `vac_forrentE` also
differs from its inventory component in **both weight and completeness**.
No standalone missingness rule is implemented for the eight omitted estimates.

### D.3 Weighted means, censoring, and normalization

W divides by the weights of retained, nonmissing values. This is a
measure-specific normalization, even though NHGIS fractions are unchanged.
All values missing or no positive effective weight gives `NaN` in the installed
`matrixStats::weightedMean()`. A missing effective count-weight for an observed
value returns NA; if that value is itself missing, its weight is discarded too.
Even an allocation fraction of zero does not neutralize a missing source count
in `count * fraction`: the effective weight is still missing. A helper probe
confirmed this can make a weighted mean missing on a non-contributing row.

Only source `rentE` and `lqcrentE` ≥3500 are censored. Their M values remain
eligible, so E and M can describe different source subsets and E can be missing
while M is observed. Source income is retained independently of rent censoring.
`med_hvalE` is not censored on the BG path. The top gross-rent **count bin** is
retained; it is not the same concept as a censored source median.

### D.4 Count MOEs and derived uncertainty

Relative MOE weights use available source **base estimates** in their
denominators. Missing base estimates produce missing relative weights; zero
base totals produce undefined relative weights. U discards missing MOEs or
missing/undefined relative-weight products without adjusting the other weights
again. This differs from W, which normalizes separately over observed E or M.

If base totals are positive but every M is missing, U returns **zero**. With
zero base totals, `rhuM`, `huM`, and `popM` explicitly return NA; the other nine
count MOEs lack that guard and can return zero after all undefined terms are
discarded. The four dollar MOEs instead use W and can remain missing. These
differences are not documented as a coherent uncertainty-completeness contract.

Derived share MOEs/CVs operate on the resulting aggregates, with the formulas
and denominator/zero guards in B.3. A source-incomplete zero MOE can propagate
to an observed zero CV. A missing aggregated operand generally propagates
missingness; no derived helper recovers source completeness information.

### D.5 Ratios, interpolated rent, and quality flags

Q uses available-case component totals without a common source-completeness
rule. A missing numerator's sources can disappear into a zero numerator while
the denominator remains positive. Numerator and denominator may therefore
represent different available-source sets. The guards prevent division by
non-positive denominators, not these coverage differences.

Interpolation uses the separately aggregated cash-rent total and bin counts.
It does not check whether those represent the same available observations or
whether every contributing bin was observed. It returns NA for bottom/top
median bins, no cash units, or failure to find a bin reaching the threshold;
otherwise it interpolates using `upper - lower` (for example, 149 − 100).
Missing source bins can affect the result without making interpolation missing.

Rent-quality sums omit missing allocated renter counts. `pct_m_rent` uses
genuine source missingness before censoring; `pct_tc_rent` uses observed raw
rent ≥3500 with nonzero renter counts. `pct_miss_rent` is calculated after
censoring and includes both; §5.5 checks their decomposition. Zero renter
denominators yield missing shares, but `tc_flag_rent_24` becomes **0** when
`pct_tc_rent` is missing. A top-coded source with no positive allocated renters
does not set the flag. These shares/flags describe rent observability or
censoring, not general count or MOE completeness.

## E. Documentation discrepancies

| Finding | Evidence and effect |
|---|---|
| **Blanket MOE formula is wrong for four saved fields.** | Step 2 schema “Aggregation method”/MOE section and notebook §2.5 say RSS. `rentM`, `lqcrentM`, `med_hhincM`, `med_hvalM` are weighted means. Notebook §5.5 acknowledges unresolved dollar-MOE behavior but does not correct the earlier statement. |
| **Estimate/MOE weights and denominators are not fully disclosed.** | Income E uses households, M uses renter units. `rhu_baseE` uses R, its M uses uH. `pctrhuE` uses `huE` but M uses `rhu_baseE/M`; `pcthspE` uses `pop_ethnE` but M uses `pop_raceE/M`. Generic “corresponding share MOE” wording hides these distinctions. |
| **Most missingness rules are unstated.** | Schema, README and notebook prose describe counts as weighted sums without `na.rm=TRUE`, all-missing →0, or source-first structure propagation. Step 1's low-rent row-sum documentation likewise omits available-case behavior. No general count completeness flag is produced. |
| **Weight preservation is not a complete normalization description.** | Geographic no-renormalization claims are correct. Dollar means nevertheless normalize over observed values; relative MOE weights normalize base counts and then discard missing MOEs without a second normalization. Income's available-case rule is documented, but missing count-weights and zero-weight NA behavior are not. |
| **Censoring and uncertainty coverage can diverge.** | Rent E censoring is documented; unchanged M and separately selected E/M source subsets are not. The BG schema should distinguish house-value missingness from the separate tract-source top-code flags. |
| **Top-code flag description is too broad.** | “Any top-coded” rent does not specify positive allocated renter contribution or flag 0 when the share is missing. The exact code tests `!is.na(pct_tc_rent) & pct_tc_rent > 0`. |
| **Interpolation/derived completeness is implicit.** | Open-bin/no-cash exclusions are described, but no-threshold-match NA and independently incomplete cash/bin aggregates are not. The notebook calls the comparison measure “weighted median rent”; `rentE` is a weighted **mean of BG medians**. |
| **Schema references are stale after working-tree renames.** | README Step 2 still names `schemas/acs_step2_16.md` and `schemas/acs_step2_24.md` and says schema paths were retained. The BG schema points share definitions to the absent `acs_step2_16.md`; the actual current file is `acs_step2_2016_tract.md`. Shared [PIPELINE.md](../../../PIPELINE.md) also links the old schema. |
| **Overview includes stale consumer prose.** | Notebook overview says Census tract measures do not enter the saved panel, contrary to the current README/shared pipeline descriptions. This is a documentation finding only; no Step 4 code or propagation audit was undertaken. |
| **The schema is an inventory, not an explicit intended-output reconciliation.** | Its listed production fields cover the inspected 100 columns; no unexpected cached-only field or documented production-field absence was found. It accurately omits the eight standalone estimates and distinguishes inventory diagnostics, but does not identify the analyst-intent gap. Subsection rows under “Derived measures” also lack complete standalone Markdown table headers/separators, reducing readability. |

Inventory's positive-contributor rule, zero-contributor behavior, diagnostic
persistence, and H-versus-R vacancy distinction are explicitly and consistently
documented in the schema, README, notebook, and shared pipeline. These are not
documentation omissions. The eight absent standalone estimates are an
**intent-versus-implementation** discrepancy, distinct from a schema/cache
disagreement.

## F. Recommended follow-up scope — not implemented

### F.1 Code scope implied directly by the intended list

1. Aggregate and persist the seven named structure estimates independently;
   keeping only `smfE`/`mf5E` cannot meet the list. All source fields already
   exist. Existing structure allocation uses H; completeness for the new
   individual fields should be made explicit without silently changing the
   combined measures.
2. Persist a standalone `vac_rentedE` constructed from B25004_003E. Its intended
   inclusion is settled; its weight/completeness rule is not specified by the
   list. The current diagnostic must not be copied under that name without
   settling F.4.
3. Extend the explicit Step 2 output/parity contract for approved additions:
   the current BG migration allows **only** `rhu_inventoryE`, so other added
   columns would fail comparisons when a prior reference exists. Preserve
   reference snapshots and shared-column checks. No additional ACS download
   is implied by the eight missing fields.

### F.2 Corresponding schema/documentation updates

Document every approved new field's source, weight, missingness, persistence,
and companion policy. Synchronize the Step 2 schema, notebook overview/prose,
README, and relevant shared pipeline description. Repair renamed schema links
and table formatting. Any decision about unlisted measures must be reflected
in the explicit contract; their presence alone does not authorize removal.

### F.3 Straightforward documentation of existing behavior

Describe S/L/C/W/U/Q/T rules as implemented, including all-missing zeros,
missing/zero effective weights, MOE guards, actual dollar-MOE means, different
estimate/MOE weights and denominators, rent censoring without M censoring,
interpolation completeness limits, and zero-denominator flag behavior.
Distinguish unchanged allocation fractions from weighted-mean and relative-MOE
normalization. Preserve the already explicit inventory rules. These additions
can document current behavior without changing a substantive rule.

### F.4 Unresolved analyst decisions

- Which D measures and companions belong in the eventual product? The intended
  list is silent about rent medians/interpolation, inventory, combined structure
  totals, demographics, shares, and quality measures. Do not remove them merely
  because they are unlisted.
- Should standalone `vac_rentedE` follow the H-weighted, available-case vacancy
  path or the existing R-weighted, strict inventory-component path, or an
  explicitly specified rule? Likewise, confirm the missingness policy for new
  standalone structure fields; the combined measures currently omit entire
  source subtotals when one component is missing.
- Are MOEs/CVs/quality companions required for the intended estimates, and if
  so which ones? This audit treats the list as estimate inclusion only; existing
  companion availability is not authority to invent a requirement or formula.
- Should the flagged dollar-MOE methods, income/occupied-base weight differences,
  share-denominator differences, all-missing/zero-total MOE behavior, or related
  count/inventory missingness differences change? They are surfaced for review;
  this task neither ranks alternative rules nor tests alternative empirical
  specifications. The intended list also supplies no alternative method for
  combining source income medians.

No follow-up change in this section has been implemented.
