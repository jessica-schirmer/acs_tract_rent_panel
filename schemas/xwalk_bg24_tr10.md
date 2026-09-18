# Schema: `xwalk_bg24_tr10.feather`

**Produced by:** `01_acs.Rmd` (Step 1) · **Source:** NHGIS crosswalk `nhgis_bg2020_tr2010_06.csv`

**Purpose:** allocate 2020-vintage block-group measures to 2010 census tracts.
Used by `02a_aggregate_2024_block_groups.Rmd` to aggregate `acs_step1_2024_block_group.feather` to the 2010-tract
grain.

**Grain:** one row per (2020 block group → 2010 tract) allocation.
**Key:** the **pair** (`bg2020_id`, `tr2010_id`) is unique. Neither ID alone is
unique — the crosswalk is intentionally **many-to-many** because a block group
can split across multiple tracts and vice versa.

## Columns

| column | type | description |
|---|---|---|
| `bg2020_id` | character | Nonmissing 12-digit 2020-vintage block-group GEOID (renamed from `bg2020ge`). |
| `tr2010_id` | character | Nonmissing 11-digit 2010-vintage tract GEOID (renamed from `tr2010ge`). |
| `wt_pop` | numeric | Allocation weight by population — share of the source block group's population assigned to this tract. In [0, 1]. |
| `wt_hh` | numeric | Allocation weight by households. In [0, 1]. |
| `wt_hu` | numeric | Allocation weight by total housing units. In [0, 1]. |
| `wt_renthu` | numeric | Allocation weight by renter-occupied housing units. In [0, 1]. |
| `x_id` | logical | Join flag, constant `TRUE` (marks rows sourced from a crosswalk). |

**Weights:** for a given source `bg2020_id`, each weight column must sum to one
within `1e-6` across all its target tracts, retaining the existing Step 2
source-sum tolerance. Downstream aggregation picks the weight appropriate to the
measure being apportioned (e.g. `wt_renthu` for renter-housing counts).

## Step 1 validation

Section 6.1 reads both geographic IDs explicitly as character to preserve
leading zeros; cross-state IDs are permitted. Missing/malformed IDs, duplicate
allocation pairs, missing required columns, nonnumeric/nonfinite/out-of-range
weights, invalid `x_id` flags, and failed full-source weight reconciliation stop
before saving. Every one of the four weights must be finite and in `[0,1]`.
No links or weights are altered, dropped, or renormalized.

ACS-only and crosswalk-only BG coverage is reported separately by source
state/county, with complete unmatched IDs and crosswalk links/weights retained
in notebook diagnostics. Statewide coverage differences alone are nonfatal;
they do not exempt any source from structural or weight-sum checks. Step 2
handles contributor completeness for its selected destination tracts.

Section 7.6 compares the reloaded file exactly with the validated in-memory
crosswalk: row counts, keys/row order, column names/order, storage types/classes,
flags, and every allocation weight must be unchanged. The source-sum tolerance
does not apply to readback equality. QA adds no output columns.
