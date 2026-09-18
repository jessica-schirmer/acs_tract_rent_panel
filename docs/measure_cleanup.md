# ACS measure cleanup

Implemented 2026-09-17 from `task_spec_02_cleanup.md` and the analyst's scope
clarifications: remove block-group weighted dollar estimates **except median
household income**, remove house-value-only diagnostics, keep native tract
products and existing 2016 native panel fields, and defer analysis-consumer
migration to a separate task. Canonical data files were not regenerated.

## Exact field removals

All three Step 1 outputs and both Step 2 native tract outputs lose only
`rhu_lrE` and `rhu_lr2E` in this cleanup. Step 2 also discards these fields
when reading older Step 1 caches. All source requests, including the 24
B25063 rent bins and native dollar estimate/MOE pairs, are unchanged.

The Step 2 block-group aggregate loses these 12 fields:

| Class | Removed fields |
|---|---|
| Low-rent counts | `rhu_lrE`, `rhu_lr2E` |
| Weighted gross rent and uncertainty | `rentE`, `rentM`, `rentCV` |
| Weighted lower-quartile contract rent | `lqcrentE`, `lqcrentM` |
| Weighted median house value and uncertainty | `med_hvalE`, `med_hvalM`, `med_hvalCV` |
| House-value source-missingness diagnostics | `hu_miss_hval`, `pct_miss_hval` |

There was no `lqcrentCV` output to remove. The removed estimates used
`weightedMean()` on block-group dollar estimates; they were not medians
computed from the pooled rent distribution.

The final `acs_full` panel loses these 26 fields, exactly as enumerated by
`panel_schema_removals()`:

| Class | Removed fields |
|---|---|
| Low-rent levels | `rhu_lrE_16`, `rhu_lrE_24`, `rhu_lr2E_16`, `rhu_lr2E_24` |
| Low-rent changes | `rhu_lrPOST`, `rhu_lr2POST` |
| 2024 rent/value estimates and uncertainty | `rentE_24`, `rentM_24`, `rentCV_24`, `lqcrentE_24`, `lqcrentM_24`, `med_hvalE_24`, `med_hvalM_24`, `med_hvalCV_24` |
| Dependent changes and uncertainty | `rentPOST`, `lqcrentPOST`, `moe_rentPOST`, `rentPOSTCV`, `m_flag_rentPOST` |
| House-value diagnostic | `pct_miss_hval` |
| Sole-use 2024 flags | `m_flag_rent_24`, `m_flag_lqcrent_24`, `m_flag_med_hval_24`, `zero_flag_med_hval_24`, `tc_flag_lqcrent_24`, `tc_flag_med_hval_24` |

Their `_24_bg_agg` source copies and the diagnostic weighted-rent comparison
are also removed. `diag_rentPOST_24_bg_agg` is no longer constructed.

## Retained measures and intentional references

- `med_hhincE`, `med_hhincM`, and `med_hhincCV` remain in the block-group
  product. The estimate retains household weights `hhE * wt_hh`; its MOE
  retains the existing renter weights `rhuE * wt_renthu`. Their different
  weights are unchanged. Income censoring/parity expectations and the panel
  income levels/change/MOE/CV remain intact.
- Both tract products retain native rent, lower-quartile rent, and house
  value, including uncertainty and flags. Their 2016 panel counterparts remain,
  with the existing 1.307 dollar adjustment. Source-estimate references in
  Step 1, tract paths, and native-source tests are therefore intentional.
- `interp_rent` remains native tract `rentE_24_tract` for
  `geo_consistent == 1`, and distribution-based `interp_rent_24_bg_agg` for
  every other status. Missing selected values never fall back to the other
  source. `interp_rentPOST` retains the positive, inflation-adjusted
  `rentE_16` denominator. No interpolation MOE/CV is invented.
- Source `rentE` remains necessary for `rhu_miss_rent`, `pct_miss_rent`,
  `pct_tc_rent`, `tc_flag_rent_24`, and historical income-correction
  expectations. These source-quality definitions and downstream quality rules
  are unchanged. Native `rentE_24_tract` and its diagnostic change ratio remain
  internal to Step 4 for interpolation and paired source comparisons.
- Explicit removal allowlists, obsolete-input fixtures, and negative schema
  tests intentionally name retired fields. Current schemas describe these
  names only as migration/removal entries, except when documenting retained
  native/source estimates.
- Dated audits, session logs, notes, and archived task specifications remain
  historical records. In particular, the block-group aggregation audit,
  rent-weighting/rental-unit audits, interpolation validation note, and income
  correction note describe the pre-cleanup schema where applicable. Their
  old weighted-rent/value and low-rent references are not current contracts.
  This record and the current schemas supersede those output descriptions.

