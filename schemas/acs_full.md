# Schema: `acs_full.feather`

**Produced by:** `04_merge.Rmd` (Step 4, optional write). **Sources:**
`acs_step2_2016_tract.feather`, `acs_step2_2024_block_group_aggregated.feather`,
`acs_step2_2024_tract.feather`, and `xwalk_tr20_tr10.feather` under `../../../data/`.

Step 4 consumes the current filenames; preserved legacy files are not refreshed
or used as substitutes. All overlapping panel estimates, MOEs, CVs, and quality
flags follow the geographic hierarchy before canonical changes are calculated.
Source-comparison columns and diagnostic changes stay outside this output.

`write_panel <- FALSE` is the notebook default. Validation uses the in-memory
panel; writing and reloading require explicit enablement. Enabled writes retain
the fixed schema migration below, announced replacement, and saved-value checks.
See the [Step 4 diagnostic workflow](../README.md#step-4-create-acs-panel-and-compare-revised-measurement-sources).

**Grain:** one row per 2010-vintage tract in the five Southern California plus
nine Bay Area counties configured in [02_assemble.Rmd](../02_assemble.Rmd) §1.3
(the union of the 2016 and block-group-aggregated 2024 `tr2010_id` keys).
**Key:** `tr2010_id` (unique, non-missing).

This is the analysis panel: 2012–2016 and 2020–2024 tract measures side by side,
with the 2016 dollar values inflation-adjusted to 2024 dollars, plus
period-change ("POST") ratios.

## Geographic hierarchy and provenance

| column | R storage type | definition |
|---|---|---|
| `geo_consistent` | double | Upstream 0/1 flag attached on available 2010 links; unresolved links remain `NA`. Unexpected numeric values are retained and reported, never recoded to 0/1. |
| `relationship_class` | character | Available upstream `consistent`, `one_to_one_changed`, `split`, `merge`, or `many_to_many` class; unresolved links are `NA`. Unexpected labels remain visible in QA. |
| `tr2020_id` | character | Explicit 11-digit Census source key on a consistent link, including different-GEOID pairs; otherwise `NA`. A linked key can lack a Census input record. |
| `acs_source_24` | character | `"tract"` for `geo_consistent == 1`, `"bg_agg"` for `geo_consistent == 0`, otherwise `NA`. Assignment is independent of measurement availability. |

Only agreeing repeated status/class records are collapsed; no dominant partner
or equal-GEOID inference is used. Omitted merge/many-to-many 2010 partner IDs
cannot be reconstructed from this crosswalk. All original panel rows remain.
Missing/unrecognized geographic flags leave every hierarchy-controlled 2024
field and its canonical changes missing. An unknown class label is reported
without overriding a valid geographic flag; contradictory known flag/class
combinations and invalid/ambiguous links fail validation.

**No availability fallback:** a missing estimate, MOE, CV, flag, or source
record stays missing when that source is selected, even if its alternative is
observed. The whole selected upstream bundle is retained, including an observed
MOE accompanying a censored estimate. A 2016-only member of the original key
union can receive Census values and changes through a consistent link even
without a block-group record. Native-2020-only tracts never enlarge the panel.

## Year-suffixed level measures

The analytic measures from each survey carry a `_16` (2012–2016) or `_24`
(2020–2024) suffix. For each survey the following appear (see
the [2016](acs_step2_16.md), [2024 aggregate](acs_step2_24.md), and
[2024 tract](acs_step2_2024_tract.md) schemas for definitions). These measures
are numeric doubles, with missingness inherited from the selected source:

- **Estimates `_{yr}`:** `rentE`, `lqcrentE`, `popE`, `huE`, `rhuE`, `med_hvalE`,
  `rhu_lrE`, `rhu_lr2E`, `med_hhincE`, `pctrhuE`, `pctvacE`, `pctblkE`, `pcthspE`,
  `pctaaE`, `pctsfdE`, `mf5E`, `nsfaE`, `pctrvacE`, `pctsvacE`, `rhu_inventoryE`.
  (`mf5E` = units in 5+ structures, renamed from `mfE`; `nsfaE` =
  non-single-family attached count; `pctrvacE` / `pctsvacE` = rental / for-sale
  vacancy rates. These carry no MOE/CV column.)
- **Margins of error `_{yr}`:** `rentM`, `lqcrentM`, `popM`, `huM`, `rhuM`,
  `med_hvalM`, `med_hhincM`, `pctrhuM`, `pctblkM`, `pcthspM`.
- **Coefficients of variation `_{yr}`:** `rentCV`, `popCV`, `huCV`, `rhuCV`,
  `med_hvalCV`, `med_hhincCV`, `pctrhuCV`, `pctblkCV`, `pcthspCV`.

**Inflation adjustment:** the 2016 dollar estimates/MOEs (`rentE_16`,
`lqcrentE_16`, `med_hhincE_16`, `med_hvalE_16`, and the `*M_16` counterparts) are
multiplied by **1.307** to express them in 2024 dollars. The factor uses CPI-U
annual averages (BLS, CPI-U, U.S. city average, all items): 313.689 (2024) /
240.007 (2016) ≈ 1.307.

**Inventory is distinct from occupied renter units.** `rhu_inventoryE_16` and
`rhu_inventoryE_24` include renter-occupied units, vacant for rent, and rented,
not occupied units. They use the saved upstream inventory estimate directly;
the aggregate inventory cannot be reconstructed from its housing-weighted
vacancy-rate components. Counts receive no inflation adjustment. Inventory has
no MOE/CV. `rhuE_16`/`rhuE_24` remain occupied-renter counts.

## Extra carried columns

| column | source | description |
|---|---|---|
| `interp_rent` | 2024 block-group aggregate | Interpolated median rent (not suffixed); source-specific alternative. |
| `pct_miss_rent`, `pct_miss_hval` | 2024 block-group aggregate | Share of weighted units missing rent / value. Rent includes censored top-coded block groups; see `pct_tc_rent`. |
| `pct_tc_rent` | 2024 block-group aggregate | Share of weighted renter units whose rent is top-coded; the top-coded portion of `pct_miss_rent`. |
| `m_flag_rent`, `m_flag_lqcrent`, `m_flag_rhu`, `m_flag_med_hval` | 2016 | Missing-value flags (0/1). |
| `zero_flag_rhu` | 2016 | Zero renter-units flag (0/1). |
| `tc_flag_rent`, `tc_flag_lqcrent`, `tc_flag_med_hval` | 2016 | Top-code flags (0/1). |

The analyst chose to preserve these block-group companions' existing names and
values on all panel rows, including Census-selected and unresolved rows. They
describe the aggregate source, not quality of the selected Census estimate;
downstream quality-classification rules remain unchanged. `interp_rentPOST`
remains the corresponding block-group-specific alternative change. Neither
interpolated rent nor its CV is supplied by the tract product; no CV is created.

### Canonical 2024 quality fields

All fields below use double 0/1/NA storage and follow the selected source.
Missing source records and unassigned sources leave these flags missing.

| columns | definition |
|---|---|
| `m_flag_rent_24`, `m_flag_lqcrent_24`, `m_flag_rhu_24`, `m_flag_med_hval_24` | Tract source: corresponding upstream missing flags. Aggregate source: `is.na()` of its estimate, calculated before joining. |
| `zero_flag_rhu_24`, `zero_flag_med_hval_24` | Tract source: upstream zero flags. Aggregate source: its estimate equals zero, with `NA` for missing estimates. |
| `tc_flag_rent_24` | Tract source: upstream `tc_flag_rent` (tract median meets the censoring threshold). Aggregate source: upstream `tc_flag_rent_24` (a positively renter-weighted contributing block group was top-coded). The aggregate can still have observed rent. |
| `tc_flag_lqcrent_24`, `tc_flag_med_hval_24` | Upstream tract flags for Census-selected rows; `NA` for aggregate-selected rows because no equivalent flags are supplied. Never inferred from an aggregated estimate. |

## Change measures

**Level changes (ratios, `*POST`).** Dollar- and count-denominated measures use
the ratio of the 2024 value to the inflation-adjusted 2016 value, defined only
where the 2016 denominator is positive (else `NA`).

| column | definition |
|---|---|
| `rentPOST` | `rentE_24 / rentE_16` |
| `interp_rentPOST` | `interp_rent / rentE_16` |
| `lqcrentPOST` | `lqcrentE_24 / lqcrentE_16` |
| `huPOST` | `huE_24 / huE_16` |
| `rhuPOST` | `rhuE_24 / rhuE_16` |
| `rhu_inventoryPOST` | `rhu_inventoryE_24 / rhu_inventoryE_16`; separate inventory change, not occupied-renter change |
| `rhu_lrPOST`, `rhu_lr2POST` | low-rent renter-unit change ratios |
| `med_hhincPOST` | `med_hhincE_24 / med_hhincE_16` |
| `popPOST` | `popE_24 / popE_16` |

**Share / rate changes (percentage-point differences, `*PPC`).** Share and rate
measures use `value_24 − value_16` (range ≈ [−1, 1]), defined wherever both
periods are present (`NA` only if a period is missing).

| column | definition |
|---|---|
| `pctrhuPPC` | `pctrhuE_24 − pctrhuE_16` (renter-occupied share) |
| `pctvacPPC` | `pctvacE_24 − pctvacE_16` (overall vacant share) |
| `pctrvacPPC` | `pctrvacE_24 − pctrvacE_16` (rental vacancy rate) |
| `pctsvacPPC` | `pctsvacE_24 − pctsvacE_16` (for-sale vacancy rate) |

**Change-measure MOE/CV:** `moe_rentPOST`, `moe_rhuPOST`, `moe_med_hhincPOST`
(ratio-MOE propagation) and `rentPOSTCV`, `rhuPOSTCV`, `med_hhincPOSTCV`.

These calculations consume the canonical selected 2024 fields. Existing
uncertainty formulas and upstream MOEs remain unchanged; the documented upstream
dollar-MOE discrepancy is a separate research decision. Missing selected
estimates or uncertainty propagate through the change calculations.

**Change flags (double 0/1):** `m_flag_rentPOST`, `m_flag_rhuPOST`,
`m_flag_rhu_inventoryPOST`; 1 exactly when the corresponding change is missing.
No inventory change MOE/CV is added.

## Join-indicator columns

| column | type | description |
|---|---|---|
| `base_id` | logical | Constant `TRUE` (set after the merge). |
| `post_id` | logical | `TRUE` if present in the block-group-aggregated 2024 input, else `NA`; does not determine selected-source availability. |
| `rent_id`, `rhu_id`, `left_id`, `right_id` | logical | Existing upstream join tags carried from the 2016/block-group inputs. |

One-period-only membership is audited in `04_merge.Rmd` against the original
2016/2024 input keys, independently of `base_id`. The audit stays in notebook
diagnostics and adds no output columns.

## Schema migration and validation

`panel_schema_additions()` allows only inventory's two levels, ratio and missing
flag; the four geographic/provenance columns; and the eight newly added 2024
quality flags above (`tc_flag_rent_24` already existed). No old columns are
removed; shared columns retain their order and storage types. New fields are
required and type-checked even without a prior reference. Observed estimate
values may change under the hierarchy; the prior file is a schema reference,
not a value-parity target. Save/reload column order/types and values stay strict.

Notebook QA reports source counts/shares, missing/unrecognized status counts,
canonical missingness by source, and exact equality to each selected bundle.
Median rent and inventory explicitly report selected missing values with an
observed alternative. Task 1 comparisons retain their original source-specific
denominators. Full execution and output regeneration remain analyst-run work;
synthetic tests exercise the notebook with temporary inputs and output only.
