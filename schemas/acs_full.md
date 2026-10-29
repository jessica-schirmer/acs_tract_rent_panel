# Schema: `acs_full.feather`

## 1. Dataset contract

| Property | Contract |
|---|---|
| Producer | [04_assemble_tract_panel.Rmd](../04_assemble_tract_panel.Rmd), with [R/merge_helpers.R](../R/merge_helpers.R), [R/merge_diagnostics.R](../R/merge_diagnostics.R), and [R/geography_qa.R](../R/geography_qa.R). |
| Output | `../../../data/acs_full.feather`, relative to the repository root; `write_panel` controls saving and is currently `TRUE`. |
| Role / status | Canonical analysis panel: baseline and selected 2024 levels, changes, uncertainty, and provenance. Source comparisons remain notebook-only. |
| Row grain | One 2010-vintage census tract in the union of the 2016 and block-group-aggregated 2024 input keys. |
| Primary key | `tr2010_id`: unique, nonmissing character GEOID matching `^06[0-9]{9}$`; leading zeros retained. |
| Geographic scope | California destinations in the 14 counties below; no further sample restriction in Step 4. |
| Temporal scope | `_16`: 2012–2016 ACS five-year estimates; `_24`, `interp_rent`, and BG rent shares: 2020–2024. All dollar levels/MOEs are expressed in 2024 dollars. |

`step2_target_counties()` defines Southern California as Los Angeles (`037`),
Orange (`059`), Riverside (`065`), San Bernardino (`071`), and Ventura (`111`);
the Bay Area comprises Alameda (`001`), Contra Costa (`013`), Marin (`041`),
Napa (`055`), San Francisco (`075`), San Mateo (`081`), Santa Clara (`085`),
Solano (`095`), and Sonoma (`097`). State FIPS is `06`.

## 2. Inputs and provenance

All files are under `../../../data/`, relative to the repository root.

| Input | Source grain / key | Role |
|---|---|---|
| `acs_step2_2016_tract.feather` ([schema](acs_step2_2016_tract.md)) | Native 2010 tract; `tr2010_id` | Baseline ACS levels, uncertainty, flags, and panel membership. |
| `acs_step2_2024_block_group_aggregated.feather` ([schema](acs_step2_2024_block_group_aggregated.md)) | 2010 destination tract; `tr2010_id` | NHGIS-allocated 2020 block-group (BG) measurements, rent diagnostics, and panel membership. |
| `acs_step2_2024_tract.feather` ([schema](acs_step2_2024_tract.md)) | Native 2020 tract; `tr2020_id` | Census tract measurements for geographically consistent links. |
| `xwalk_tr20_tr10.feather` ([schema](xwalk_tr20_tr10.md)) | Statewide native 2020 tract; unique `tr2020_id` | Step 3 geographic status and explicit consistent 2010–2020 links. |
| Existing `acs_full.feather` (optional) | 2010 tract; `tr2010_id` | Schema reference read at setup only when saving is enabled; supplies no measurements or value-parity target. |

## 3. Construction rules

- **Hierarchy:** select the native-tract 2024 bundle only for `geo_consistent == 1`;
  select BG measurements for every other flag, including missing/unexpected
  values. This covers retained estimates, MOEs, CVs, and 2024 renter flags and rent metadata.
  Missing selected fields/records have no availability fallback. Calculate
  changes after selection.
- **Rent:** `interp_rent` uses post-censoring native tract median gross rent on
  consistent links. Elsewhere it uses upstream BG interpolation:
  `lower + (upper - lower) * (cash_rent_units / 2 - prior_cumulative) / bin_count`.
  Select the first bin reaching half the cash-rent count, with inclusive dollar
  bounds. All 24 bins and the cash-rent total must be complete and the total
  positive. Bin 24 ($3,500+) confirms top-coding; bin 1 (< $100), zero renters,
  incomplete counts, or invalid distributions yield missing rent with explicit
  unavailable/unresolved status. Exactly half reached below bin 24 is not top-coded.
- **Allocation:** copy upstream counts without rounding or renormalization.
  BG population/race/ethnicity uses `wt_pop`, housing/structure/vacancy counts
  use `wt_hu`, and renter/rent-bin counts use `wt_renthu`. BG income is an
  available-value mean of medians weighted by `hhE * wt_hh`; its MOEs instead
  use `rhuE * wt_renthu` (§8).
