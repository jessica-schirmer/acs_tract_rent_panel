# Schema: `acs_step2_2024_tract.feather`

## 1. Dataset contract

| Property | Contract |
|---|---|
| Producer | [02b_build_measures_from_tracts.Rmd](../02b_build_measures_from_tracts.Rmd) §3; readback validation in §4. |
| Output | `${ACS_DATA_DIR}/acs_step2_2024_tract.feather`, under the configured processed-data directory. |
| Role / status | Native tract source for Step 4: canonical measurements on explicit `geo_consistent == 1` links, including different-GEOID pairs; source diagnostics otherwise. Selected missing values have no fallback to block-group aggregates. See the [panel contract](acs_full.md). |
| Row grain | One native 2020-vintage California census tract. |
| Primary key | `tr2020_id`: unique, nonmissing character GEOID matching `^06[0-9]{9}$`. |
| Geographic scope | All input tracts in the 14 target counties below. |
| Temporal scope | 2020–2024 ACS five-year estimates; dollar measures in 2024 dollars. |

`step2_target_counties()` in [R/geography_qa.R](../R/geography_qa.R) defines
Southern California: Los Angeles (`037`), Orange (`059`), Riverside (`065`),
San Bernardino (`071`), Ventura (`111`); Bay Area: Alameda (`001`), Contra Costa
(`013`), Marin (`041`), Napa (`055`), San Francisco (`075`), San Mateo (`081`),
Santa Clara (`085`), Solano (`095`), Sonoma (`097`). State FIPS is `06`.

## 2. Inputs and provenance

| Input | Source grain / key | Role |
|---|---|---|
| `${ACS_DATA_DIR}/acs_step1_2024_tract.feather` ([schema](acs_step1_2024_tract.md)) | Statewide native 2020 tract; `tr2020_id` | ACS estimates/MOEs downloaded by `01_import_acs.Rmd` using `tidycensus::get_acs`, California, year 2024, five-year survey. |
| `${ACS_DATA_DIR}/parity_reference/acs_step2_2024_tract.feather` (optional) | Native 2020 tract; `tr2020_id` | Preserved Southern California comparison only; supplies no measurements. |

## 3. Construction rules

- Filter by state/county substrings of `tr2020_id`; preserve native geography,
  source column order/types, and selected row order. No aggregation or weighting
  changes source measurements.
- Classify original B25064 evidence before inflation: `3501` or a supported
  upper annotation gives top-coding, with a $3,500 source-dollar bound. Genuine
  `3500` requires a finite MOE and a complete non-top distribution and remains
  observed. Only `observed` rent enters numeric `rentE`.
  Keep lower-quartile censoring at `>= 3500`. Flag `med_hvalE >= 2000000` without censoring it. Create missing flags after
  censoring; bedroom rents and all source MOEs pass through unchanged.
- Preserve income estimates/MOEs independently of rent availability, with no
  income threshold. Derive structures, shares, CVs, and inventory as listed below
  using [R/assemble_helpers.R](../R/assemble_helpers.R).
- The source request has 65 aliases for 62 distinct Census codes. Duplicate
  aliases `grent_3`, `grent_20`, and `grent_26` produce only the first-alias pairs
  `grentcat1`, `grentcat18`, and `grentcat24`.
- Discard `rhu_lrE` and `rhu_lr2E` if present in an older input. B25111/B25113
  fields are absent from the current input mapping.

## 4. Join / allocation contract

No geographic crosswalk is used. Each tract contributes once, with unit weight,
to `rhu_inventoryE`. Join only that estimate from the keyed inventory diagnostics
back to the production table, one-to-one on `tr2020_id`, preserving existing rows
and columns. Component totals and completeness/contributor diagnostics remain
in memory and are not persisted here.

## 5. Columns

The current input contract yields **170 columns**: 124 source estimate/MOE
columns, three identifiers/tags, five evidence fields, and 38 derived fields. Source pairs below list
both persisted names: `E` is the estimate and `M` the 90% margin of error.
Source measures are numeric doubles; counts are persons, households, or housing
units as indicated, and dollar estimates are monthly rents, annual household
income, or house value. Source `NA` is allowed. Unless stated otherwise, source
pairs retain their values; nonnegative finite values are expected but are only
asserted for the inventory estimates (see §7).

