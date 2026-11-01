# ACS Tract Rent Panel: Geographic Harmonization and Mapping

Constructs comparable census-tract measures of rent, rental housing inventory, and neighborhood characteristics from the 2012–2016 and 2020–2024 American Community Survey. Addresses changes in tract boundaries by retaining native tract estimates where geography is unchanged and allocating block-group measures to 2010 tract boundaries elsewhere. The resulting panel covers 14 counties in Southern California and the Bay Area and supports static and interactive maps of rent levels and change.


![Baseline rent and rent change in Alameda County](outputs/figures/tract_rent_baseline_and_change_alameda.html)

<a id="setup"></a>

## Getting started

Raw and intermediate datasets are not included in this public repository.
Configure their locations before running the notebooks; the tracked `.here`
marker anchors repository-relative paths.

1. Install the R version recorded in [renv.lock](renv.lock) and the system
   requirements below. **All notebook renders need Pandoc**, available with
   RStudio or as a separate installation. Restoring R packages does not install
   R, Pandoc, system libraries, or input data.
2. From the repository root, restore the locked R packages. The tracked
   [.Rprofile](.Rprofile) and [renv/activate.R](renv/activate.R) bootstrap renv
   and activate the project library. Restore needs network access unless packages
   are cached. Run project commands without `--vanilla`, which bypasses
   `.Rprofile` and `.Renviron`.

   ```sh
   Rscript -e 'renv::restore(prompt = FALSE)'
   ```

