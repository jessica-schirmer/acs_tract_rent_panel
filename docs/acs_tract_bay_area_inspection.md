**ACS tract pipeline: Bay Area extension inspection**

Inspection date: 2026-09-11. Scope: [task_spec_01_inspect.md](../task_spec_01_inspect.md).

The recommendation is to **lightly parameterize the existing R pipeline, then
extend it**. The Bay Area inputs are already cached, but geographic filtering
needs a targeted correction before expansion.

The inspection left code, documentation, data, and saved outputs unchanged. No
notebooks or external/API requests were run. Checks were limited to file and
cached-data inspection, environment inspection, and a small in-memory helper
probe. This document records the findings from that inspection.

**Subsequent stage-1 migration (2026-09-12):** The inspection below records the
inputs and outputs as they existed on its date. Current stage 1 writes
`acs_step1_2016_tract.feather` and `acs_step1_2024_block_group.feather` in place
of the two historical ACS filenames, and adds `acs_step1_2024_tract.feather`.
The variable contract also changed; old caches are retained and cannot
substitute for newly generated inputs. Stage 2 now processes block groups and
the native-2020 tract source separately; see the
[current output names](../README.md#stage-2-output-naming-and-references).
See the [migration and parity compatibility](../README.md#stage-1-input-migration).

**Subsequent Step 2 inventory implementation (2026-09-12):** Assembly now adds
`rhu_inventoryE` to both original products, propagating missing required estimates on
positive-weight contributors. All three block-group inventory components use
`wt_renthu`; existing occupied counts and vacancy rates retain their calculations.
Only the agreed vintage-specific schema additions/removals are permitted against
older parity references, with shared-column checks preserved. New diagnostics
check completeness and reconcile complete-target totals. Synthetic validation
passed; canonical regeneration and empirical review remain analyst-run. The
inspection below retains its original filenames and findings. The subsequently
added 2024 tract-source inventory uses direct tract sums with the same missingness rule.

1. **Current pipeline structure**

   | Stage | Main work and outputs |
   |---|---|
   | [01_acs.Rmd](../01_acs.Rmd), using [R/helpers.R](../R/helpers.R) | Downloads statewide 2012–2016 tract and 2020–2024 block-group ACS estimates/MOEs; derives low-rent counts; imports NHGIS crosswalks. Writes `acs_step1_16.feather`, `acs_step1_24.feather`, and two crosswalk Feathers. |
   | [02_assemble.Rmd](../02_assemble.Rmd), using [R/assemble_helpers.R](../R/assemble_helpers.R) | Selects counties, allocates 2024 block groups to 2010 tracts, censors rent, aggregates measures, and calculates interpolated rent, shares, vacancy rates, flags, and uncertainty. Writes both `acs_step2_*` files. |
   | [03_merge.Rmd](../03_merge.Rmd), using [R/merge_helpers.R](../R/merge_helpers.R) | Selects and suffixes measures, multiplies 2016 dollar estimates/MOEs by 1.307, full-joins surveys, and calculates change measures. Writes `acs_full.feather`. |

   Outputs meet downstream stages through shared `ADU_Rent/data/` filenames.
   Current consumers include `tract_rent_acs`, `tract_rent_renthub`, and
   `comp_analysis_renthub`. The 2000→2010 crosswalk is produced but unused by the
   active assembly/merge sequence.

2. **How geography is encoded**

   Import geography is statewide: both ACS calls specify `state = "CA"`, and
   NHGIS filenames identify California. The assembled sample is controlled by
   one `scag_counties` vector in [02_assemble.Rmd](../02_assemble.Rmd), §1.3:
   Los Angeles `037`, Orange `059`, Riverside `065`, San Bernardino `071`, and
   Ventura `111`. Thus “Southern California” currently means these five
   counties; Imperial and San Diego are excluded.

   The vector is applied to **source block-group IDs** for 2024 and **tract
   IDs** for 2016. `select_target_counties()` in
   [R/assemble_helpers.R](../R/assemble_helpers.R) additionally hardcodes state
   prefix `06` and county positions 3–5. There is no separate geographic
   configuration file or individual-tract exception logic.

   Stage 3 inherits the selected geography. Its transformations assume
   `tr2010_id`; documentation and schemas describe SCAG coverage. No
   county-specific estimation formulas appear in this cleaning stage.

3. **Expected work in R**

   For planning, Bay Area means the nine counties Alameda `001`, Contra Costa
   `013`, Marin `041`, Napa `055`, San Francisco `075`, San Mateo `081`, Santa
   Clara `085`, Solano `095`, and Sonoma `097`.

   **Simple parameterization:** define named Southern California/Bay Area
   county sets and their union, apply the same target geography to both
   vintages, and update affected notebook prose, README, and schemas.
   Read-only checks found **1,588 Bay Area baseline tracts and 5,187 Bay Area
   block groups already present** in the statewide caches. Their crosswalk
   coverage is present, with unique allocation pairs and source weights
   summing to one within tolerance. Geographic expansion alone therefore does
   not require another ACS download.

   **Necessary geographic adaptation:** select **destination 2010 tracts
   while retaining all contributing source block groups**. Merely enlarging
   the current source-county filter is insufficient. Inspection found six
   out-of-scope tracts in the current 2024 output and final panel: four in
   Kern, one in Santa Barbara, and one in Nevada. It also found a positive
   population/household/housing allocation from a San Joaquin block group
   into an Alameda tract. A Bay Area source-only filter would omit it.

   These arise from the source-geography restriction before aggregation in
   [02_assemble.Rmd](../02_assemble.Rmd), §2.2. Retain the original allocation
   weights; destination filtering must not renormalize a source’s retained
   fractions.

   Strengthen validation around source/target coverage, unmatched joins,
   county membership, allocation weights, and unique tract keys. Also correct
   the diagnostic’s `merge == "left_id"`: the helper actually emits
   `"left_only"`. Existing checks mostly print results rather than enforce
   acceptance conditions.

   Preserve the 2016/2024 vintages, 2010 tract geography, year-specific
   low-rent cutoffs, inflation convention, and output column contract. Keep
   the final full-join behavior and audit one-period-only tracts using input
   keys; `base_id` is overwritten with `TRUE` in
   [03_merge.Rmd](../03_merge.Rmd), §3.1.

   Downstream expansion remains separate work:
   [RentHub preparation](../../../analysis/tract_rent_renthub/00_prep_tract_data.Rmd)
   and [ACS analysis](../../../analysis/tract_rent_acs/01_fe_rent.Rmd)
   independently filter back to the five counties. Their parcel, place, and
   other supporting inputs also need Bay Area coverage.

4. **Python-rebuild assessment**

   A rebuild is technically feasible, but substantially more work than the
   geographic extension. Most operations map to pandas/NumPy; Feather maps
   to PyArrow; `tidycensus` needs equivalent API retrieval, variable naming,
   and special-value handling; R Markdown’s audit record needs an equivalent
   notebook workflow. There is no spatial overlay or model estimation to
   port in this stage, despite several loaded spatial/survey packages.

   The main difficulty is numerical parity: weighted means with missing
   values, all-missing sums, sequential `mutate()`/`summarise()` behavior,
   interpolation-bin boundaries, MOE/CV formulas, join indicators, and
   nullable types.

   Two inspected discrepancies make a translation from documentation
   particularly risky. First, `censor_tc_vars()` in
   [R/assemble_helpers.R](../R/assemble_helpers.R) tests already-censored
   `rentE` when updating `med_hhincE`. A three-row in-memory check confirmed
   that missing/top-coded rent also makes income missing. The
   [2016 step-2 schema](../schemas/acs_step2_16.md) describes this condition
   as effectively inactive.

   Second, `calc_agg_vars()` computes dollar-measure MOEs as weighted means,
   while count MOEs use relative-weight root-sum-of-squares. The
   [2024 step-2 schema](../schemas/acs_step2_24.md) describes all of these as
   root-sum-of-squares.

   These require explicit decisions about intended behavior before defining
   Python parity or changing research measures.

5. **Why the lightly parameterized R approach fits**

   The existing three-stage structure, reusable helpers, statewide caches,
   and Feather contracts already support the expansion. The substantive
   geographic correction is localized. A Python rebuild would add retrieval
   and numerical-equivalence work without eliminating the underlying
   geographic or measurement decisions.

   Reproducibility has two practical gaps: the documented raw crosswalk paths
   are absent locally, and no `renv.lock` or active project `renv` setup was
   found, although the notebook packages are installed. The shared
   [PIPELINE.md](../../../PIPELINE.md) also contains stale vintage and
   downstream descriptions.

6. **Suggested next implementation task**

   Extend the existing R stage to the five current counties plus the nine
   Bay Area counties using named county sets and destination-tract filtering.
   Preserve incoming crosswalk contributions and existing measurement
   definitions; correct merge diagnostics; synchronize affected documentation.

   Add focused checks for geographic containment, joins, weight conservation,
   schema compatibility, and missing/top-coded rent by county. Require parity
   for unaffected Southern California tracts and explicitly report
   boundary-related changes. Keep candidate outputs separate during
   validation, and handle the income-censoring/MOE decisions explicitly before
   accepting analytical results.