- **Inventory:** native sources add occupied renters, vacant-for-rent units,
  and rented-but-unoccupied units (B25003_003 + B25004_002 + B25004_003).
  BG inventory allocates each component with `wt_renthu`, so housing-weighted
  vacancy-rate components cannot reconstruct it.
- **Inflation:** multiply 2016 rent, lower-quartile contract rent, income, and
  house-value estimates/MOEs and `rent_censor_bound_16` by exactly `1.307` (documented CPI-U annual averages:
  313.689 / 240.007). The $3,500 source bound becomes $4,574.50; the 2024 bound stays $3,500. Counts, shares, flags, statuses, and CVs are unscaled.
- **Changes:** `*POST` is a 2024/positive-2016 ratio; `*PPC` is a share/rate
  difference on the 0–1 scale (`0.01` = one percentage point). Structure counts
  are levels only. Inventory, rent, and share/rate changes have no MOE/CV.

## 4. Join / allocation contract

Full-join the unique 2016 and BG inputs on `tr2010_id`, retaining one-period-only
tracts. Attach statuses, consistent links, and source bundles by left joins
with unique right keys, no missing-key matches, and unchanged panel row order
and count. Native-2020-only records never expand the panel; a baseline-only
tract can receive Census measurements through a consistent link without a BG record.

Collapse repeated status/class records only when they agree. Use explicit
consistent links even when GEOIDs differ; never infer consistency from equal
IDs or choose a dominant partner. Merge/many-to-many records omit 2010 partner
IDs, leaving some panel statuses unresolved. Missing/unrecognized flags/classes
remain visible; contradictory known combinations and invalid/ambiguous links fail.

## 5. Columns

The current inputs and producer yield **113 persisted columns**, grouped below;
select by name. `E`, `M`, and `CV` denote an estimate, its 90% margin of error,
and its coefficient of variation. `_16` levels come from the baseline; `_24`
levels follow §3. Source operands without suffixes refer to that Step 2 record,
including components not retained in this panel.

Expected domains: **Count** = nonnegative persons or housing units, with fractional
BG counts valid; **Dollars** = nonnegative amount; **Share** = unscaled fraction,
ordinarily [0, 1]; **MOE** = nonnegative uncertainty in the estimate's units;
**CV** = unscaled ratio with no upper bound. These are not universal range
assertions; missingness and exceptions are in §§6–8.

`R(n, d) = n / d` when `d > 0`, otherwise `NA`.
`D(p, m_n, m_d, d) = sqrt(pmax(0, m_n^2 - p^2 * m_d^2)) / d` when `d != 0`,
otherwise `NA`. `C(E, M) = (M / 1.645) / E`; count/share CVs guard zero
estimates, whereas dollar/change CVs do not.

### Identifiers, provenance, and join tags

| Column | Type | Source / construction | Description | Valid values / missingness |
|---|---|---|---|---|
| `tr2010_id` | character | Full-join key | Panel tract | §1 key constraints |
| `tr2020_id` | character | Explicit consistent link | Census source key; does not establish record availability | California 11-digit GEOID on flag-1 links; otherwise NA |
| `geo_consistent` | double | Crosswalk status | Geographic consistency | Expected 0/1; unresolved NA and unexpected numeric values retained |
| `relationship_class` | character | Crosswalk class | Geographic relationship | `consistent`, `one_to_one_changed`, `split`, `merge`, `many_to_many`; unresolved NA and unexpected labels retained |
| `acs_source_24` | character | Hierarchy | Assigned source, independent of availability | `tract` for flag 1; `bg_agg` otherwise; never missing |
| `rent_id` | logical | 2016 source tag | Baseline-record membership | TRUE when baseline present; otherwise NA |
| `rhu_id`, `left_id`, `right_id` | logical | BG aggregation and final interpolation-join tags | BG input provenance | TRUE when BG record present; otherwise NA |
| `base_id` | logical | Set after panel merge | Constant tag, not baseline membership | Always TRUE |
| `post_id` | logical | BG side of panel merge | BG-record membership | TRUE when BG record present; otherwise NA |