### Identifiers and source pairs

| Column | Type | Source / construction | Description | Valid values / missingness |
|---|---|---|---|---|
| `tr2020_id` | character | Source GEOID | Native tract key | See §1; nonmissing |
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
| `rentE`, `rentM` | double | `B25064_001` | Median gross rent (dollars) | E observed through 3500 or NA; M retained |
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
| `lqcrentE`, `lqcrentM` | double | `B25057_001` | Lower contract rent quartile (dollars) | E < 3500 or NA after censoring; M retained |
| `med_hhincE`, `med_hhincM` | double | `B19013_001` | Median household income (dollars) | Source values / NA |
| `tot_vac_baseE`, `tot_vac_baseM` | double | `B25002_001` | Occupancy status — total (denominator) | Source values / NA |
| `tot_vacE`, `tot_vacM` | double | `B25002_003` | Vacant housing units | Source values / NA |
| `vac_forrentE`, `vac_forrentM` | double | `B25004_002` | Vacant units for rent (available rental units) | Source values / NA |
| `vac_rentedE`, `vac_rentedM` | double | `B25004_003` | Vacant units rented, not occupied | Source values / NA |
| `vac_forsaleE`, `vac_forsaleM` | double | `B25004_004` | Vacant units for sale only (available for-sale units) | Source values / NA |

| `rent_source_e`, `rent_source_ea`, `rent_source_m`, `rent_source_ma` | character | Original B25064_001 E/EA/M/MA request | Preserved source evidence, including sentinels and annotations | API null → NA; never inflation-adjusted; fallback E/M are normalized strings |
| `rent_evidence_available` | logical | Raw request availability | TRUE only when original E/EA/M/MA were retrieved and matched to the same-vintage extract | FALSE for normalized-E/M fallback; never missing |

### Added measures and flags

All added fields are numeric doubles. `R(n, d)` means `n / d` when `d > 0`,
otherwise `NA`. `Q(p, m, d, b)` means
`sqrt(pmax(0, m^2 - p^2 * b^2)) / d` when `d != 0`, otherwise `NA`.
`C(E, M)` means `(M / 1.645) / E`; guarded CVs return `NA` when `E == 0`.
These definitions propagate missing inputs; dollar CVs are unguarded (§6).

