# Schema: `acs_step1_2024_block_group.feather`

## 1. Dataset contract

| Property | Contract |
|---|---|
| Producer | [01_import_acs.Rmd](../01_import_acs.Rmd) §4; final validation in §7. |
| Output | `${ACS_DATA_DIR}/acs_step1_2024_block_group.feather`, under the configured processed-data directory. |
| Role / status | Persisted Step 1 source extract for downstream aggregation; statewide, before geographic harmonization or analysis-sample restriction. |
| Row grain | One row per returned 2020-vintage California census block group. |
| Primary key | `bg2020_id`: unique, nonmissing character string matching `^[0-9]{12}$`; leading zeros retained. Structure: state (2) + county (3) + tract (6) + block group (1) digits. |
| Geographic scope | California (`state = "CA"`, state FIPS `06`); no county filter. |
| Temporal scope | 2020–2024 ACS 5-year estimates (`year = 2024`, `survey = "acs5"`), on 2020-vintage geography. This is one pooled period, not annual observations. |

## 2. Inputs and provenance

| Input | Source grain / key | Role |
|---|---|---|
| Census Bureau 2024 ACS 5-year detailed tables, via `tidycensus::get_acs()` | Block group × Census variable; `GEOID` + variable code | Supplies `NAME` and all estimates/MOEs. Request: `geography = "block group"`, `state = "CA"`, `year = 2024`, `survey = "acs5"`, `output = "wide"`. |
| `tract_vars` and `block_group_unavailable_vars` in `01_import_acs.Rmd` §§1.2, 2.2 | Named alias → Census code mapping | Defines `block_group_vars` and the requested columns. |
| `load_variables(2024, "acs5")` | Census variable code | Interactive lookup only; does not transform values or determine exclusions. |
| NHGIS `${ACS_RAW_DATA_DIR}/nhgis/nhgis_bg2020_tr2010_06/nhgis_bg2020_tr2010_06.csv`, prepared as `xwalk_bg24_tr10.feather` | Allocation pair: raw (`bg2020ge`, `tr2010ge`), renamed (`bg2020_id`, `tr2010_id`) | Companion input for Step 1 coverage diagnostics and downstream allocation; supplies no columns to this extract. |