### Levels in both periods

Native count MOEs retain Census values. BG count MOEs use
`sqrt(sum((source_M * relative_weight)^2, na.rm = TRUE))`, with relative weights
equal to each source's allocated population, housing units, or renter units
divided by the corresponding target total; weighting-base counts must be
complete. All CVs use `C(E, M)`.
For share MOEs, the implemented formulas are
`pctrhuM = D(pctrhuE, rhuM, rhu_baseM, rhu_baseE)`,
`pctblkM = D(pctblkE, pop_blkM, pop_raceM, pop_raceE)`, and
`pcthspM = D(pcthspE, pop_hspM, pop_raceM, pop_raceE)` (exceptions in §8).

| Column | Type | Source / construction | Description | Valid values / missingness |
|---|---|---|---|---|
| `popE_16`, `popM_16`, `popCV_16`, `popE_24`, `popM_24`, `popCV_24` | double | B01003_001; population allocation for BG | Total population and uncertainty | Count / MOE / CV |
| `huE_16`, `huM_16`, `huCV_16`, `huE_24`, `huM_24`, `huCV_24` | double | B25001_001; housing allocation for BG | Total housing units and uncertainty | Count / MOE / CV |
| `rhuE_16`, `rhuM_16`, `rhuCV_16`, `rhuE_24`, `rhuM_24`, `rhuCV_24` | double | B25003_003; renter allocation for BG | Occupied renter units and uncertainty | Count / MOE / CV |
| `rhu_inventoryE_16`, `rhu_inventoryE_24` | double | Three-component inventory (§3) | Occupied, available, and rented/unoccupied rental units | Count; complete components required |
| `med_hhincE_16`, `med_hhincM_16`, `med_hhincCV_16`, `med_hhincE_24`, `med_hhincM_24`, `med_hhincCV_24` | double | B19013_001; BG available-value weighted means (§3) | Annual median household income, or mean of BG medians, and uncertainty | Dollars / MOE / CV; BG E requires complete household counts, M requires complete renter counts |
| `pctrhuE_16`, `pctrhuM_16`, `pctrhuCV_16`, `pctrhuE_24`, `pctrhuM_24`, `pctrhuCV_24` | double | `R(rhuE, huE)`; share-MOE formula above | Renter-occupied share of all housing units and uncertainty | Share / MOE / CV |
| `pctvacE_16`, `pctvacE_24` | double | `R(tot_vacE, tot_vac_baseE)` | Vacant share of housing units | Share |
| `pctblkE_16`, `pctblkM_16`, `pctblkCV_16`, `pctblkE_24`, `pctblkM_24`, `pctblkCV_24` | double | `R(pop_blkE, pop_raceE)`; share-MOE formula above | Black alone population share and uncertainty | Share / MOE / CV |
| `pcthspE_16`, `pcthspM_16`, `pcthspCV_16`, `pcthspE_24`, `pcthspM_24`, `pcthspCV_24` | double | `R(pop_hspE, pop_ethnE)`; share-MOE formula above | Hispanic or Latino population share and uncertainty | Share / MOE / CV |
| `pctaaE_16`, `pctaaE_24` | double | `R(pop_aaE, pop_raceE)` | Asian alone population share | Share |
| `pctsfdE_16`, `pctsfdE_24` | double | `R(sfd_detE, sfd_baseE)` | Detached single-family share of units | Share |
| `mf5E_16`, `mf5E_24` | double | `mf_5_9E + mf_10_19E + mf_20_49E + mf_50E` | Units in structures with 5+ units | Count; housing allocation for BG |
| `nsfaE_16`, `nsfaE_24` | double | `smfE + mf5E` | Attached single-family and multifamily units; excludes detached, mobile, other | Count |
| `smfE_16`, `smfE_24` | double | `sfd_attE + duplexE + quadplexE` | Attached single-family and units in 2–4-unit structures | Count; housing allocation for BG |
| `sfd_detE_16`, `sfd_detE_24` | double | B25024_002 | Detached single-family units | Count; housing allocation for BG |
| `pctrvacE_16`, `pctrvacE_24` | double | `R(vac_forrentE, rhuE + vac_forrentE)` | Rental vacancy rate; excludes rented/unoccupied units | Share |
| `pctsvacE_16`, `pctsvacE_24` | double | `R(vac_forsaleE, ohuE + vac_forsaleE)` | For-sale vacancy rate | Share |

