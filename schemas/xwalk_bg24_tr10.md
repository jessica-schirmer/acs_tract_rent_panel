# Schema: `xwalk_bg24_tr10.feather`

**Produced by:** `01_acs.Rmd` (Step 1) · **Source:** NHGIS crosswalk `nhgis_bg2020_tr2010_06.csv`

**Purpose:** allocate 2020-vintage block-group measures to 2010 census tracts.
Used by `02_assemble.Rmd` to aggregate `acs_step1_24.feather` to the 2010-tract
grain.

**Grain:** one row per (2020 block group → 2010 tract) allocation.
**Key:** the **pair** (`bg2020_id`, `tr2010_id`) is unique. Neither ID alone is
unique — the crosswalk is intentionally **many-to-many** because a block group
can split across multiple tracts and vice versa.

## Columns

| column | type | description |
|---|---|---|
| `bg2020_id` | character | 2020-vintage block-group GEOID (renamed from `bg2020ge`). |
| `tr2010_id` | character | 2010-vintage tract GEOID (renamed from `tr2010ge`). |
| `wt_pop` | numeric | Allocation weight by population — share of the source block group's population assigned to this tract. In [0, 1]. |
| `wt_hh` | numeric | Allocation weight by households. In [0, 1]. |
| `wt_hu` | numeric | Allocation weight by total housing units. In [0, 1]. |
| `wt_renthu` | numeric | Allocation weight by renter-occupied housing units. In [0, 1]. |
| `x_id` | logical | Join flag, constant `TRUE` (marks rows sourced from a crosswalk). |

**Weights:** for a given source `bg2020_id`, each weight column sums to ~1 across
its target tracts. Downstream aggregation picks the weight appropriate to the
measure being apportioned (e.g. `wt_renthu` for renter-housing counts).
