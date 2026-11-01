# Schema: `acs_step1_2024_tract.feather`

## 1. Dataset contract

| Property | Contract |
|---|---|
| Producer | [01_import_acs.Rmd](../01_import_acs.Rmd) |
| Output | `${ACS_DATA_DIR}/acs_step1_2024_tract.feather` |
| Role / status | Source extract before county filtering, censoring, or inflation |
| Row grain | One 2020-vintage California tract |
| Primary key | `tr2020_id`: unique, nonmissing 11-digit character GEOID |
| Geographic scope | California, state FIPS 06; statewide |
| Temporal scope | 2020–2024 ACS five-year estimates, in 2024 source dollars |

## 2. Inputs and provenance

`tidycensus::get_acs(geography = "tract", state = "CA", year = 2024, survey = "acs5", output = "wide")`
uses `tract_vars` in `01_import_acs.Rmd`. A separate original Census ACS5 B25064 request
retrieves E/EA/M/MA before normalization. Requests use the configured API key;
keys are never persisted. B25064 evidence must match extract GEOIDs and normalized
E/M exactly; conflicting requests stop before saving.

## 3. Construction rules

The 65 aliases cover 62 distinct codes. Duplicate request aliases `grent_3`,
`grent_20`, and `grent_26` produce only `grentcat1`, `grentcat18`, and `grentcat24`
pairs. All three bedroom-rent pairs remain; B25111/B25113 and derived low-rent
counts are absent. Rename GEOID, add `rent_id = TRUE`, and attach rent evidence
without changing source values, row order, or membership. No inflation or
classification occurs here.

## 4. Join / allocation contract

Original B25064 evidence joins one-to-one on GEOID, requiring identical key
sets and normalized E/M. This extract is not geographically allocated.

## 5. Columns

There are 132 persisted columns: 62 estimate/MOE pairs, three identifiers/tags,
and five evidence fields. Numeric source pairs use estimate `E` and 90% MOE `M`
in the same units. Counts are persons, households, or housing units; rent is
monthly dollars and income annual dollars. Zero is observed, and missing E/M
values are independent. All columns are listed locally below.