### Baseline dollar fields and unsuffixed rent fields

| Column | Type | Source / construction | Description | Valid values / missingness |
|---|---|---|---|---|
| `rentE_16`, `rentM_16`, `rentCV_16` | double | B25064_001; E/M inflation-adjusted; `C(E, M)` unchanged | Monthly median gross rent and uncertainty | Dollars / MOE / CV; E censored upstream (§6) |
| `lqcrentE_16`, `lqcrentM_16` | double | B25057_001; E/M inflation-adjusted | Monthly lower-quartile contract rent and MOE | Dollars / MOE; E censored upstream |
| `med_hvalE_16`, `med_hvalM_16`, `med_hvalCV_16` | double | B25077_001; E/M inflation-adjusted; `C(E, M)` unchanged | Median house value and uncertainty | Dollars / MOE / CV; top-coded E retained |
| `interp_rent` | double | Selected tract median or BG interpolation (§3) | Canonical 2024 monthly gross rent | Dollars; selected-source missingness |
| `pct_miss_rent` | double | BG renter-weighted share with missing/censored corrected source median rent | Missing/censored BG rent exposure | Share; BG-only diagnostic on every row |

### Quality flags

Flags are double 0/1 when observed. Unsuffixed flags describe 2016 and are `NA`
on rows without a baseline record. The `_24` renter flags follow the selected
source; an absent selected record leaves them `NA`. Rent metadata uses the
explicit contract below, with `unresolved` for an absent selected record.

| Column | Type | Source / construction | Description | Valid values / missingness |
|---|---|---|---|---|
| `m_flag_lqcrent`, `m_flag_rhu`, `m_flag_med_hval` | double | 2016 `is.na()` of corresponding E after censoring | Baseline missing-estimate flags | 0/1 within baseline records |
| `zero_flag_rhu` | double | 2016 `rhuE == 0` | Baseline zero occupied renters | NA if estimate missing |
| `tc_flag_lqcrent` | double | Raw 2016 corresponding E >= $3,500, before inflation | Baseline lower-quartile top-code flag | NA if raw estimate missing |
| `tc_flag_med_hval` | double | Raw 2016 `med_hvalE >= 2000000`, before inflation | Baseline house-value top-code flag | NA if estimate missing |
| `m_flag_rhu_24` | double | Selected tract flag or BG `is.na(rhuE)` before joining | Missing occupied-renter estimate | 0/1 within selected records |
| `zero_flag_rhu_24` | double | Selected tract flag or BG `rhuE == 0` | Zero occupied renters | NA if estimate missing |

### Rent metadata

| Column | Type | Source / construction | Description | Valid values / missingness |
|---|---|---|---|---|
| `tc_flag_rent_16`, `tc_flag_rent_24` | double | Source-specific status before inflation; 2024 uses the rent source mapping | Confirmed upper censoring | 1 top_coded; 0 observed; NA unavailable_other/unresolved |
| `rent_status_16`, `rent_status_24` | character | Original native E/EA/M/MA or final BG distribution | Year-specific selected rent status | observed / top_coded / unavailable_other / unresolved; never NA |
| `rent_censor_bound_16` | double | Source $3,500 multiplied at Step 4 by the rent inflation parameter | Lower bound in 2024 dollars | 4574.50 at current 1.307 factor for top_coded; NA otherwise |
| `rent_censor_bound_24` | double | Selected source's $3,500 upper-interval bound | Lower bound in 2024 dollars | 3500 for top_coded; NA otherwise |

Flags/statuses/bounds describe the same selected rent. Source reason codes,
median-bin evidence, and original E/EA/M/MA remain in Steps 1/2, not this panel.

### Change measures

