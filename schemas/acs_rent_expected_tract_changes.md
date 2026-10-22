# Schema: rent expected-change diagnostics

## 1. Dataset contract

| Property | Contract |
|---|---|
| Producer | [tests/report_rent_expected_changes.R](../tests/report_rent_expected_changes.R) |
| Outputs | `docs/acs_rent_expected_tract_changes.csv`; companion `docs/acs_rent_expected_change_input_manifest.csv` |
| Role / status | Expected changes pending regeneration; diagnostic only, never a canonical input or verified new model sample |
| Row grain / key | One harmonized 2010 tract; unique nonmissing character `tr2010_id`. Manifest: one inspected input per `input`. |
| Scope | Union of previously reported BG coverage changes, the five native evidence cases, and requested native boundary case `06081601501` |
| Temporal scope | Selected 2020–2024 ACS rent and existing 2012–2016 baseline quality operands; rent in 2024 dollars |

## 2. Inputs and provenance

- Existing `../../../data/acs_full.feather`: selected source/key, saved flag/rent/coverage,
  and baseline rent/CV/top-code flag. `tract_ADU_ACS_combined.feather`: common-input keys only.
  A relocated panel may be supplied explicitly, but must match both saved hashes.
  This comparison uses `acs_full_260918.feather`, byte-identical to the old panel.
- Existing Step 1 native/BG rent estimates, MOEs, cash-renter counts, and all 24
  bins; `xwalk_bg24_tr10.feather`: unchanged destination links and renter weights.
- Saved `docs/acs_rent_native_2024_evidence.csv`, coverage source/tract comparisons,
  and their input manifest from the earlier targeted checks.
- Existing downstream audit `outputs/tables/acs_rent_flags/tract_status.csv` and
  its input manifest: prior independent statuses and complete-case diagnostics.
  The audit is read, not rerun. Current helpers and the quality-rule notebook
  are fingerprinted in the new manifest.

## 3. Construction rules

`old_*` numeric values/flags describe the saved panel, reconciled to the prior
checks. **Old status is the prior independent audit assessment, not a persisted
panel field or an interpretation of its obsolete top-code flag.** It is missing
outside the audit universe. Thus the genuine native $3,500 case already has
audit status `observed` despite a saved flag of 1 and missing numeric rent.

`expected_*` rent metadata uses corrected producer helpers on only the selected
native sources and requested BG destinations. Original E/EA/M/MA resolves the
five native cases. No source fallback, bound substitution, or weight changes.
Coverage is reconstructed with the original renter denominator and corrected
BG source missingness. The allocation and selected median remain distinct.

Screen diagnostics hold current baseline rent/CV/top-code operands fixed and
apply the existing `01_fe_rent.Rmd` rule: missing baseline gives NA; otherwise
coverage > .05 sets the missingness component, CV > .12 sets the CV component,
and any known failing component or baseline top-code sets `rent_qual_flag = 1`.
Unknown operands follow that existing rule's default zero. No quintiles, full
complete-case evaluation, new common eligibility, models, or samples are run.

## 4. Join / allocation contract

Join unique source records and comparison rows by explicit keys, preserving the
target union. A selected native source uses saved `tr2020_id`; BG selection uses
`tr2010_id`. Every positive-weight BG contributor must be present. Allocate cash
and bin counts with unchanged positive `wt_renthu`, propagating incompleteness.

## 5. Columns

CSV encodes missing values as `NA`. GEOIDs must be read as character. Flags use
numeric 0/1/NA; screen flags use 1 for failure. Logical values use TRUE/FALSE/NA.

