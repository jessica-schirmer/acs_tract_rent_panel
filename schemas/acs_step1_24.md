# Schema: `acs_step1_24.feather`

**Produced by:** `01_acs.Rmd` (Step 1) · **Source:** 2020–2024 ACS 5-year, **block-group** level, California (`tidycensus::get_acs`)

**Grain:** one row per 2020-vintage California census block group.
**Key:** `bg2020_id` (unique, non-missing).

This file shares the **same variable layout** as `acs_step1_16.feather` — the
extraction uses the identical variable set (`v24_save <- v16_save`). The
differences are the geographic grain (block group, not tract), the key column
name, and the low-rent cutoffs used for the derived columns.

## Column conventions

Wide format: each analytic measure appears as `<name>E` (estimate) and `<name>M`
(90% margin of error). See `acs_step1_16.md` for the full measure-by-measure
table (`pop`, `rent`, `rhu`, structure-type counts, gross-rent categories
`grentcat1`–`grentcat24`, race/ethnicity, income, vacancy status, etc.) — the
codes and meanings are identical, including the B25004 vacancy-status detail
`vac_forrent` (B25004_002, for rent) and `vac_forsale` (B25004_004, for sale only).

## Identifier columns

| column | type | description |
|---|---|---|
| `bg2020_id` | character | 12-digit block-group GEOID (renamed from `GEOID`). Table key. |
| `NAME` | character | Census long name for the block group. |

## Derived and flag columns

| column | type | description |
|---|---|---|
| `rhu_lrE` | numeric | Low-rent renter housing units: row sum of `grentcat1E`–`grentcat18E`. Cutoff at category **18** (~$1,000–1,249) for the 2024 vintage — one bin higher than the 2016 file. |
| `rhu_lr2E` | numeric | Wider low-rent count: row sum of `grentcat1E`–`grentcat20E` (~$1,500–1,999). |
| `rent_id` | logical | Join flag, constant `TRUE`. |

**Downstream:** `02_assemble.Rmd` aggregates this block-group table up to 2010
tracts using `xwalk_bg24_tr10.feather`. See the decision block in `01_acs.Rmd`
§4.1 for why these data are pulled at the block-group level.