| Column | Type | Source / construction | Description | Valid values / missingness |
|---|---|---|---|---|
| `interp_rentPOST` | double | `R(interp_rent, rentE_16)` | Real rent ratio | Ratio; 1 = unchanged |
| `huPOST` | double | `R(huE_24, huE_16)` | Total housing-unit ratio | Ratio; 1 = unchanged |
| `rhuPOST` | double | `R(rhuE_24, rhuE_16)` | Occupied-renter ratio | Ratio; 1 = unchanged |
| `rhu_inventoryPOST` | double | `R(rhu_inventoryE_24, rhu_inventoryE_16)` | Rental-inventory ratio | Ratio; 1 = unchanged |
| `med_hhincPOST` | double | `R(med_hhincE_24, med_hhincE_16)` | Real income ratio | Ratio; 1 = unchanged |
| `popPOST` | double | `R(popE_24, popE_16)` | Population ratio | Ratio; 1 = unchanged |
| `pctrhuPPC` | double | `pctrhuE_24 - pctrhuE_16` | Renter-share change | Difference; zero shares valid |
| `pctvacPPC` | double | `pctvacE_24 - pctvacE_16` | Vacant-share change | Difference; zero shares valid |
| `pctrvacPPC` | double | `pctrvacE_24 - pctrvacE_16` | Rental-vacancy-rate change | Difference; zero rates valid |
| `pctsvacPPC` | double | `pctsvacE_24 - pctsvacE_16` | For-sale-vacancy-rate change | Difference; zero rates valid |
| `moe_rhuPOST` | double | `D(rhuPOST, rhuM_24, rhuM_16, rhuE_16)` | Occupied-renter ratio MOE | MOE; implemented subtraction formula |
| `moe_med_hhincPOST` | double | `D(med_hhincPOST, med_hhincM_24, med_hhincM_16, med_hhincE_16)` | Income ratio MOE | MOE; implemented subtraction formula |
| `rhuPOSTCV`, `med_hhincPOSTCV` | double | `C(corresponding POST, corresponding moe_*POST)` | Ratio CVs | CV; unguarded |
| `m_flag_rhuPOST`, `m_flag_rhu_inventoryPOST` | double | `is.na(corresponding POST)` | Missing-change indicators | 0/1; never missing |

## 6. Missingness and special-value rules

- Missing periods, selected records, or measurements remain missing, without
  imputation. `NA`/`NaN` count as missing for flags and hierarchy checks. Zero
  is a valid count/share; a zero numerator over a positive baseline yields zero.
  Missing/nonpositive denominators make `R` missing; differences need both periods.
- BG additive counts/inventory require all relevant positive-weight contributors.
  Missing zero-weight values have no effect; empty contributor sets yield zero.
  Incomplete counts propagate through dependent source formulas. Income means
  omit missing values/weights; complete counts do not ensure observed income.
- Native gross rent uses the verified `3501` upper code/annotation. Genuine
  `3500` survives with finite MOE and complete non-top distribution evidence.
  Known source unavailability/lower interval gives `unavailable_other`; missing
  or conflicting classification evidence gives `unresolved`. Only `observed`
  status permits numeric rent; confirmed top-codes never enter numeric change.
  MOEs remain independent. Lower-quartile rent still uses `>= 3500`, and house
  values retain their $2,000,000 flag without censoring. Income remains independent.
- BG component coverage `pct_miss_rent` has unchanged weights/denominator but
  corrected source classification: genuine $3,500 estimates are no longer
  missing and source interval codes are unavailable. It remains BG coverage
  even on native-selected rows. Missing BG records, incomplete renter counts,
  or nonpositive totals yield NA. It never classifies the selected tract rent.