| Column | Type | Source / construction | Description | Valid values / missingness |
|---|---|---|---|---|
| `tr2020_id` | character | Source GEOID | Tract key | See §1; nonmissing |
| `NAME` | character | Source | Census tract label | Retained |
| `rent_id` | logical | Step 1 tag | ACS source marker | Always `TRUE` |
| `popE`, `popM` | double | `B01003_001` | Total population | Source values / NA |
| `pop_rentE`, `pop_rentM` | double | `B25008_003` | Population in renter-occupied housing units | Source values / NA |
| `huE`, `huM` | double | `B25001_001` | Total housing units | Source values / NA |
| `hhE`, `hhM` | double | `B11001_001` | Total households | Source values / NA |
| `sfd_baseE`, `sfd_baseM` | double | `B25024_001` | Units in structure — total (denominator) | Source values / NA |
| `sfd_detE`, `sfd_detM` | double | `B25024_002` | 1-unit, detached | Source values / NA |
| `sfd_attE`, `sfd_attM` | double | `B25024_003` | 1-unit, attached | Source values / NA |
| `duplexE`, `duplexM` | double | `B25024_004` | 2 units | Source values / NA |
| `quadplexE`, `quadplexM` | double | `B25024_005` | 3 or 4 units | Source values / NA |
| `mf_5_9E`, `mf_5_9M` | double | `B25024_006` | 5 to 9 units | Source values / NA |
| `mf_10_19E`, `mf_10_19M` | double | `B25024_007` | 10 to 19 units | Source values / NA |
| `mf_20_49E`, `mf_20_49M` | double | `B25024_008` | 20 to 49 units | Source values / NA |
| `mf_50E`, `mf_50M` | double | `B25024_009` | 50 or more units | Source values / NA |
| `mobhmE`, `mobhmM` | double | `B25024_010` | Mobile home | Source values / NA |
| `oth_unitsE`, `oth_unitsM` | double | `B25024_011` | Boat, RV, van, etc. | Source values / NA |
| `rhu_baseE`, `rhu_baseM` | double | `B25003_001` | Occupied units by tenure — total (denominator) | Source values / NA |
| `rhuE`, `rhuM` | double | `B25003_003` | Renter-occupied housing units | Source values / NA |
| `ohuE`, `ohuM` | double | `B25003_002` | Owner-occupied housing units | Source values / NA |
| `rentE`, `rentM` | double | `B25064_001` | Median gross rent (dollars) | Source values / NA; positive interval codes retained |
| `rent1bdrE`, `rent1bdrM` | double | `B25031_003` | Median gross rent, 1 bedroom | Source values / NA |
| `rent2bdrE`, `rent2bdrM` | double | `B25031_004` | Median gross rent, 2 bedrooms | Source values / NA |
| `rent3bdrE`, `rent3bdrM` | double | `B25031_005` | Median gross rent, 3 bedrooms | Source values / NA |
| `rhutotE`, `rhutotM` | double | `B25063_001` | Renter units with gross rent computed — total | Source values / NA |
| `rhucashE`, `rhucashM` | double | `B25063_002` | With cash rent | Source values / NA |
| `rhunocashE`, `rhunocashM` | double | `B25063_027` | No cash rent | Source values / NA |
| `grentcat1E`, `grentcat1M` | double | `B25063_003` | Cash-rent units: gross rent <$100 | Source values / NA |
| `grentcat2E`, `grentcat2M` | double | `B25063_004` | Cash-rent units: gross rent $100–149 | Source values / NA |
| `grentcat3E`, `grentcat3M` | double | `B25063_005` | Cash-rent units: gross rent $150–199 | Source values / NA |
| `grentcat4E`, `grentcat4M` | double | `B25063_006` | Cash-rent units: gross rent $200–249 | Source values / NA |
| `grentcat5E`, `grentcat5M` | double | `B25063_007` | Cash-rent units: gross rent $250–299 | Source values / NA |
| `grentcat6E`, `grentcat6M` | double | `B25063_008` | Cash-rent units: gross rent $300–349 | Source values / NA |
| `grentcat7E`, `grentcat7M` | double | `B25063_009` | Cash-rent units: gross rent $350–399 | Source values / NA |
| `grentcat8E`, `grentcat8M` | double | `B25063_010` | Cash-rent units: gross rent $400–449 | Source values / NA |
| `grentcat9E`, `grentcat9M` | double | `B25063_011` | Cash-rent units: gross rent $450–499 | Source values / NA |
| `grentcat10E`, `grentcat10M` | double | `B25063_012` | Cash-rent units: gross rent $500–549 | Source values / NA |
| `grentcat11E`, `grentcat11M` | double | `B25063_013` | Cash-rent units: gross rent $550–599 | Source values / NA |
| `grentcat12E`, `grentcat12M` | double | `B25063_014` | Cash-rent units: gross rent $600–649 | Source values / NA |
| `grentcat13E`, `grentcat13M` | double | `B25063_015` | Cash-rent units: gross rent $650–699 | Source values / NA |
| `grentcat14E`, `grentcat14M` | double | `B25063_016` | Cash-rent units: gross rent $700–749 | Source values / NA |
| `grentcat15E`, `grentcat15M` | double | `B25063_017` | Cash-rent units: gross rent $750–799 | Source values / NA |
| `grentcat16E`, `grentcat16M` | double | `B25063_018` | Cash-rent units: gross rent $800–899 | Source values / NA |
| `grentcat17E`, `grentcat17M` | double | `B25063_019` | Cash-rent units: gross rent $900–999 | Source values / NA |
| `grentcat18E`, `grentcat18M` | double | `B25063_020` | Cash-rent units: gross rent $1,000–1,249 | Source values / NA |
| `grentcat19E`, `grentcat19M` | double | `B25063_021` | Cash-rent units: gross rent $1,250–1,499 | Source values / NA |
| `grentcat20E`, `grentcat20M` | double | `B25063_022` | Cash-rent units: gross rent $1,500–1,999 | Source values / NA |
| `grentcat21E`, `grentcat21M` | double | `B25063_023` | Cash-rent units: gross rent $2,000–2,499 | Source values / NA |
| `grentcat22E`, `grentcat22M` | double | `B25063_024` | Cash-rent units: gross rent $2,500–2,999 | Source values / NA |
| `grentcat23E`, `grentcat23M` | double | `B25063_025` | Cash-rent units: gross rent $3,000–3,499 | Source values / NA |
| `grentcat24E`, `grentcat24M` | double | `B25063_026` | Cash-rent units: gross rent $3,500+ | Source values / NA |
| `med_hvalE`, `med_hvalM` | double | `B25077_001` | Median house value (dollars) | Source values / NA |
| `pop_raceE`, `pop_raceM` | double | `B02001_001` | Race — total population (denominator) | Source values / NA |
| `pop_blkE`, `pop_blkM` | double | `B02001_003` | Black or African American population | Source values / NA |
| `pop_aaE`, `pop_aaM` | double | `B02001_005` | Asian population | Source values / NA |
| `pop_ethnE`, `pop_ethnM` | double | `B03003_001` | Hispanic-origin — total population (denominator) | Source values / NA |
| `pop_hspE`, `pop_hspM` | double | `B03003_003` | Hispanic or Latino population | Source values / NA |
| `lqcrentE`, `lqcrentM` | double | `B25057_001` | Lower contract rent quartile (dollars) | Source values / NA; positive interval codes retained |
| `med_hhincE`, `med_hhincM` | double | `B19013_001` | Median household income (dollars) | Source values / NA |
| `tot_vac_baseE`, `tot_vac_baseM` | double | `B25002_001` | Occupancy status — total (denominator) | Source values / NA |
| `tot_vacE`, `tot_vacM` | double | `B25002_003` | Vacant housing units | Source values / NA |
| `vac_forrentE`, `vac_forrentM` | double | `B25004_002` | Vacant units for rent (available rental units) | Source values / NA |
| `vac_rentedE`, `vac_rentedM` | double | `B25004_003` | Vacant units rented, not occupied | Source values / NA |
| `vac_forsaleE`, `vac_forsaleM` | double | `B25004_004` | Vacant units for sale only (available for-sale units) | Source values / NA |
| `rent_source_e`, `rent_source_ea`, `rent_source_m`, `rent_source_ma` | character | Original B25064_001 E/EA/M/MA request | Preserved source evidence, including sentinels and annotations | API null → NA; never inflation-adjusted; fallback E/M are normalized strings |
| `rent_evidence_available` | logical | Raw request availability | TRUE only when original E/EA/M/MA were retrieved and matched to the same-vintage extract | FALSE for normalized-E/M fallback; never missing |

