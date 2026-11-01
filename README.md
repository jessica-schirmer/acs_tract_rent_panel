# ACS Tract Rent Panel: Geographic Harmonization and Mapping

This R pipeline constructs comparable census-tract measures of rent, rental housing inventory, and neighborhood characteristics from the 2012–2016 and 2020–2024 American Community Survey. It addresses changes in tract boundaries by retaining native tract estimates where geography is unchanged and allocating block-group measures to 2010 tract boundaries elsewhere. The resulting panel covers 14 counties in Southern California and the Bay Area and supports static and interactive maps of rent levels and change.


![Baseline rent and rent change in Alameda County](outputs/figures/tract_rent_baseline_and_change_alameda.png)

## Setup

Raw and intermediate datasets are not included in this public repository.
Data can remain outside the checkout; no surrounding research-project directory
structure is required.

1. Use **R 4.5.1**, the version recorded in [renv.lock](renv.lock), and install
   Pandoc (included with RStudio), system `unzip`, and working PNG/PDF graphics
   support (Quartz on macOS, Cairo elsewhere). CRAN binaries generally supply
   the compiled R dependencies on macOS/Windows. Source builds need a C/C++/Fortran
   toolchain; spatial packages need GDAL, GEOS, PROJ and UDUNITS2, while graphics
   packages need FreeType, Fontconfig and Cairo development libraries. Linux
   builds also commonly need curl, OpenSSL and libxml2 development libraries.
   Follow the [sf system setup](https://r-spatial.github.io/sf/#installing),
   [gdtools requirements](https://davidgohel.github.io/gdtools/), and
   [Arrow installation guide](https://arrow.apache.org/docs/r/articles/install.html)
   if binary packages are unavailable. The locked Arrow version requires C++17
   and CMake >= 3.25 for a full source build; these are system prerequisites,
   not notebook-installed packages.
2. Start R in the repository root and run `renv::restore()`, or use the shell
   command below. The tracked `.Rprofile` and `renv/activate.R` bootstrap the
   pinned renv version and isolate the project library. Restore requires network
   access unless the versions are already cached. Do not use `--vanilla` for
   normal project commands: it bypasses `.Rprofile` and `.Renviron`.

   ```sh
   Rscript -e 'renv::restore(prompt = FALSE)'
   ```

3. Copy [.Renviron.example](.Renviron.example) to an ignored `.Renviron` in the
   repository root and fill in `ACS_RAW_DATA_DIR`, `ACS_DATA_DIR`, and
   `CENSUS_API_KEY`. Request your own [Census API key](https://api.census.gov/data/key_signup.html)
   and activate it using the emailed instructions. Environment variables supplied
   before starting R are also supported. **Restart R after editing `.Renviron`.**
   Absolute paths are accepted; relative paths resolve from the repository root
   located by `here` and the tracked `.here` marker. No old-layout fallback exists.
   The ignored local choices `data-raw/` (or `data-raw-temp/`) and `data/` are
   supported. Other repository-local choices need corresponding ignore rules.
4. Supply the three manual inputs below. Keep raw files unchanged. `ACS_DATA_DIR`
   receives generated Feather files, so choose a dedicated output directory;
   writers create missing output directories and announce replacements. Step 3
   and the map retain their explicit overwrite controls; Step 4 checks any
   prior schema before replacement. Notebooks 1 and 3 need both data variables;
   notebooks 2a, 2b, 4 and 5 need only `ACS_DATA_DIR`.

### Manual inputs

Sign in to an [IPUMS NHGIS account](https://www.nhgis.org/geographic-crosswalks).
Under **Downloads → Crosswalks to Census Tracts**, select **California, 2020 to
2010** under **2020s Block Groups**, and **California, 2000 to 2010** under
**2000 Census Tracts**. Download and extract both ZIPs, placing the CSVs at the
exact paths below. Notebook 1 requires the second crosswalk even though later
stages do not consume its output. The download links require IPUMS login.

| Manual download | Required path below `ACS_RAW_DATA_DIR` |
|---|---|
| [NHGIS 2020 BG → 2010 tract ZIP](https://secure-assets.ipums.org/nhgis/crosswalks/nhgis_bg2020_tr2010_state/nhgis_bg2020_tr2010_06.zip) | `nhgis/nhgis_bg2020_tr2010_06/nhgis_bg2020_tr2010_06.csv` |
| [NHGIS 2000 tract → 2010 tract ZIP](https://secure-assets.ipums.org/nhgis/crosswalks/nhgis_tr2000_tr2010_state/nhgis_tr2000_tr2010_06.zip) | `nhgis/nhgis_tr2000_tr2010_06/nhgis_tr2000_tr2010_06.csv` |
| [Census California 2020 → 2010 tract relationship text](https://www2.census.gov/geo/docs/maps-data/data/rel2020/tract/tab20_tract20_tract10_st06.txt) | `census/tab20_tract20_tract10_st06.txt` |

The Census text is the California entry under **Census Tract Relationship Files**
on the [2020 relationship-file page](https://www.census.gov/geographies/reference-files/time-series/geo/relationship-files.2020.html).
Save it unchanged as UTF-8 pipe-delimited text. Missing raw files stop execution
with the expected full path and a link back to this setup section.

### Run the pipeline

From the repository root, render each notebook in a fresh R process:

```sh
Rscript -e 'rmarkdown::render("01_import_acs.Rmd")'
Rscript -e 'rmarkdown::render("02a_build_measures_from_block_groups.Rmd")'
Rscript -e 'rmarkdown::render("02b_build_measures_from_tracts.Rmd")'
Rscript -e 'rmarkdown::render("03_identify_tract_boundary_changes.Rmd")'
Rscript -e 'rmarkdown::render("04_assemble_tract_panel.Rmd")'
Rscript -e 'rmarkdown::render("05_map_tract_rents.Rmd")'
```

Steps 2a/2b can run in either order after 1; Step 3 is independent of 1–2.
Step 1 downloads statewide ACS estimates and rent evidence via the Census API.
Step 4 always validates, saves `ACS_DATA_DIR/acs_full.feather`, and checks its
readback; no prior panel is required. Step 5 needs only that panel and public
Census 2010 TIGER/Line boundaries, which it downloads/caches under
`outputs/cache/tiger2010/`. Figures remain under `outputs/figures/`.
Optional historical Step 2 snapshots belong under `ACS_DATA_DIR/parity_reference/`;
missing snapshots report parity as unchecked and do not block production.

For inexpensive offline checks after restoration, run
`Rscript tests/test_data_paths.R`, `Rscript tests/test_dependencies.R`, and the
synthetic `tests/test_*.R` suites. Tests use temporary outputs; full empirical
execution and diagnostic review remain analyst-run.

## Notebook overview

- [01_import_acs.Rmd](01_import_acs.Rmd) imports statewide ACS estimates and original rent
  evidence for 2016 tracts and 2024 tracts/block groups, plus NHGIS crosswalks.
- [02a_build_measures_from_block_groups.Rmd](02a_build_measures_from_block_groups.Rmd)
  allocates 2024 block-group measures to target-county 2010 tracts and derives
  rent, rental inventory, and covariates.
- [02b_build_measures_from_tracts.Rmd](02b_build_measures_from_tracts.Rmd) prepares both
  vintages on native tract keys, with rental inventory and rent metadata.
  It and 02a can run in either order after 01.
- [03_identify_tract_boundary_changes.Rmd](03_identify_tract_boundary_changes.Rmd) identifies geographically consistent
  2010–2020 tract links from statewide Census intersections. It runs independently
  of Steps 1–2, or its validated crosswalk can be reused.
- [04_assemble_tract_panel.Rmd](04_assemble_tract_panel.Rmd) combines all three Step 2 products and the Step 3
  crosswalk, selects 2024 measurements by geographic consistency, and calculates
  panel changes and source comparisons, then saves the panel consumed by notebook 5.
- [05_map_tract_rents.Rmd](05_map_tract_rents.Rmd) maps baseline monthly gross
  rent and subsequent real percentage change on 2010 tracts, with explicit
  top-coded and unavailable display statuses. It reads the saved Step 4 panel;
  Alameda County is the default; the HTML version adds tract/value hover labels.

<a id="stage-1-input-migration"></a>

## Step 1: Import ACS data

Notebook: [01_import_acs.Rmd](01_import_acs.Rmd). Import statewide ACS estimates, original
B25064 rent evidence, and NHGIS allocation crosswalks without sample filtering.

**Inputs:**

- Census ACS 5-year API via `tidycensus`: 2012–2016 tracts and 2020–2024
  tracts/block groups, California.
- `${ACS_RAW_DATA_DIR}/nhgis/nhgis_bg2020_tr2010_06/nhgis_bg2020_tr2010_06.csv`
  — 2020 block groups to 2010 tracts.
- `${ACS_RAW_DATA_DIR}/nhgis/nhgis_tr2000_tr2010_06/nhgis_tr2000_tr2010_06.csv`
  — 2000 tracts to 2010 tracts.

**Outputs:**

- `${ACS_DATA_DIR}/acs_step1_2016_tract.feather` — 2012–2016 estimates on
  `tr2010_id`; [schema](schemas/acs_step1_2016_tract.md).
- `${ACS_DATA_DIR}/acs_step1_2024_block_group.feather` — 2020–2024 estimates on
  `bg2020_id`; [schema](schemas/acs_step1_2024_block_group.md).
- `${ACS_DATA_DIR}/acs_step1_2024_tract.feather` — 2020–2024 estimates on
  `tr2020_id`; [schema](schemas/acs_step1_2024_tract.md).
- `${ACS_DATA_DIR}/xwalk_bg24_tr10.feather` — block-group allocation links and
  weights; [schema](schemas/xwalk_bg24_tr10.md).
- `${ACS_DATA_DIR}/xwalk_tr00_tr10.feather` — 2000-to-2010 tract allocation links
  and weights; [schema](schemas/xwalk_tr00_tr10.md). Not consumed by Steps 2–4.

**Steps:**

1. Define ACS variables, retaining rent-distribution and inventory components; omit unavailable bedroom-rent measures from the block-group request.
2. Download 2012–2016 tract estimates and original rent evidence, check uncertainty, and save on 2010 tract keys.
3. Download 2020–2024 block-group estimates and rent evidence, validate the requested fields and keys, and save.
4. Download 2020–2024 native tract estimates and rent evidence, check uncertainty, and save on 2020 tract keys.
5. Import both geographic crosswalks; validate block-group allocation pairs and weights and report ACS/crosswalk coverage.
6. Validate the five saved products, including keys, missingness, distributions, and exact block-group/crosswalk readback.

<a id="stage-2-output-naming-and-references"></a>

## Step 2a: Aggregate 2024 block groups

Notebook: [02a_build_measures_from_block_groups.Rmd](02a_build_measures_from_block_groups.Rmd).
Allocate 2020–2024 block-group measures to target-county 2010 tracts, retaining
all contributing sources, including those outside the target counties, with
original NHGIS fractions and no renormalization.

**Inputs:**

- `${ACS_DATA_DIR}/acs_step1_2024_block_group.feather` — statewide ACS block groups.
- `${ACS_DATA_DIR}/xwalk_bg24_tr10.feather` — allocation links and weights.
- Optional `${ACS_DATA_DIR}/parity_reference/acs_step2_24.feather` — preserved
  schema and Southern California parity reference.

**Outputs:**

- `${ACS_DATA_DIR}/acs_step2_2024_block_group_aggregated.feather` — one row per
  `tr2010_id`, with counts, rental inventory, interpolated rent,
  rent status/flags/bounds, component coverage, income, shares/rates, and
  uncertainty measures. See the [output schema](schemas/acs_step2_2024_block_group_aggregated.md)
  for construction rules, diagnostics, and validation.

**Steps:**

1. Select allocations and check contributors; classify source rents, aggregate counts and income, construct inventory, derive rent and other measures, compare preserved references, and save.
2. Validate the reloaded product's contributor integrity, count/dependent-measure completeness, county coverage, rent metadata, and inventory reconciliation.

Missing required contributor records stop execution; missing positive-weight
count estimates make the affected aggregate and its dependent measures missing.
Rent interpolation requires the cash-renter total and all 24 rent bins.
Inventory adds renter-occupied, vacant-for-rent, and rented-but-unoccupied units,
allocating all three components with renter weights (`wt_renthu`).

## Step 2b: Prepare native tract sources

Notebook: [02b_build_measures_from_tracts.Rmd](02b_build_measures_from_tracts.Rmd).
Prepare both vintages directly on their native tract keys, retaining source
rent estimates and evidence. Income remains independent of rent availability;
see the [income decision and acceptance checks](docs/notes/income_censoring.md).

**Inputs:**

- `${ACS_DATA_DIR}/acs_step1_2016_tract.feather` — 2012–2016 estimates on 2010 tracts.
- `${ACS_DATA_DIR}/acs_step1_2024_tract.feather` — 2020–2024 estimates on 2020 tracts.
- Optional `${ACS_DATA_DIR}/parity_reference/acs_step2_16.feather` and
  `${ACS_DATA_DIR}/parity_reference/acs_step2_2024_tract.feather` — separate
  preserved schema and Southern California parity references.

**Outputs:**

- `${ACS_DATA_DIR}/acs_step2_2016_tract.feather` — 2012–2016 measures on
  `tr2010_id`; [schema](schemas/acs_step2_2016_tract.md).
- `${ACS_DATA_DIR}/acs_step2_2024_tract.feather` — 2020–2024 measures on
  `tr2020_id`; [schema](schemas/acs_step2_2024_tract.md).

Both contain target-county tract measures, direct rental inventory, rent
metadata/evidence, structure counts, shares, vacancy rates, and CVs. They
retain native dollar estimates and uncertainty; no tract rent interpolation
is constructed.

**Steps:**

1. Restrict 2012–2016 tracts to target counties, classify/censor rent, construct flags and derived measures including inventory, check parity, and save.
2. Prepare the corresponding 2020–2024 native tract measures, preserving 2020 keys and source income, then validate and save.
3. Validate both reloaded products' keys, county coverage, missingness, flags, distributions, and inventory completeness/reconciliation.

## Step 3: Identify geographically consistent tracts

Notebook: [03_identify_tract_boundary_changes.Rmd](03_identify_tract_boundary_changes.Rmd). Characterize statewide
2010–2020 tract relationships for Step 4's source selection and comparisons.

**Inputs:**

- `${ACS_RAW_DATA_DIR}/census/tab20_tract20_tract10_st06.txt`
  — Census 2020-to-2010 tract geographic intersections.

**Outputs:**

- `${ACS_DATA_DIR}/xwalk_tr20_tr10.feather` — one row per California `tr2020_id`,
  with a `tr2010_id` where uniquely linked, geographic consistency, relationship
  class, and land-area QA. Pair-level diagnostics, regional/county summaries,
  and rejected one-to-one pairs remain in the notebook.
  See the [crosswalk schema](schemas/xwalk_tr20_tr10.md).

**Steps:**

1. Read and validate geographic IDs, intersection pairs, and land areas.
2. Count all partners and identify consistency: one partner in each direction, positive tract land areas, and intersection area exactly equal to both totals.
3. Retain every 2020 tract, attach only unique 2010 links, and classify changed one-to-one, split, merge, and many-to-many relationships.
4. Review statewide and target-region/county relationships, exclusion reasons, overlap shares, coverage, and land reconciliation.
5. Save the crosswalk and validate membership, keys, fields, and values after reload.

Equal GEOIDs alone do not establish consistency. Step 3 neither allocates
changed tracts nor imposes the Step 2 county restriction.

## Step 4: Build the panel and compare sources

Notebook: [04_assemble_tract_panel.Rmd](04_assemble_tract_panel.Rmd). Retain the union of 2016 and
block-group-aggregated 2024 keys. Select native 2024 tract measurements only
where `geo_consistent == 1`, and block-group measurements otherwise, including
missing/unexpected flags. Entire measurement and quality bundles follow that
selection; missing selected records or values have no availability fallback.

**Inputs:**

- `${ACS_DATA_DIR}/acs_step2_2016_tract.feather` — baseline on `tr2010_id`.
- `${ACS_DATA_DIR}/acs_step2_2024_block_group_aggregated.feather` — 2024 measures on `tr2010_id`.
- `${ACS_DATA_DIR}/acs_step2_2024_tract.feather` — native 2024 measures on `tr2020_id`.
- `${ACS_DATA_DIR}/xwalk_tr20_tr10.feather` — geographic status and explicit links.
- Existing `${ACS_DATA_DIR}/acs_full.feather`, when present
  — prior column/type reference, not a source of measurements.

**Outputs:**

- `${ACS_DATA_DIR}/acs_full.feather`, saved after validation — a 2010-tract
  panel with baseline/selected levels, changes, uncertainty, and
  geographic/source/rent metadata. Occupied-renter and rental-inventory changes
  remain separate; `smfE` and `sfd_detE` are retained as levels for both years.
  See the [panel schema](schemas/acs_full.md) for definitions and acceptance
  checks. Geographic, source-level/change, and inventory comparison tables
  remain in the notebook.

**Steps:**

1. Read all three measurement products and the crosswalk; convert 2016 dollar estimates, MOEs, and rent censoring bounds to 2024 dollars using 1.307.
2. Merge on explicit tract links, select canonical 2024 bundles, and calculate level ratios over positive baselines and share/rate differences.
3. Review geographic coverage, unmatched keys, source selection, and agreement with selected sources.
4. Compare native and block-group rent/inventory levels and implied changes on geographically consistent tract pairs only.
5. Compare occupied renters with rental inventory within native inputs and compare their changes on the full panel and consistent subset.
6. Validate panel membership, changes, flags, missingness, and distributions; save and check the reloaded panel.

Canonical `interp_rent` is the native median gross rent for consistent tracts
and the block-group distribution interpolation elsewhere. `interp_rentPOST`
divides it by positive, inflation-adjusted `rentE_16`. Income/uncertainty
weighting limitations are documented in the [panel schema](schemas/acs_full.md#8-known-limitations--intentional-exceptions).

## Step 5: Map baseline rent and real change

Notebook: [05_map_tract_rents.Rmd](05_map_tract_rents.Rmd). Produce paired
static and HTML hover maps of 2012–2016 monthly median gross rent and its percentage change to
2020–2024, using canonical rents already expressed in 2024 dollars. Select a
county in the configuration chunk; no parcel, ADU, CV, or model-sample filters apply.
Only the plotting frame omits confirmed water-only tracts (`ALAND10 == 0` and
`AWATER10 > 0`). The full join retains every tract; tracts containing land or
missing either area attribute remain displayed with their existing rent statuses.

**Inputs:**

- `${ACS_DATA_DIR}/acs_full.feather` — canonical 2010-tract panel; `rentE_16`,
  `interp_rent`, `interp_rentPOST`, and their geographic/rent quality fields.
- [Census 2010 TIGER/Line county tract ZIP](https://www2.census.gov/geo/tiger/TIGER2010/TRACT/2010/tl_2010_06001_tract10.zip)
  — default Alameda boundaries, cached at
  `outputs/cache/tiger2010/tl_2010_06001_tract10.zip`; other county filenames use
  the configured state/county FIPS. The notebook documents source vintage and fields.

**Outputs:**

- `outputs/figures/tract_rent_baseline_and_change_alameda.png` — paired maps
  for the repository example.
- `outputs/figures/tract_rent_baseline_and_change_alameda.pdf` — equivalent
  vector figure. Filename suffixes follow the configured county name.
- `outputs/figures/tract_rent_baseline_and_change_alameda.html` — self-contained
  paired maps with tract/value hover labels; the suffix follows the same county configuration.
- Inline figure, full-join validation, displayed status counts, and a separate
  omitted water-only count; the original boundary ZIP is cached, with no
  intermediate dataset written.

**Steps:**

1. Configure the processed-data directory, county, projection, and repository-local outputs.
2. Validate wide-panel keys, canonical rent metadata, and the selected county.
3. Cache 2010 boundaries, join one-to-one, and report unmatched GEOIDs in both directions.
4. Derive percentage changes and display statuses, then omit confirmed water-only tracts from a separate plotting frame.
5. Use the plotting frame for all map layers, status counts, full-range scales, and shared extents; export paired PNG/PDF maps and the HTML hover version.
6. Reconcile full-join, displayed, and omitted counts; inspect plotted ranges and confirm all three exports.

Helpers live in [R/tract_rent_maps.R](R/tract_rent_maps.R). Notebook 5 uses `sf`,
`ggplot2`, `patchwork`, `arrow`, `dplyr`, `tibble`, `here`, `digest`, and
`RColorBrewer`, plus `ggiraph` and `htmlwidgets` for HTML hover maps, with
`knitr`/`rmarkdown` for rendering. Hatching uses clipped
`sf` line geometry; no pattern package is needed. System `unzip` verifies ZIP
checksums; PNG/vector PDF exports use native Quartz on macOS and Cairo elsewhere.
HTML rendering also requires Pandoc (available with RStudio).

Use the shared [setup and execution instructions](#setup) for environment restoration
and notebook rendering.

The configuration retains `overwrite_figures <- TRUE` and announces replacement
of existing PNG/PDF/HTML files; set it to `FALSE` to refuse replacement. Full real-data
rendering remains analyst-run. Review the notebook's final acceptance checks,
including the unchanged-input Alameda counts and removal of the three western
water-only pieces.

Open the saved `.html` file directly in a browser (for example, double-click it).
Its scripts and styles are embedded, so it works offline without a server or an
asset folder. Hover labels show the full tract GEOID and the panel's value:
whole-dollar baseline rent labeled as 2024 dollars, or signed real percentage
change to one decimal place. Top-coded and unavailable values retain their
panel-specific labels. The fixed side-by-side maps preserve proportions when
resized; zoom, pan, selection, and cross-panel highlighting are disabled.
Compare the HTML against both static exports during analyst acceptance review.

The inexpensive offline check is:

```sh
Rscript tests/test_tract_rent_maps.R --preview-dir /tmp/acs_tract_map_preview_r
```

Its explicitly synthetic PNG/PDF/HTML previews must not replace the empirical
example below. The HTML fixture includes numeric, top-coded, unavailable, and
multipart tracts for local hover checks.

## Rent metadata migration

Use year-specific `rent_status_16/24`, `tc_flag_rent_16/24`, and
`rent_censor_bound_16/24`; only observed rent remains numeric. The schemas above
define source evidence, classification, and units. Removed `m_flag_rent` is
replaced by explicit status information. **The removed `pct_tc_rent` component
share has no replacement share: the selected final-median top-code flag must
not be substituted into its legacy rules.** `pct_miss_rent` remains block-group
component coverage, even on native-selected rows, with corrected source
classification and unchanged weights/denominator.

The dated [expected-change report](docs/acs_rent_expected_tract_changes.csv),
[input manifest](docs/acs_rent_expected_change_input_manifest.csv), and
[diagnostic contract and reproduction procedure](schemas/acs_rent_expected_tract_changes.md)
preserve the 2026-10-21 evidence: five native unavailability resolutions,
17 coverage changes, and native $3,500 recovery. These are expected changes
against preserved inputs, not verified regenerated outputs or sample additions.
The [original native evidence](docs/acs_rent_native_2024_evidence.csv) and
[source](docs/acs_rent_coverage_source_changes.csv)/[tract coverage comparisons](docs/acs_rent_coverage_tract_changes.csv)
retain the underlying diagnostics and [input hashes](docs/acs_rent_metadata_input_manifest.csv).

Downstream ADU/model preparation is maintained separately and is not needed to
run this repository. Historical `tests/check_rent_metadata_inputs.R` and
`tests/report_rent_expected_changes.R` are optional diagnostic generators,
not setup checks. They require preserved pre-regeneration inputs under
`ACS_DATA_DIR`, including `tract_ADU_ACS_combined.feather`. The expected-change
report also takes an explicit downstream analysis directory; see its
[reproduction contract](schemas/acs_rent_expected_tract_changes.md#9-validation-and-regeneration).
Neither is called by notebooks 1–5 or the synthetic tests. Existing CSV reports
remain dated evidence; do not regenerate them with current inputs.

## Detailed documentation and known inconsistencies

Output schemas linked above are the current contracts, including methods,
diagnostics, focused validation, and analyst-run regeneration procedures.
The [crosswalk/contributor QA guide](docs/qa_guide.md) explains coverage limits;
the [measure-cleanup record](docs/measure_cleanup.md) documents earlier field
removals.

Some supporting prose remains stale: the QA guide permits interpolation with
a missing later bin. Use the current block-group schema's
complete-distribution rules.
Step 3's overview still describes diagnostic-only downstream use; Step 4 and
the panel schema establish its role in canonical source selection. Historical
consumer-migration instructions in the cleanup record should be read alongside
the separately maintained downstream workflow.