| Column | Type | Source / construction | Description | Valid values / missingness |
|---|---|---|---|---|
| `mf5E` | double | `mf_5_9E + mf_10_19E + mf_20_49E + mf_50E` | Units in structures with 5+ units | NA if any component missing |
| `smfE` | double | `sfd_attE + duplexE + quadplexE` | Attached single-family and 2–4-unit structures | NA if any component missing |
| `nsfaE` | double | `smfE + mf5E` | Attached/multifamily units; excludes detached, mobile, other | NA if either component missing |
| `pctrhuE` | double | `R(rhuE, huE)` | Renter-occupied share of all housing units | Fraction; denominator rule above |
| `pctvacE` | double | `R(tot_vacE, tot_vac_baseE)` | Vacant share of housing units | Fraction; denominator rule above |
| `pctblkE` | double | `R(pop_blkE, pop_raceE)` | Black population share | Fraction; denominator rule above |
| `pcthspE` | double | `R(pop_hspE, pop_ethnE)` | Hispanic population share | Fraction; denominator rule above |
| `pctaaE` | double | `R(pop_aaE, pop_raceE)` | Asian population share | Fraction; denominator rule above |
| `pctsfdE` | double | `R(sfd_detE, sfd_baseE)` | Detached single-family share | Fraction; denominator rule above |
| `pctrvacE` | double | `R(vac_forrentE, rhuE + vac_forrentE)` | Rental vacancy rate; excludes rented/unoccupied units | NA or finite [0, 1] |
| `pctsvacE` | double | `R(vac_forsaleE, ohuE + vac_forsaleE)` | For-sale vacancy rate | NA or finite [0, 1] |
| `pctrhuM` | double | `Q(pctrhuE, rhuM, rhu_baseE, rhu_baseM)` | Renter-share MOE as implemented | Zero denominator → NA; see §8 |
| `pctblkM` | double | `Q(pctblkE, pop_blkM, pop_raceE, pop_raceM)` | Black-share MOE | Zero denominator → NA |
| `pcthspM` | double | `Q(pcthspE, pop_hspM, pop_raceE, pop_raceM)` | Hispanic-share MOE as implemented | Zero denominator → NA; see §8 |
| `rentCV` | double | `C(rentE, rentM)` | Median gross-rent CV | Unguarded; censored rent → NA |
| `med_hhincCV` | double | `C(med_hhincE, med_hhincM)` | Median income CV | Unguarded |
| `med_hvalCV` | double | `C(med_hvalE, med_hvalM)` | Median house-value CV | Unguarded |
| `pctrhuCV` | double | Guarded `C(pctrhuE, pctrhuM)` | Renter-share CV | Zero estimate → NA |
| `pctblkCV` | double | Guarded `C(pctblkE, pctblkM)` | Black-share CV | Zero estimate → NA |
| `pcthspCV` | double | Guarded `C(pcthspE, pcthspM)` | Hispanic-share CV | Zero estimate → NA |
| `rhuCV` | double | Guarded `C(rhuE, rhuM)` | Renter-occupied-unit CV | Zero estimate → NA |
| `huCV` | double | Guarded `C(huE, huM)` | Housing-unit CV | Zero estimate → NA |
| `popCV` | double | Guarded `C(popE, popM)` | Population CV | Zero estimate → NA |
| `rhu_inventoryE` | double | `rhuE + vac_forrentE + vac_rentedE` | Occupied plus available and rented/unoccupied rental units | Finite nonnegative or NA; complete components required |
| `tc_flag_lqcrent` | double | Raw lower-quartile E >= 3500 | Lower-quartile top-code indicator | 0/1; NA for missing raw E |
| `tc_flag_rent_24` | double | Original B25064 evidence | Confirmed upper censoring | 1 top-coded; 0 observed; NA otherwise |
| `rent_status_24` | character | Source evidence classification | Selected native rent availability | observed / top_coded / unavailable_other / unresolved; never NA |
| `rent_censor_bound_24` | double | Confirmed upper interval | Lower censoring bound in 2024 dollars | 3500 only for top_coded; NA otherwise |
| `rent_status_reason` | character | Classifier reason | Detailed source/encoding/conflict explanation | Nonmissing reason code |
| `rent_median_bin` | integer | Complete B25063 distribution | Supporting median-bin evidence, never a replacement native rent | 1–24 or NA |
| `tc_flag_med_hval` | double | `med_hvalE >= 2000000` | House-value top-code indicator | 0/1; NA for missing E |
| `m_flag_lqcrent`, `m_flag_rhu`, `m_flag_rhucash`, `m_flag_med_hval` | double | `is.na()` of corresponding E after censoring | Missing-estimate indicators | 0/1; never NA |
| `zero_flag_rhu`, `zero_flag_rhucash`, `zero_flag_med_hval` | double | Corresponding E == 0 | Zero-estimate indicators | 0/1; NA for missing E |

## 6. Missingness and special-value rules

- Zero is a valid count. Inventory is zero when all three components are zero;
  any component `NA`/`NaN` makes inventory `NA`. Missing rent, income, or component
  MOEs does not make inventory incomplete. No imputation or partial subtotal.
- Structures use ordinary addition, preserving missingness. Shares use positive
  denominators and are fractions, not percentages. Missing numerators propagate.
- Share MOEs clamp a negative radicand to zero; missing inputs remain missing.
  Their denominator guard is `!= 0`, not `> 0`. Guarded count/share CVs are
  missing for zero or missing estimates. Dollar CVs can be `Inf`/`NaN` at zero
  estimates; the producer does not replace them.
- `top_coded` means confirmed upper code/annotation; its numeric rent is NA.
  Known unavailable source codes/annotations (`-666666666` / `-`, `-999999999` /
  `N`, `-888888888` / `(X)`) and lower interval `99` give `unavailable_other`.
  Missing original evidence, unexplained boundary values, or conflicting source
  estimate/annotation/distribution evidence give `unresolved`. Missing E or M
  alone never creates a top-code. Ordinary numeric E can be observed without M.