The API request requires `CENSUS_API_KEY`. Geometry is not requested. A separate original B25064 E/EA/M/MA
request preserves rent evidence before tidycensus normalization. MOE confidence uses the [`get_acs()`
default](https://walker-data.com/tidycensus/reference/get_acs.html), defined in
§5. Source dollar measures use the [2024 ACS dollar
basis](https://www.census.gov/programs-surveys/acs/guidance/comparing-acs-data/2024.html).
The local dictionary below supplies each requested Census code.

## 3. Construction rules

`block_group_vars` removes exactly these aliases from `tract_vars`, preserving
retained names, Census codes, and request order:

| Excluded alias | Census code | Absent output columns |
|---|---|---|
| `rent1bdr` | B25031_003 | `rent1bdrE`, `rent1bdrM` |
| `rent2bdr` | B25031_004 | `rent2bdrE`, `rent2bdrM` |
| `rent3bdr` | B25031_005 | `rent3bdrE`, `rent3bdrM` |

Exclusions are explicit because the installed geography lookup lacks 2024
entries. B25111/B25113 measures are absent from the full request, rather than
additional block-group exclusions. Their absent estimate/MOE pairs use the
aliases `rentyrblt`, `rentyrblt_14_16`, `rentyrblt_10_13`, `rentyrblt_00_09`,
`rentyrblt_90_99`, `rentmv1yr`, and `rentmv5yr`.

The request has 62 aliases for 59 distinct Census codes. Wide output uses the
first alias for each code; these duplicate aliases add no columns:

| Request-only alias | Census code | Persisted pair |
|---|---|---|
| `grent_3` | B25063_003 | `grentcat1E`, `grentcat1M` |
| `grent_20` | B25063_020 | `grentcat18E`, `grentcat18M` |
| `grent_26` | B25063_026 | `grentcat24E`, `grentcat24M` |

- `rename_id()` renames `GEOID` to `bg2020_id` and appends logical
  `rent_id = TRUE`; `NAME` and source estimate/MOE values pass through.
- Step 1 does not filter rows, restrict the sample, aggregate, interpolate,
  adjust dollars, or derive inventory, percentages, CVs, or structure totals.
  All 24 gross-rent bins and the three vacancy-status pairs are retained.
  The retired counts `rhu_lrE` and `rhu_lr2E` are intentionally absent.

## 4. Join / allocation contract

A one-to-one original B25064 join requires identical GEOIDs and normalized
E/M, preserving every source row/value. If retrieval fails, normalized E/M
strings, missing annotations, and availability FALSE are retained with a visible
review message. No geographic allocation changes this saved table. BG→tract allocation occurs
downstream in [02a_build_measures_from_block_groups.Rmd](../02a_build_measures_from_block_groups.Rmd),
joining on `bg2020_id` to [xwalk_bg24_tr10.feather](xwalk_bg24_tr10.md).
Crosswalk allocation pairs are many-to-many; the ACS table supplies one row per
source BG. Destination IDs and allocation weights are not persisted here.

## 5. Columns

All **126 persisted columns** are listed below: two identifiers/labels, 59
estimate/MOE pairs, one flag, and five B25064 evidence fields. Rows are grouped by measure for readability;
consumers should select columns by name.

- `E` = point estimate; `M` = 90% MOE for the corresponding estimate, in the
  same units. Census codes below include the estimate/MOE suffix.
- `numeric` permits R integer or double storage under the current assertions.
- Valid-value classes: **Count** = nonnegative persons, households, or housing
  units as described; **Dollars** = nonnegative source dollar amount; **MOE** =
  nonnegative uncertainty in the estimate's units. All inherit §6 missingness
  rules. These numeric ranges describe expected values, not fail-fast checks.
- `grentcat*` estimates count cash-rent units by monthly gross rent; bin labels
  give dollar ranges, not the units of the stored count. Structure variables
  count housing units, not buildings.

| Column | Type | Source / construction | Description | Valid values / missingness |
|---|---|---|---|---|
| `bg2020_id` | character | `GEOID`, renamed | Block-group key | Key constraints in §1 |
| `NAME` | character | ACS `NAME` | Census block-group long name | Source text; missingness reported, not rejected |
| `popE` | numeric | B01003_001E | Total population | Count |
| `popM` | numeric | B01003_001M | MOE for `popE` | MOE |
| `pop_rentE` | numeric | B25008_003E | Population in renter-occupied units | Count |
| `pop_rentM` | numeric | B25008_003M | MOE for `pop_rentE` | MOE |
| `huE` | numeric | B25001_001E | Total housing units | Count |
| `huM` | numeric | B25001_001M | MOE for `huE` | MOE |
| `hhE` | numeric | B11001_001E | Total households | Count |
| `hhM` | numeric | B11001_001M | MOE for `hhE` | MOE |
| `sfd_baseE` | numeric | B25024_001E | Units in structure: total | Count |
| `sfd_baseM` | numeric | B25024_001M | MOE for `sfd_baseE` | MOE |
| `sfd_detE` | numeric | B25024_002E | Single-family detached units | Count |
| `sfd_detM` | numeric | B25024_002M | MOE for `sfd_detE` | MOE |
| `sfd_attE` | numeric | B25024_003E | Single-family attached units | Count |
| `sfd_attM` | numeric | B25024_003M | MOE for `sfd_attE` | MOE |
| `duplexE` | numeric | B25024_004E | Units in 2-unit structures | Count |
| `duplexM` | numeric | B25024_004M | MOE for `duplexE` | MOE |
| `quadplexE` | numeric | B25024_005E | Units in 3–4-unit structures | Count |
| `quadplexM` | numeric | B25024_005M | MOE for `quadplexE` | MOE |
| `mf_5_9E` | numeric | B25024_006E | Units in 5–9-unit structures | Count |
| `mf_5_9M` | numeric | B25024_006M | MOE for `mf_5_9E` | MOE |
| `mf_10_19E` | numeric | B25024_007E | Units in 10–19-unit structures | Count |
| `mf_10_19M` | numeric | B25024_007M | MOE for `mf_10_19E` | MOE |
| `mf_20_49E` | numeric | B25024_008E | Units in 20–49-unit structures | Count |
| `mf_20_49M` | numeric | B25024_008M | MOE for `mf_20_49E` | MOE |
| `mf_50E` | numeric | B25024_009E | Units in structures with 50+ units | Count |
| `mf_50M` | numeric | B25024_009M | MOE for `mf_50E` | MOE |
| `mobhmE` | numeric | B25024_010E | Mobile homes | Count |
| `mobhmM` | numeric | B25024_010M | MOE for `mobhmE` | MOE |
| `oth_unitsE` | numeric | B25024_011E | Boat, RV, van, etc. | Count |
| `oth_unitsM` | numeric | B25024_011M | MOE for `oth_unitsE` | MOE |
| `rhu_baseE` | numeric | B25003_001E | Occupied units by tenure: total | Count |
| `rhu_baseM` | numeric | B25003_001M | MOE for `rhu_baseE` | MOE |
| `rhuE` | numeric | B25003_003E | Renter-occupied housing units | Count |
| `rhuM` | numeric | B25003_003M | MOE for `rhuE` | MOE |
| `ohuE` | numeric | B25003_002E | Owner-occupied housing units | Count |
| `ohuM` | numeric | B25003_002M | MOE for `ohuE` | MOE |
| `rentE` | numeric | B25064_001E | Median monthly gross rent | Dollars |
| `rentM` | numeric | B25064_001M | MOE for `rentE` | MOE |
| `rhutotE` | numeric | B25063_001E | Gross-rent table: total renter-occupied units | Count |
| `rhutotM` | numeric | B25063_001M | MOE for `rhutotE` | MOE |
| `rhucashE` | numeric | B25063_002E | Renter units with cash rent | Count |
| `rhucashM` | numeric | B25063_002M | MOE for `rhucashE` | MOE |
| `rhunocashE` | numeric | B25063_027E | Renter units with no cash rent | Count |
| `rhunocashM` | numeric | B25063_027M | MOE for `rhunocashE` | MOE |
| `grentcat1E` | numeric | B25063_003E | Gross rent < $100 | Count |
| `grentcat1M` | numeric | B25063_003M | MOE for `grentcat1E` | MOE |
| `grentcat2E` | numeric | B25063_004E | Gross rent $100–149 | Count |
| `grentcat2M` | numeric | B25063_004M | MOE for `grentcat2E` | MOE |
| `grentcat3E` | numeric | B25063_005E | Gross rent $150–199 | Count |
| `grentcat3M` | numeric | B25063_005M | MOE for `grentcat3E` | MOE |
| `grentcat4E` | numeric | B25063_006E | Gross rent $200–249 | Count |
| `grentcat4M` | numeric | B25063_006M | MOE for `grentcat4E` | MOE |
| `grentcat5E` | numeric | B25063_007E | Gross rent $250–299 | Count |
| `grentcat5M` | numeric | B25063_007M | MOE for `grentcat5E` | MOE |
| `grentcat6E` | numeric | B25063_008E | Gross rent $300–349 | Count |
| `grentcat6M` | numeric | B25063_008M | MOE for `grentcat6E` | MOE |
| `grentcat7E` | numeric | B25063_009E | Gross rent $350–399 | Count |
| `grentcat7M` | numeric | B25063_009M | MOE for `grentcat7E` | MOE |
| `grentcat8E` | numeric | B25063_010E | Gross rent $400–449 | Count |
| `grentcat8M` | numeric | B25063_010M | MOE for `grentcat8E` | MOE |
| `grentcat9E` | numeric | B25063_011E | Gross rent $450–499 | Count |
| `grentcat9M` | numeric | B25063_011M | MOE for `grentcat9E` | MOE |
| `grentcat10E` | numeric | B25063_012E | Gross rent $500–549 | Count |
| `grentcat10M` | numeric | B25063_012M | MOE for `grentcat10E` | MOE |
| `grentcat11E` | numeric | B25063_013E | Gross rent $550–599 | Count |
| `grentcat11M` | numeric | B25063_013M | MOE for `grentcat11E` | MOE |
| `grentcat12E` | numeric | B25063_014E | Gross rent $600–649 | Count |
| `grentcat12M` | numeric | B25063_014M | MOE for `grentcat12E` | MOE |
| `grentcat13E` | numeric | B25063_015E | Gross rent $650–699 | Count |
| `grentcat13M` | numeric | B25063_015M | MOE for `grentcat13E` | MOE |
| `grentcat14E` | numeric | B25063_016E | Gross rent $700–749 | Count |
| `grentcat14M` | numeric | B25063_016M | MOE for `grentcat14E` | MOE |
| `grentcat15E` | numeric | B25063_017E | Gross rent $750–799 | Count |
| `grentcat15M` | numeric | B25063_017M | MOE for `grentcat15E` | MOE |
| `grentcat16E` | numeric | B25063_018E | Gross rent $800–899 | Count |
| `grentcat16M` | numeric | B25063_018M | MOE for `grentcat16E` | MOE |
| `grentcat17E` | numeric | B25063_019E | Gross rent $900–999 | Count |
| `grentcat17M` | numeric | B25063_019M | MOE for `grentcat17E` | MOE |
| `grentcat18E` | numeric | B25063_020E | Gross rent $1,000–1,249 | Count |
| `grentcat18M` | numeric | B25063_020M | MOE for `grentcat18E` | MOE |
| `grentcat19E` | numeric | B25063_021E | Gross rent $1,250–1,499 | Count |
| `grentcat19M` | numeric | B25063_021M | MOE for `grentcat19E` | MOE |
| `grentcat20E` | numeric | B25063_022E | Gross rent $1,500–1,999 | Count |
| `grentcat20M` | numeric | B25063_022M | MOE for `grentcat20E` | MOE |
| `grentcat21E` | numeric | B25063_023E | Gross rent $2,000–2,499 | Count |
| `grentcat21M` | numeric | B25063_023M | MOE for `grentcat21E` | MOE |
| `grentcat22E` | numeric | B25063_024E | Gross rent $2,500–2,999 | Count |
| `grentcat22M` | numeric | B25063_024M | MOE for `grentcat22E` | MOE |
| `grentcat23E` | numeric | B25063_025E | Gross rent $3,000–3,499 | Count |
| `grentcat23M` | numeric | B25063_025M | MOE for `grentcat23E` | MOE |
| `grentcat24E` | numeric | B25063_026E | Gross rent ≥ $3,500 | Count |
| `grentcat24M` | numeric | B25063_026M | MOE for `grentcat24E` | MOE |
| `med_hvalE` | numeric | B25077_001E | Median owner-occupied housing value | Dollars |
| `med_hvalM` | numeric | B25077_001M | MOE for `med_hvalE` | MOE |
| `pop_raceE` | numeric | B02001_001E | Race: total population | Count |
| `pop_raceM` | numeric | B02001_001M | MOE for `pop_raceE` | MOE |
| `pop_blkE` | numeric | B02001_003E | Black or African American alone population | Count |
| `pop_blkM` | numeric | B02001_003M | MOE for `pop_blkE` | MOE |
| `pop_aaE` | numeric | B02001_005E | Asian alone population | Count |
| `pop_aaM` | numeric | B02001_005M | MOE for `pop_aaE` | MOE |
| `pop_ethnE` | numeric | B03003_001E | Hispanic origin: total population | Count |
| `pop_ethnM` | numeric | B03003_001M | MOE for `pop_ethnE` | MOE |
| `pop_hspE` | numeric | B03003_003E | Hispanic or Latino population | Count |
| `pop_hspM` | numeric | B03003_003M | MOE for `pop_hspE` | MOE |
| `lqcrentE` | numeric | B25057_001E | Lower monthly contract rent quartile | Dollars |
| `lqcrentM` | numeric | B25057_001M | MOE for `lqcrentE` | MOE |
| `med_hhincE` | numeric | B19013_001E | Median household income | Dollars |
| `med_hhincM` | numeric | B19013_001M | MOE for `med_hhincE` | MOE |
| `tot_vac_baseE` | numeric | B25002_001E | Occupancy status: total housing units | Count |
| `tot_vac_baseM` | numeric | B25002_001M | MOE for `tot_vac_baseE` | MOE |
| `tot_vacE` | numeric | B25002_003E | Vacant housing units | Count |
| `tot_vacM` | numeric | B25002_003M | MOE for `tot_vacE` | MOE |
| `vac_forrentE` | numeric | B25004_002E | Vacant for rent | Count |
| `vac_forrentM` | numeric | B25004_002M | MOE for `vac_forrentE` | MOE |
| `vac_rentedE` | numeric | B25004_003E | Rented, not occupied | Count |
| `vac_rentedM` | numeric | B25004_003M | MOE for `vac_rentedE` | MOE |
| `vac_forsaleE` | numeric | B25004_004E | Vacant for sale only | Count |
| `vac_forsaleM` | numeric | B25004_004M | MOE for `vac_forsaleE` | MOE |
| `rent_id` | logical | `rename_id()` appends `TRUE` | ACS source-row join flag | Nonmissing; always `TRUE` |

| `rent_source_e`, `rent_source_ea`, `rent_source_m`, `rent_source_ma` | character | Original B25064_001 E/EA/M/MA request | Preserved source evidence, including sentinels and annotations | API null → NA; never inflation-adjusted; fallback E/M are normalized strings |
| `rent_evidence_available` | logical | Raw request availability | TRUE only when original E/EA/M/MA were retrieved and matched to the same-vintage extract | FALSE for normalized-E/M fallback; never missing |

## 6. Missingness and special-value rules

- **Zero is observed data**, including a zero count or MOE; it is not missing.
  Step 1 neither converts zeros to `NA` nor replaces missing values with zero.
- `tidycensus` converts ACS sentinel codes (`-111111111`, `-222222222`,
  `-333333333`, `-444444444`, `-555555555`, `-666666666`, `-777777777`,
  `-888888888`, `-999999999`) to `NA` during import. B25064 original values/annotations are retained in the five evidence fields;
  other variables retain only their normalized missingness.
- Numeric `NA` and `NaN` returned in either estimates or MOEs are preserved,
  including wholly missing measure columns. No imputation, estimate/MOE
  missingness coupling, or missingness threshold is applied.
- Finite boundary/top-coded dollar values pass through. In particular, Step 1
  does not censor rent; Step 2 distinguishes the upper `3501` code from genuine
  `3500`, while lower-quartile rent retains its `>= 3500` rule; missing or
  top-coded rent does not alter `med_hhincE`. MOEs are not rescaled or recomputed.
- Negative or infinite numeric values surviving import are retained for
  analyst review, not silently recoded or rejected by the structural checks.

## 7. Validation contract

### Fail-fast invariants

Implemented in [R/acs_input_qa.R](../R/acs_input_qa.R) and `01_import_acs.Rmd`.
Checkpoint section numbers refer to the notebook.

| Notebook checkpoint | Required condition |
|---|---|
| Request definition, §2.2 | Tract aliases unique; exclusions unique and present in the tract mapping; retained BG mapping unchanged; no B25111/B25113 requests; `vac_forrent` / `vac_rented` retain B25004_002 / B25004_003. |
| After wide extraction and before save, §4 | Nonempty table; key constraints from this contract; no duplicate column names; `NAME` character; every first-alias estimate/MOE column present and numeric. After renaming, `rent_id` has the documented type/encoding. |
| Before save and after reload, §§4.3, 7.2 | Row count equals the observed imported row count; no geographic-key duplicates. No fixed empirical row count is imposed. |
| Reloaded schema, §§7.1–7.4 | Required fields/types/flag valid; bedroom-rent pairs, B25111/B25113 pairs, and retired counts listed in construction rules absent. Raw column names beginning `B25111_` / `B25113_` are also rejected. |
| Exact readback, §7.6 | `assert_step1_readback()` requires identical row count, keys/row order, column names/order, storage types/classes, and all values, including the distinction between `NA` and `NaN`; no numeric tolerance. `assert_acs_bg_input()` runs again. |

### Analyst-review diagnostics

| Notebook diagnostic | Review expectation |
|---|---|
| Population/rent probes, §4.2 | Inspect nonmissing/missing counts, estimate mean/range, and mean MOE for `popE` / `rentE`. |
| Critical missingness and numeric summaries, §§7.3, 7.5 | Review reported missingness, all numeric means/minima/maxima, and explicit negative/infinite-value counts. Investigate implausible distributions. |
| Statewide ACS/crosswalk coverage, §6.1 | `bg_coverage_24` reports ACS-only and crosswalk-only distinct BGs separately, grouped by source state/county. Full IDs are in `$acs_only` / `$crosswalk_only`; `$crosswalk_only_links` retains unmatched links/weights. Coverage gaps do not filter this extract or establish downstream tract completeness. |

Diagnostic objects are retained in the notebook, not added to this Feather.
The companion crosswalk has its own structural/weight assertions; those are
separate from the coverage diagnostics above.

## 8. Known limitations / intentional exceptions

- Passing Step 1 validation does not establish acceptable sampling precision
  or valid downstream contributors. Required-column checks do not reject
  arbitrary extra columns; key-format checks do not independently enforce the
  California prefix.
- **Definition discrepancy:** the `rhutot` comment in `01_import_acs.Rmd` and related
  tract-schema descriptions say rent is “computed.” The requested
  [B25063_001 total](https://api.census.gov/data/2024/acs/acs5/groups/B25063.html)
  includes cash-rent and no-cash-rent units; `rhucashE` identifies the cash-rent
  subset. The dictionary follows the requested Census code.

## 9. Validation and regeneration

- **Focused validation:** from the repository root, run
  `Rscript tests/test_acs_input_qa.R`. It parses Step 1 chunks and
  exercises request-derived columns, malformed inputs, coverage cases, and
  exact temporary CSV/Feather round trips using a stubbed ACS call; it does not
  query ACS or write canonical outputs.
- **Column-dictionary audit:** compare §5 names with
  `c("bg2020_id", "NAME", acs_request_columns(block_group_vars), "rent_id", rent_evidence_columns())`
  as a set, and verify each numeric field's Census code against the first-alias
  mapping. This checks documentation completeness separately from row counts.
- **Analyst-run regeneration:** execute `01_import_acs.Rmd` with its packages, Census
  API key, and raw NHGIS inputs available. The notebook writes all five Step 1
  outputs, so handle existing outputs deliberately. Accept this extract only
  after the validation contract above is satisfied; source-input
  details for the full run are in the [README](../README.md#step-1-import-acs-data).
  Rebuild from the current request; renamed older caches do not substitute for
  this contract.