- `tc_flag_rent`, `m_flag_rent`, and `pct_tc_rent` are removed. Consumer migration
  is documented in [README](../README.md#rent-metadata-migration).
- Missing inputs propagate through change/share-MOE formulas; negative radicands
  are clamped to zero. Count/share CVs are missing at zero estimates; unguarded
  dollar/change CVs can be `Inf`/`NaN`. BG count MOEs omit missing products, so
  all-missing source MOEs can yield zero when weighting-base counts are complete
  and positive; zero-base `popM`, `huM`, and `rhuM` are missing. There is no general
  nonfinite-value cleanup.

## 7. Validation contract

Section references in these tables refer to `04_assemble_tract_panel.Rmd`.

### Fail-fast invariants

| Checkpoint | Required condition |
|---|---|
| Inputs, §2 | Unique nonmissing California tract keys; required fields present and cleanup exclusions respected. Rent/interpolation, occupied renters, inventory, `smfE`, and `sfd_detE` numeric and finite/nonnegative when observed. Numeric fields numeric; statuses character. Exactly 14 baseline counties; both 2024 inputs match that set. |
| Geography/joins, §§2.4–3.2 | Valid crosswalk storage, partner counts, retained IDs, and known flag/class combinations; consistent links unique on both keys. Preserve the input-key union, panel row order, and row count. |
| Hierarchy, §§3.2, 4.2, 7 | Every row has the correct source label. All mapped fields match selected-source observed values exactly and preserve numeric missingness (`NA`/`NaN` equivalent), with absent source status explicitly unresolved; no observed BG values lost on rows not flagged consistent. |
| Changes/diagnostics, §7 | Occupied-renter/inventory changes agree with selected diagnostic ratios; rent change equals the canonical positive-baseline ratio with tolerance zero. Diagnostic work preserves every canonical column/value; valid rent status/flag/bound/value combinations and no confirmed top-codes in numeric rent changes. |
| Schema, §§7, 7.5 | `panel_schema_additions()` fields present with checked types; `panel_schema_removals()` fields absent; no duplicate column names. Selected 2024 quality flags and inventory-change missing flag double 0/1/NA. Prior-panel comparisons permit only those fixed additions/removals, with exact shared column order/types/classes. |
| Saved output, §7.5 | Recheck input-key union/counties and exact column order/types/classes against memory. Values use `isTRUE(all.equal(acs_saved, acs_full))` with default numeric tolerance; prior output values are not compared. |

### Analyst-review diagnostics

| Diagnostic | Review expectation |
|---|---|
| Panel membership and geographic coverage/unmatched tables | Distinguish one-period-only rows, unresolved/unrecognized statuses, absent links, absent records, and missing estimates. Panel class counts cannot recover omitted multi-partner links. |
| Source-selection counts/missingness and `hierarchy_equality` | Review full assigned-source denominators and selected missing values with observed alternatives; source assignment must be complete. |
| Source level/change comparisons, §5 | Compare rent/inventory on consistent links, retaining missing records/baselines in coverage denominators. |
| Inventory comparisons, §6 | Inspect inventory below occupied renters and differing changes; native-input and consistent-subset denominators differ. |
| CV, flag, missingness, and numeric summaries, §§3.4, 7.2–7.4 | Review uncertainty, all flag encodings, structure levels, nonfinite values, negative counts, out-of-range shares, and implausible ratios. No fixed empirical row count or missingness threshold. |

## 8. Known limitations / intentional exceptions

- Changes can compare differently constructed rent or income measures (§3);
  geographic consistency does not ensure measurement precision.
- **Upstream uncertainty mismatches:** BG income uses household weights for
  estimates and renter weights for MOEs. `pctrhuM` uses occupied-unit totals
  (`rhu_baseE/M`) while `pctrhuE` uses all housing units; `pcthspM` uses race-table
  totals while `pcthspE` uses Hispanic-origin totals. Step 4 retains these formulas.
- The 113-column dictionary describes current inputs. `select_vars()` also
  retains input names ending in `id` or the survey suffix; schema validation
  is not an exhaustive whitelist without a prior reference. Missing references
  leave the prior-schema comparison unchecked.

## 9. Validation and regeneration

- **Focused validation:** existing `Rscript --vanilla tests/test_merge_diagnostics.R`
  covers synthetic bundles, geography, changes, schema guards, and temporary
  Feather writes/readback; it does not regenerate canonical data.
- **Documentation/column audit:** compare §5 with `merge_measure_columns()`,
  notebook `var_list` selections, input join tags, `panel_schema_additions()`,
  and both change helpers. Check template headings, local links, notebook/helper
  parsing, and `git diff --check` without reading data.
- **Analyst-run regeneration:** run `04_assemble_tract_panel.Rmd` from setup through §7 with
  current Step 2 products, the Step 3 crosswalk, and `write_panel <- FALSE` for
  in-memory review. Set it to `TRUE` and rerun from setup to save; §7.5 announces
  replacement, checks any prior schema, writes, and reloads the output. Review
  the diagnostics above.
