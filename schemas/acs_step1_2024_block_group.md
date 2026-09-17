# Schema: `acs_step1_2024_block_group.feather`

**Produced by:** `01_acs.Rmd` (Step 1) · **Source:** 2020–2024 ACS 5-year, **block-group** level, California (`tidycensus::get_acs`)

**Grain:** one row per 2020-vintage California census block group.
**Key:** `bg2020_id` (unique, non-missing).

## Variable availability and column conventions

`block_group_vars` is derived directly from the full `tract_vars` mapping by
excluding the aliases in `block_group_unavailable_vars` (`01_acs.Rmd` §1.2).
The **62 aliases cover 59 distinct Census codes** and preserve the tract
mapping's retained names, codes, and order. Wide format supplies `<name>E`
(estimate) and `<name>M` (90% margin of error) per distinct measure. See the
[full tract mapping](acs_step1_2016_tract.md) for all codes and meanings, with
exactly these three exclusions:

| Excluded alias | Census code | Columns omitted from block-group output |
|---|---|---|
| `rent1bdr` | B25031_003 | `rent1bdrE`, `rent1bdrM` |
| `rent2bdr` | B25031_004 | `rent2bdrE`, `rent2bdrM` |
| `rent3bdr` | B25031_005 | `rent3bdrE`, `rent3bdrM` |

These bedroom-rent pairs remain in both tract outputs. The installed geography
lookup lacks 2024 entries, so the explicit configuration determines exclusions.
All selected B25111 measures (including its total) and B25113 measures have
been removed from the full tract mapping and are absent here as well; they
are not part of the block-group exclusion set.

Both rental vacancy inventory components are present: `vac_forrentE/M`
(B25004_002, vacant for rent) and `vac_rentedE/M` (B25004_003, rented, not
occupied). `vac_forsaleE/M` (B25004_004, for sale only), renter-occupied units,
and all 24 gross-rent categories are retained. No rental-inventory calculation
is introduced. The three duplicate-code request aliases (`grent_3`, `grent_20`,
`grent_26`) are preserved, with output pairs returned under their first aliases
(`grentcat1`, `grentcat18`, `grentcat24`), as in the tract schemas.

## Identifier columns

| column | type | description |
|---|---|---|
| `bg2020_id` | character | 12-digit block-group GEOID (renamed from `GEOID`). Table key. |
| `NAME` | character | Census long name for the block group. |

## Flag columns

| column | type | description |
|---|---|---|
| `rent_id` | logical | Join flag, constant `TRUE`. |

The derived low-rent counts `rhu_lrE` and `rhu_lr2E` are retired and must be
absent. All source estimates/MOEs and all 24 gross-rent bins remain unchanged;
see the [cleanup contract](../docs/measure_cleanup.md).

## Step 1 validation

Immediately after wide extraction and before saving, `01_acs.Rmd` §4 requires
a nonmissing, unique, character 12-digit BG key, character `NAME`, and numeric
estimate/MOE columns derived from the first alias per distinct code in
`block_group_vars`. Duplicate BG rows/column names, missing required columns,
and wrong types fail. The saved `rent_id` flag must be logical, nonmissing, and
`TRUE`. Numeric `NA`/`NaN` source estimates remain valid for Step 2 completeness
handling; no estimate-missingness threshold is imposed.

Section 6.1 reports ACS-only and crosswalk-only BGs separately by source
state/county, with complete ID tables retained in the notebook. These statewide
coverage differences are diagnostic and do not filter this output. Section 7.6
requires exact Feather readback of row counts, keys/row order, column names/order,
storage types/classes, and values against the validated in-memory extract.
These checks add no output columns or measures.

**Downstream:** `02_assemble.Rmd` continues to aggregate this block-group table
to 2010 tracts using `xwalk_bg24_tr10.feather`. See `01_acs.Rmd` §§4.1 and 6.1.
The separate [2024 tract input](acs_step1_2024_tract.md) is consumed by the
native-2020 tract path in Step 2 §4. Generate this file from the revised stage 1; the old cache cannot
substitute for this schema. See the [migration instructions](../README.md#stage-1-input-migration).