## 6. Missingness and special-value rules

`tidycensus` normalizes repeated-digit negative sentinels to NA in E/M. The raw
B25064 strings retain original negative codes and EA/MA annotations. If raw
retrieval fails, E/M strings retain their normalized values, annotations are NA,
and `rent_evidence_available = FALSE`; a visible review message records the
failure. Raw `3501` denotes an upper interval, not exact rent; `3500` may be
observed. Both pass through Step 1 for source-dollar classification in Step 2.
Missing MOE alone does not identify a top-code. No source missing value is
imputed or changed to zero.

## 7. Validation contract

Keys remain unique/nonmissing, original evidence joins preserve source row order
and E/M, and source evidence uses character strings plus a nonmissing logical
availability indicator. Step 2 checks metadata/value consistency after cleaning.
Review evidence availability and numeric missingness/distributions; no empirical
counts are fixed acceptance targets.

## 8. Known limitations / intentional exceptions

Normalized legacy extracts cannot recover missing-value reasons. Rebuild with
Step 1 to obtain the original evidence; unresolved classifications persist when
evidence remains insufficient. Retained MOEs do not establish observed rent.

## 9. Validation and regeneration

Run `Rscript tests/test_rent_metadata.R` and
`Rscript tests/test_acs_input_qa.R` for synthetic checks.
Analyst-run regeneration: `01_import_acs.Rmd`, then `02b_build_measures_from_tracts.Rmd`.
See [migration and acceptance](../docs/measure_cleanup.md#rent-metadata-migration).
