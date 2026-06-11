# Schema: `acs_step1_16.feather`

**Produced by:** `01_acs.Rmd` (Step 1) · **Source:** 2012–2016 ACS 5-year, tract level, California (`tidycensus::get_acs`)

**Grain:** one row per 2010-vintage California census tract.
**Key:** `tr2010_id` (unique, non-missing).

## Column conventions

The table is pulled in **wide** format. Each analytic measure listed below
appears as **two columns**:

- `<name>E` — the ACS point estimate
- `<name>M` — the 90% margin of error

Plus the non-suffixed identifier/label and derived/flag columns at the bottom.

## Identifier columns

| column | type | description |
|---|---|---|
| `tr2010_id` | character | 11-digit tract GEOID (renamed from `GEOID`). Table key. |
| `NAME` | character | Census long name for the tract. |

## Analytic measures (each present as `<name>E` and `<name>M`)

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
| `rentmv1yr` | B25113_002 | Median gross rent, householder moved in most recent period |
| `rentmv5yr` | B25113_003 | Median gross rent, householder moved in prior period |
| `rent1bdr` | B25031_003 | Median gross rent, 1 bedroom |
| `rent2bdr` | B25031_004 | Median gross rent, 2 bedrooms |
| `rent3bdr` | B25031_005 | Median gross rent, 3 bedrooms |
| `rentyrblt` | B25111_001 | Median gross rent by year built — total |
| `rentyrblt_14_16` | B25111_002 | Median gross rent, built 2014 or later |
| `rentyrblt_10_13` | B25111_003 | Median gross rent, built 2010–2013 |
| `rentyrblt_00_09` | B25111_004 | Median gross rent, built 2000–2009 |
| `rentyrblt_90_99` | B25111_005 | Median gross rent, built 1990–1999 |
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
| `vac_forsale` | B25004_004 | Vacant units for sale only (available for-sale units) |

## Derived and flag columns

| column | type | description |
|---|---|---|
| `rhu_lrE` | numeric | Low-rent renter housing units: row sum of `grentcat1E`–`grentcat17E`. Cutoff at category 17 (~$900–999) for the 2016 vintage. |
| `rhu_lr2E` | numeric | Wider low-rent count: row sum of `grentcat1E`–`grentcat19E` (~$1,250–1,499). |
| `rent_id` | logical | Join flag, constant `TRUE` (marks rows sourced from an ACS rent table). |

**Note on year-specific cutoffs:** `rhu_lrE` / `rhu_lr2E` use categories 1–17 /
1–19 here; the 2024 file (`acs_step1_24.feather`) shifts these up one bin
(1–18 / 1–20) to hold the real rent threshold roughly constant. See the decision
blocks in `01_acs.Rmd` §3.2 and §4.2.