- Numeric rent is NA for every status except `observed`; an observed MOE may
  remain beside missing rent. `rent_status_reason` records numeric/boundary,
  upper/lower interval, source unavailable, insufficient-evidence, or conflict
  reasons. `rent_median_bin` uses complete consistent counts and first cumulative
  count >= half; it is supporting evidence only.
- `tc_flag_rent` and `m_flag_rent` are removed. Unrelated flags retain their rules.
  Raw B25064 strings are never altered by censoring or downstream inflation.

## 7. Validation contract

### Fail-fast invariants

| Checkpoint | Required condition |
|---|---|
| Input and geography | Unique nonmissing statewide key; character California GEOIDs; bedroom-rent pairs, `vac_rentedE/M`, and `rent_id` present. Selected key membership preserved; all 14 and only target counties represented. |
| Inventory construction/join | Three component estimate/MOE pairs numeric; observed estimates finite and nonnegative. One-to-one join preserves every existing column and row. |
| Inventory before save/readback | Missingness matches keyed completeness diagnostics; complete inventories equal component sums and diagnostic estimates within `1e-10`. Source-first and target-first totals reconcile over complete targets only. |
| Income | Source `med_hhincE/M` unchanged, including missingness; CV equals source-based formula within `1e-10`, independent of parity-reference availability. |
| Optional parity | Southern California keys and shared values match the reference (numeric tolerance `1e-10`); shared column order/types match. Only documented rent evidence/metadata additions and retired flags/low-rent removals are allowed. Shared rent/CV changes must match both source-derived old and corrected values; no unrelated income/allocation exceptions. Missing reference means **parity not checked**. |
| Saved output | Exact in-memory/readback equality of rows, values, column order/types; retired low-rent fields absent even without parity. Numeric flags 0/1 or missing; missing flags nonmissing; `rent_id` logical TRUE. Vacancy rates missing or finite [0, 1]. |

### Analyst-review diagnostics

| Diagnostic | Review expectation |
|---|---|
| County and rent summaries | Review tract counts, raw missing/top-coded rent, and post-censoring missing rent alongside renter counts; no empirical missingness threshold. |
| Numeric distributions | Inspect negative counts, non-finite values, implausible dollars, and shares outside [0, 1]; general range checks are diagnostics, not universal assertions. |
| Inventory diagnostics | Inspect missing source components and incomplete targets by county; each native tract has one contributor. Complete-target totals do not estimate the entire sample's inventory. |

## 8. Known limitations / intentional exceptions

- **Uncertainty denominator mismatch:** `pctrhuE` uses `huE`, but `pctrhuM`
  uses `rhu_baseE/M`; `pcthspE` uses `pop_ethnE`, but `pcthspM` uses
  `pop_raceE/M`. These are the current `calc_cv()` formulas, not matched-denominator
  uncertainty estimates; this schema does not correct the code.
- No structure/inventory MOE or CV, interpolated rent, or block-group rent-quality
  shares are added. Step 4 uses post-censoring `rentE` as this source's counterpart
  for canonical `interp_rent`; this file contains no tract interpolation.
- The 170-column list describes the current Step 1 contract. Step 2 retains input
  columns rather than enforcing an exhaustive column whitelist; readback checks
  compare against memory, not a fixed 170-column schema.

## 9. Validation and regeneration

- **Focused validation:** `tests/test_rent_metadata.R` covers native classification and raw evidence; existing synthetic checks in
  [tests/test_income_censoring.R](../tests/test_income_censoring.R) and
  [tests/test_rental_inventory.R](../tests/test_rental_inventory.R) cover censoring,
  inventory, and selected notebook acceptance/readback logic.
- **Documentation/column audit:** compare §5 with `tract_vars` in `01_import_acs.Rmd`
  (first alias per distinct code), producer §3, and the flag/share/CV helpers;
  verify local links and `git diff --check`. No data read or regeneration needed.
- **Analyst-run regeneration:** run `02b_build_measures_from_tracts.Rmd` from setup
  through §4 with current Step 1 inputs and optional preserved parity references.
  It writes both native tract products; review all diagnostics after readback.
