# Schema: `acs_step1_2016_tract.feather`

**Produced by:** `01_acs.Rmd` (Step 1) · **Source:** 2012–2016 ACS 5-year, tract level, California (`tidycensus::get_acs`)

**Grain:** one row per 2010-vintage California census tract.
**Key:** `tr2010_id` (unique, non-missing).

## Column conventions

The full `tract_vars` mapping is shared by both tract requests: **65 aliases
cover 62 distinct Census codes**. The table is pulled in **wide** format. Each
distinct analytic measure appears as **two columns**:

- `<name>E` — the ACS point estimate
- `<name>M` — the 90% margin of error

Plus the non-suffixed identifier/label and flag columns at the bottom.
The three duplicate-code aliases (`grent_3`, `grent_20`, `grent_26`) stay in the
request mapping; tidycensus returns these codes under their first aliases
(`grentcat1`, `grentcat18`, `grentcat24`), without separate duplicate pairs.
Requested-alias counts therefore differ from returned-column counts.

All selected B25111 measures (including its total) and B25113 measures are
removed. The three B25031 bedroom-rent pairs remain in both tract outputs;
only the [block-group output](acs_step1_2024_block_group.md) excludes them.

## Identifier columns

| column | type | description |
|---|---|---|
| `tr2010_id` | character | 11-digit tract GEOID (renamed from `GEOID`). Table key. |
| `NAME` | character | Census long name for the tract. |

## Analytic mapping (distinct measures returned as `<name>E` and `<name>M`)

| name | census var | description |
|---|---|---|
| `pop` | B01003_001 | Total population |
| `pop_rent` | B25008_003 | Population in renter-occupied housing units |
| `hu` | B25001_001 | Total housing units |
| `hh` | B11001_001 | Total households |
| `sfd_base` | B25024_001 | Units in structure — total (denominator) |
| `sfd_det` | B25024_002 | 1-unit, detached |
| `sfd_att` | B25024_003 | 1-unit, attached |
| `duplex` | B25024_004 | 2 units |
| `quadplex` | B25024_005 | 3 or 4 units |
| `mf_5_9` | B25024_006 | 5 to 9 units |
| `mf_10_19` | B25024_007 | 10 to 19 units |
| `mf_20_49` | B25024_008 | 20 to 49 units |
| `mf_50` | B25024_009 | 50 or more units |
| `mobhm` | B25024_010 | Mobile home |
| `oth_units` | B25024_011 | Boat, RV, van, etc. |
| `rhu_base` | B25003_001 | Occupied units by tenure — total (denominator) |
| `rhu` | B25003_003 | Renter-occupied housing units |
| `ohu` | B25003_002 | Owner-occupied housing units |
| `rent` | B25064_001 | Median gross rent (dollars) |
| `rent1bdr` | B25031_003 | Median gross rent, 1 bedroom |
| `rent2bdr` | B25031_004 | Median gross rent, 2 bedrooms |
| `rent3bdr` | B25031_005 | Median gross rent, 3 bedrooms |
| `rhutot` | B25063_001 | Renter units with gross rent computed — total |
| `rhucash` | B25063_002 | With cash rent |
| `rhunocash` | B25063_027 | No cash rent |
| `grentcat1`–`grentcat24` | B25063_003 – B25063_026 | Gross rent distribution bins, low→high (<$100 … $3,500+) |
| `med_hval` | B25077_001 | Median house value (dollars) |
| `pop_race` | B02001_001 | Race — total population (denominator) |
| `pop_blk` | B02001_003 | Black or African American population |
| `pop_aa` | B02001_005 | Asian population |
| `pop_ethn` | B03003_001 | Hispanic-origin — total population (denominator) |
| `pop_hsp` | B03003_003 | Hispanic or Latino population |
| `lqcrent` | B25057_001 | Lower contract rent quartile (dollars) |
| `grent_3` | B25063_003 | Gross rent < $100 (duplicate of `grentcat1`) |
| `grent_20` | B25063_020 | Gross rent $1,000–1,249 (duplicate of `grentcat18`) |
| `grent_26` | B25063_026 | Gross rent $3,500+ (duplicate of `grentcat24`) |
| `med_hhinc` | B19013_001 | Median household income (dollars) |
| `tot_vac_base` | B25002_001 | Occupancy status — total (denominator) |
| `tot_vac` | B25002_003 | Vacant housing units |
| `vac_forrent` | B25004_002 | Vacant units for rent (available rental units) |
| `vac_rented` | B25004_003 | Vacant units rented, not occupied |
| `vac_forsale` | B25004_004 | Vacant units for sale only (available for-sale units) |

## Flag columns

| column | type | description |
|---|---|---|
| `rent_id` | logical | Join flag, constant `TRUE` (marks rows sourced from an ACS rent table). |

The derived low-rent counts `rhu_lrE` and `rhu_lr2E` are retired and must be
absent. All source estimates/MOEs and all 24 gross-rent bins remain unchanged;
see the [cleanup contract](../docs/measure_cleanup.md).

**Downstream:** Stage 2 passes through this revised schema and adds
`rhu_inventoryE = rhuE + vac_forrentE + vac_rentedE`, propagating any missing
required estimate. Its explicit `schema_migration = "2016"` parity mode permits
only the seven removed measure pairs, the two low-rent counts, and additions `vac_rentedE/M` and
`rhu_inventoryE` against older snapshots; shared columns remain strictly checked.
See the [migration and parity compatibility](../README.md#stage-1-input-migration).
Generate this file from the revised stage 1; retain the old cache as historical data.