## Files changed

| Area | Files |
|---|---|
| Notebooks | [01_acs.Rmd](../01_acs.Rmd), [02a_aggregate_2024_block_groups.Rmd](../02a_aggregate_2024_block_groups.Rmd), [02b_prepare_tract_sources.Rmd](../02b_prepare_tract_sources.Rmd), [04_merge.Rmd](../04_merge.Rmd) |
| Helpers | [R/helpers.R](../R/helpers.R), [R/assemble_helpers.R](../R/assemble_helpers.R), [R/geography_qa.R](../R/geography_qa.R), [R/merge_helpers.R](../R/merge_helpers.R), [R/merge_diagnostics.R](../R/merge_diagnostics.R) |
| Tests | [test_income_censoring.R](../tests/test_income_censoring.R), [test_rental_inventory.R](../tests/test_rental_inventory.R), [test_merge_diagnostics.R](../tests/test_merge_diagnostics.R) |
| Step 1 schemas | [2016 tract](../schemas/acs_step1_2016_tract.md), [2024 block group](../schemas/acs_step1_2024_block_group.md), [2024 tract](../schemas/acs_step1_2024_tract.md) |
| Step 2/panel schemas | [2016 tract](../schemas/acs_step2_2016_tract.md), [2024 block group](../schemas/acs_step2_2024_block_group.md), [2024 tract](../schemas/acs_step2_2024_tract.md), [acs_full](../schemas/acs_full.md) |
| Documentation | [README](../README.md), [shared PIPELINE](../../../PIPELINE.md), [pending hardening plan](step1_step2_bg_qa_hardening_plan.md), this cleanup record |

Existing working-tree edits and schema renames are preserved. Step 3, source
data, dependencies, and separate analysis repositories are unchanged. The
pending QA-hardening plan now refers to the reduced schema; its proposed
missingness/completeness changes have not been implemented here.

## Validation and analyst follow-up

Focused validation uses only synthetic inputs, temporary Feathers, and parsing:

```sh
Rscript --vanilla tests/test_income_censoring.R
Rscript --vanilla tests/test_rental_inventory.R
Rscript --vanilla tests/test_merge_diagnostics.R
```

All three scripts pass. Tests exercise the actual Step 1 mapping/schema chunks,
old-cache low-rent removal, retained native dollar measures, income correction,
all three migration contracts, hierarchy/no-fallback cases, and temporary
save/reload paths. Removed fields fail validation even without prior references.

A separate temporary comparison against the pre-edit code verified exact
retained column order, values, storage types, and keys for all three synthetic
Step 2 products and the hierarchical panel on identical retained inputs.
Source request mappings and the interpolation, relative-weight, source-rent
quality, censoring, and inventory helper bodies are unchanged. All R chunks
in the affected notebooks and the changed helpers/tests parse. No ACS download,
full render, or canonical output write was performed.

After analyst regeneration:

1. Preserve prior products/references, then regenerate Steps 1 and 2. Verify
   exactly the removal lists above; no unrelated column, type, key, row-count,
   allocation-weight, or retained-value change should result from this cleanup.
   Older documented source/inventory migrations and verified income corrections
   retain their existing narrow exceptions. Missing references mean parity was
   not checked.
2. Inspect Step 2 county coverage, rent-quality shares, income parity, inventory
   completeness/reconciliation, and strict save/reload checks. Confirm retained
   gross-rent bins and `interp_rent` match the corresponding pre-cleanup results
   on identical inputs. Native rent/value uncertainty must remain available.
3. Run Step 4 with `write_panel <- FALSE` using cleaned Step 2 products and the
   existing Step 3 crosswalk. Check the unchanged panel key union, exact source
   equality for every retained mapped field, unchanged 2016 native fields,
   retained income, and unchanged `interp_rent`/`interp_rentPOST`. Review the
   reduced schema before enabling the existing canonical write.
4. Complete the separate consumer migration before running analyses on the
   reduced panel. [tract_rent_acs/R/helpers.R](../../../analysis/tract_rent_acs/R/helpers.R)
   and [R/model_sample.R](../../../analysis/tract_rent_acs/R/model_sample.R)
   still require retired panel fields. Its `01_fe_rent.Rmd` and `01_fe_rhu.Rmd`
   still construct/select old rent changes and diagnostic fields. The
   [RentHub preparation notebook](../../../analysis/tract_rent_renthub/00_prep_tract_data.Rmd)
   also constructs `log_rentPOST` / `log_q1rentPOST` and selects retired fields.
   These references are intentionally deferred, not supplied with replacement
   aliases. Migrate their contracts, diagnostics, dependent summaries, and
   schemas in that follow-up; preserve active weighted-income controls.