3. Copy [.Renviron.example](.Renviron.example) to the ignored `.Renviron` in the
   repository root. Set `ACS_RAW_DATA_DIR` to the raw-input directory and
   `ACS_DATA_DIR` to a dedicated generated-data directory. Absolute paths or
   paths relative to this checkout are accepted; `data-raw/` and `data/` are
   supported, ignored local choices. Other local choices need matching ignore
   rules. **Notebook 1 requires `CENSUS_API_KEY`** for its rent-evidence requests:
   request and activate your own [Census API key](https://api.census.gov/data/key_signup.html)
   and put it in `.Renviron`. Environment variables set before starting R also
   work. **Restart R after editing `.Renviron`.**
4. Supply the manual inputs below without modifying their contents. Notebooks
   1 and 3 need both data-directory variables; 2a, 2b, 4, and 5 need only
   `ACS_DATA_DIR`. Writers create missing output directories and announce
   replacements. Preserve any outputs you need before rerunning. Step 3's
   `overwrite_output` and Step 5's `overwrite_figures` default to `TRUE`; setting
   either to `FALSE` refuses replacement for that stage.

### System requirements

- **Full environment / Steps 1–4:** compiled packages need a C/C++/Fortran
  toolchain when binaries are unavailable. Spatial dependencies are needed even
  before mapping because these notebooks load `tidycensus`: source builds need
  GDAL, GEOS, PROJ, SQLite, and UDUNITS2; see [sf installation](https://r-spatial.github.io/sf/#installing).
  The locked packages also require curl, OpenSSL, and libxml2 development
  libraries on typical Linux source builds. A full Arrow source build needs
  C++17 and CMake >= 3.25; see the [Arrow installation guide](https://arrow.apache.org/docs/21.0/r/articles/install.html).
- **Mapping and export:** Step 5 additionally needs system `unzip` on `PATH`
  and working R PNG/PDF graphics support. Font and graphics source builds need
  Cairo, FreeType, Fontconfig, HarfBuzz, FriBidi, and PNG/JPEG/TIFF/WebP libraries;
  see [gdtools](https://davidgohel.github.io/gdtools/) and the system requirements
  in [renv.lock](renv.lock). The complete restore includes these packages even
  if you stop before mapping. Platform-specific export details are in
  [notebook 5](05_map_tract_rents.Rmd#5-draw-and-save-the-paired-maps).

macOS/Windows binary packages generally bundle compiled dependencies. Availability
depends on the platform and locked versions; a clean restore and full pipeline
run are not established by documentation checks alone.

### Manual inputs

Sign in to an [IPUMS NHGIS account](https://www.nhgis.org/geographic-crosswalks).
Under **Downloads → Crosswalks to Census Tracts**, select **California, 2020 to
2010** under **2020s Block Groups**, and **California, 2000 to 2010** under
**2000 Census Tracts**. Download and extract both ZIPs, placing the CSVs at the
exact paths below. **Both crosswalks are mandatory:** notebook 1 checks both
files before downloading ACS data, imports both, and validates both saved
outputs. The 2000-to-2010 output is unused by later stages, but its input cannot
be skipped in the current notebook. These downloads require IPUMS login and
are not automated by this pipeline.

| Manual download | Required path below `ACS_RAW_DATA_DIR` |
|---|---|
| [NHGIS 2020 BG → 2010 tract ZIP](https://secure-assets.ipums.org/nhgis/crosswalks/nhgis_bg2020_tr2010_state/nhgis_bg2020_tr2010_06.zip) | `nhgis/nhgis_bg2020_tr2010_06/nhgis_bg2020_tr2010_06.csv` |
| [NHGIS 2000 tract → 2010 tract ZIP](https://secure-assets.ipums.org/nhgis/crosswalks/nhgis_tr2000_tr2010_state/nhgis_tr2000_tr2010_06.zip) | `nhgis/nhgis_tr2000_tr2010_06/nhgis_tr2000_tr2010_06.csv` |
| [Census California 2020 → 2010 tract relationship text](https://www2.census.gov/geo/docs/maps-data/data/rel2020/tract/tab20_tract20_tract10_st06.txt) | `census/tab20_tract20_tract10_st06.txt` |

The Census text is the California entry under **Census Tract Relationship Files**
on the [2020 relationship-file page](https://www.census.gov/geographies/reference-files/time-series/geo/relationship-files.2020.html).
Download it manually without an account and save it unchanged as UTF-8
pipe-delimited text. Missing raw files stop execution with the expected path.

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

Steps 2a and 2b can run in either order after 1. Step 3 is independent of 1–2;
run it before 4, or reuse its validated crosswalk. Step 4 needs all three Step 2
products and the Step 3 crosswalk. Optional historical Step 2 snapshots belong
under `${ACS_DATA_DIR}/parity_reference/`; missing snapshots leave parity unchecked.

**Notebook 5 requires the saved `${ACS_DATA_DIR}/acs_full.feather`.** Notebook
4 configures that destination in §1.3 (`set-paths`) and always saves after
validation in §7.5 (`save-panel`). An existing panel supplies a schema reference
and is replaced after those checks; the replacement is announced, and the
saved file is reloaded and checked. A first run needs no prior panel.

Step 1 retrieves statewide ACS estimates and rent evidence automatically through
the Census API. Step 5 can run independently once the saved panel exists; it
downloads public 2010 TIGER/Line boundaries on the first uncached run and reuses
them from `outputs/cache/tiger2010/`. Figure exports stay in `outputs/figures/`.

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
static and HTML hover maps of 2012–2016 monthly median gross rent and real
percentage change to 2020–2024. Select the county in the `configuration` chunk;
Alameda is the default.

**Inputs:**

- `${ACS_DATA_DIR}/acs_full.feather` — saved canonical 2010-tract panel from Step 4.
- [Census 2010 TIGER/Line county tract ZIP](https://www2.census.gov/geo/tiger/TIGER2010/TRACT/2010/tl_2010_06001_tract10.zip)
  — default Alameda boundaries, cached at
  `outputs/cache/tiger2010/tl_2010_06001_tract10.zip`; other county filenames use
  the configured county FIPS.

**Outputs:**

- `outputs/figures/tract_rent_baseline_and_change_alameda.png` and
  `outputs/figures/tract_rent_baseline_and_change_alameda.pdf` — paired static maps.
- `outputs/figures/tract_rent_baseline_and_change_alameda.html` — self-contained
  hover maps. All three filename suffixes follow the configured county.
- Inline maps and join/display summaries; no intermediate dataset is written.

**Steps:**

1. Configure the county, projection, and output locations.
2. Load and validate the saved panel, then select the county.
3. Load 2010 boundaries, join rent data, and report unmatched tracts.
4. Derive percentage changes and display statuses; omit confirmed water-only tracts from plotting.
5. Draw and export the paired PNG/PDF maps and HTML hover version.
6. Summarize join coverage, displayed values/statuses, omissions, and exports.

After [setup](#getting-started) and Step 4, render from the repository root:

```sh
Rscript -e 'rmarkdown::render("05_map_tract_rents.Rmd")'
```

Open the exported `.html` directly in a browser; it works offline without a
server. Hover over a tract for its full GEOID and baseline rent in 2024 dollars,
real percentage change, or top-coded/unavailable label. Rendering and display
details remain in [notebook 5](05_map_tract_rents.Rmd).

## Methods and limitations

The 2012–2016 and 2020–2024 ACS releases pool observations across two separate
five-year windows. They are period estimates, not observations of conditions
in 2016 or 2024 alone; see the [Census guide to ACS estimates](https://www.census.gov/programs-surveys/acs/guidance/estimates.html).

Step 3 identifies one-to-one tract pairs whose positive land areas overlap
exactly. Step 4 uses native 2024 tract estimates for those pairs and NHGIS-weighted
block-group allocations elsewhere, without switching sources to fill missing
values. Allocated counts and distribution-based medians approximate conditions
within 2010 boundaries; allocation and rent-bin interpolation add uncertainty
beyond ACS sampling error. They are not direct Census tract estimates, and no
margin of error is calculated for interpolated rent. See the [block-group construction rules](schemas/acs_step2_2024_block_group_aggregated.md#3-construction-rules)
and [panel limitations](schemas/acs_full.md#8-known-limitations--intentional-exceptions).

Notebook 4 §2.3 and `inflation_factor_2016()` in [R/merge_helpers.R](R/merge_helpers.R)
convert 2016 dollar estimates, their margins of error, and rent censoring bounds to 2024
dollars using exactly **1.307**. This is the rounded ratio of the BLS CPI-U
annual averages for all items, U.S. city average: **313.689 (2024) / 240.007
(2016) = 1.306999…**, verified in the [BLS historical CPI-U table](https://www.bls.gov/cpi/tables/supplemental-files/historical-cpi-u-202412.pdf).

Confirmed top-coded rents retain a status and lower bound, with no numeric
estimate; other unavailable or unresolved rents also remain missing. A genuine
observed $3,500 native rent is retained when its source evidence supports it.
Block-group interpolation requires the cash-renter total and every rent bin.
Maps distinguish top-coded from unavailable values and calculate percentage
change only when both rents are observed and positive. Detailed classification
rules are in the [panel schema](schemas/acs_full.md#6-missingness-and-special-value-rules).
Mapped changes are descriptive and do not identify a causal effect of ADUs or
any other intervention.

## Detailed documentation

The schemas linked under each notebook define current dataset contracts. The
[crosswalk/contributor QA guide](docs/qa_guide.md) explains coverage checks and
their limits. [Measure-cleanup and rent-metadata history](docs/measure_cleanup.md)
preserves dated migration evidence and superseded downstream instructions.