| Column | Type | Source / construction | Description | Valid values / missingness |
|---|---|---|---|---|
| `tr2010_id` | character | Target union | Harmonized tract key | 11-digit California GEOID |
| `acs_source_24` | character | Saved hierarchy | Selected 2024 source | tract / bg_agg |
| `tr2020_id` | character | Saved consistent link | Native source key | GEOID or NA |
| `comparison_group` | character | Requested case set | Reason for inclusion | native_evidence_resolution / native_3500_recovery / bg_component_coverage |
| `old_rent_status_24` | character | Prior audit | Independent pre-correction assessment | Four rent statuses, or NA outside audit |
| `old_status_basis` | character | Audit membership | Status provenance | prior_independent_audit / not_persisted_or_audited |
| `expected_rent_status_24` | character | Corrected selected source | Expected final status | observed / top_coded / unavailable_other / unresolved |
| `old_tc_flag_rent_24`, `expected_tc_flag_rent_24` | numeric | Saved panel / corrected source | Old versus expected selected-rent top-code flag | 0/1/NA; old BG flag means component exposure |
| `old_interp_rent`, `expected_interp_rent` | numeric | Saved panel / corrected source | Selected 2024 numeric rent | Monthly 2024 dollars or NA |
| `old_pct_miss_rent`, `expected_pct_miss_rent` | numeric | Old / corrected BG coverage | Component missing/censored-rent share | Fraction [0,1] or NA |
| `old_miss_rent_flag`, `expected_miss_rent_flag` | numeric | Existing coverage screen | Missingness-screen component | 0/1/NA |
| `missingness_component_changed` | logical | Component comparison | Expected component change | NA when baseline rent makes both flags unavailable |
| `high_cv_flag` | numeric | Existing baseline CV screen | Unchanged CV component | 0/1/NA |
| `old_rent_qual_flag`, `expected_rent_qual_flag` | numeric | Existing combined screen | Overall rent-quality flag, before complete cases | 0/1/NA; not final sample membership |
| `in_common_input` | logical | Current common-input keys | Currently eligible for downstream preparation | TRUE/FALSE |
| `prior_audit_full_complete_case`, `prior_audit_quality_complete_case` | logical | Prior audit | Dated old sample diagnostics | NA outside audit; never new membership |
| `expected_common_quality_screen_improvement` | logical | In current common input and combined flag 1 → 0 | Expected screen improvement holding baseline operands fixed | TRUE/FALSE; does not verify membership |
| `overall_quality_membership_change` | character | Execution limit | Verification status | Always not_verified_pending_regeneration |
| `change_reason` | character | Evidence / changed BG IDs | Explanation of each expected correction | Nonmissing |

The companion manifest lists all inspected artifacts and implementation inputs:

| Column | Type | Source / construction | Description | Valid values / missingness |
|---|---|---|---|---|
| `input` | character | Script input registry | Unique role | Nonmissing |
| `path` | character | Resolved input | Artifact location | Nonmissing |
| `md5` | character | Before/after file hash | Content fingerprint | Nonmissing |
| `modified_utc` | character | File metadata | Input modification time | UTC |
| `checked_utc` | character | Diagnostic run | Verification time | UTC |

## 6. Missingness and special-value rules

Source-unavailable native rent stays numerically missing with an unknown top-code
flag. Resolving its reason is not rent recovery. Genuine native $3,500 stays
numeric under corrected code. Missing old status outside the audit does not mean
`unresolved`; it means no historical status assessment is supplied.

## 7. Validation contract

Require unchanged hashes matching both earlier manifests; unchanged selected
source/key; agreement with saved rent/flag/coverage and audited quality flags;
exact target-key coverage; corroborated $3,500 recovery; no other numeric rent
changes in this bounded set; and CSV readback preserving IDs/types/values.
Counts of cases/screen changes are diagnostics, not fixed empirical test targets.

## 8. Known limitations / intentional exceptions

This is a bounded comparison, not a census of all corrected top-code flags.
It holds baseline quality operands fixed and does not verify any regenerated
quality-sample membership. Four reported coverage destinations may be outside
the saved audit/common universe; their old status and audit diagnostics are NA.

## 9. Validation and regeneration

Run `Rscript --vanilla tests/report_rent_expected_changes.R <new-report-directory> [preserved-panel-path]`
against the preserved pre-regeneration inputs. The script refuses to overwrite
reports or silently use changed canonical versions. It makes no API calls,
runs no notebooks, and writes only the two diagnostic CSVs. Producer and
downstream regeneration/audit remain separate analyst-run work.
