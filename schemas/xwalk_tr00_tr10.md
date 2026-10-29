# Schema: `xwalk_tr00_tr10.feather`

**Produced by:** `01_import_acs.Rmd` (Step 1) · **Source:** NHGIS crosswalk `nhgis_tr2000_tr2010_06.csv`

**Purpose:** allocate 2000-vintage tract measures to 2010 census tracts (used to
harmonize earlier-vintage tract data to the 2010-tract grain).

**Grain:** one row per (2000 tract → 2010 tract) allocation.
**Key:** the **pair** (`tr2000_id`, `tr2010_id`) is unique. Neither ID alone is
unique — the crosswalk is intentionally **many-to-many** because a 2000 tract can
split across multiple 2010 tracts and vice versa.

## Columns

| column | type | description |
|---|---|---|
| `tr2000_id` | character | 2000-vintage tract GEOID (renamed from `tr2000ge`). |
| `tr2010_id` | character | 2010-vintage tract GEOID (renamed from `tr2010ge`). |
| `wt_pop` | numeric | Allocation weight by population — share of the source 2000 tract's population assigned to this 2010 tract. In [0, 1]. |
| `wt_hh` | numeric | Allocation weight by households. In [0, 1]. |
| `wt_hu` | numeric | Allocation weight by total housing units. In [0, 1]. |
| `wt_renthu` | numeric | Allocation weight by renter-occupied housing units. In [0, 1]. |
| `x_id` | logical | Join flag, constant `TRUE`. |

**Weights:** for a given source `tr2000_id`, each weight column sums to ~1 across
its target 2010 tracts. Downstream aggregation picks the weight appropriate to
the measure being apportioned.
