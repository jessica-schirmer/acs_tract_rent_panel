# Schema: `xwalk_tr20_tr10.feather`

**Produced by:** `03_tract_change.Rmd` (Step 3).
**Source:** U.S. Census Bureau 2020-to-2010 tract relationship file,
`../../../data-raw-temp/census/tab20_tract20_tract10_st06.txt`.
The UTF-8, pipe-delimited source describes geographic intersections between
2020 and 2010 census tracts. It is read without modification.

**Grain:** one row per California 2020 tract present in the complete source.
**Key:** `tr2020_id` (11-digit character, unique and non-missing).
**Output:** `../../../data/xwalk_tr20_tr10.feather`.

## Columns

| Column | R storage type | Description |
|---|---|---|
| `tr2020_id` | character | `GEOID_TRACT_20`; always begins with `06`. |
| `tr2010_id` | character | `GEOID_TRACT_10` when exactly one 2010 partner exists; otherwise `NA`. |
| `geo_consistent` | double | Non-missing 0/1 flag for the exact geographic-consistency rule below. |
| `same_geoid` | double | 0/1 for equal GEOIDs on a uniquely linked pair; `NA` for multiple 2010 partners. Diagnostic only. |
| `relationship_class` | character | One of the five classifications below. Never missing. |
| `zero_land_area` | double | Non-missing 0/1 flag: any associated relationship has zero total land area for either tract. A zero intersection alone does not set this flag. |
| `n_2010_partners` | integer | Distinct 2010 partners of this 2020 tract, counted from the complete source. At least 1. |
| `n_2020_partners` | integer | Distinct 2020 partners of the uniquely linked 2010 tract; `NA` when multiple 2010 partners exist. |
| `max_n_2020_partners` | integer | Maximum reverse partner count across all linked 2010 tracts. Retained for tract-classification QA. |
| `share_2020_land` | double | `AREALAND_PART / AREALAND_TRACT_20` on a unique link with a positive denominator; otherwise `NA`. |
| `share_2010_land` | double | `AREALAND_PART / AREALAND_TRACT_10` on a unique link with a positive denominator; otherwise `NA`. |
| `arealand_2020` | double | `AREALAND_TRACT_20`, total 2020 land area in square meters. Always retained. |
| `arealand_2010` | double | `AREALAND_TRACT_10`, total 2010 land area in square meters on a unique link; otherwise `NA`. |
| `arealand_part` | double | `AREALAND_PART`, intersection land area in square meters on a unique link; otherwise `NA`. |

Area values are non-missing, finite, nonnegative whole numbers in the source.
They are stored as doubles to accommodate areas larger than a 32-bit integer;
values must remain below `2^53` for exact integer representation. Shares are in
[0, 1]. Data-quality flags follow the existing numeric double 0/1 convention.

## Geographic consistency

`geo_consistent = 1` requires **all six conditions** on a relationship:

1. `n_2010_partners == 1`;
2. `n_2020_partners == 1`;
3. `arealand_2020 > 0`;
4. `arealand_2010 > 0`;
5. `arealand_part == arealand_2020`; and
6. `arealand_part == arealand_2010`.

Equality is exact on land areas; there is no near-match threshold. Both shares
must equal 1 for a consistent pair. Zero-land-area pairs are excluded even when
all area fields equal zero. A share with a zero denominator is `NA`; the other
share is still calculated if its own denominator is positive.

`same_geoid` does not enter this rule. Consistent pairs can have different IDs,
and equal IDs do not establish consistency. No water, population, housing, or
allocation measures enter this stage.

## Relationship classification

| Class | Tract-level rule |
|---|---|
| `consistent` | The complete six-condition rule holds. |
| `one_to_one_changed` | Both partner counts equal 1, but the consistency rule fails. Includes one-to-one zero-land-area pairs. |
| `split` | Exactly one 2010 partner, whose `n_2020_partners > 1`. |
| `merge` | Multiple 2010 partners, all with `n_2020_partners == 1`. |
| `many_to_many` | Multiple 2010 partners and **any** partner has `n_2020_partners > 1`. |

The analyst selected the last rule for tracts with a mixture of pair-level
`merge` and `many_to_many` relationships. The pair-level diagnostic table retains
each row's own class. That full table remains in the notebook; this file never
selects a dominant partner or aggregates pair-specific areas/shares into an
apparently unique crosswalk. A unique 2010 ID is retained even for changed
tracts, so consumers must explicitly select `geo_consistent == 1`.

## Coverage, diagnostics, and downstream use

Counts include every source relationship, including zero-land intersections and
links to 2010 tracts outside California. Both source IDs must have 11 digits;
only 2020 IDs must begin with `06`. Reverse partner counts describe this file,
not a national relationship universe. Intersections in this California file
need not sum to every 2010 tract's full land area. The notebook reports those
differences without renormalizing or dropping relationships.

After selecting consistent rows, join native-2020 2024 ACS measures on
`tr2020_id`, then corresponding 2016 ACS measures on the explicit `tr2010_id`.
Both IDs are unique within the consistent subset. This stage does not merge ACS
measures, allocate changed tracts, or restrict to the Step 2 target counties.
The existing Step 4 panel does not yet consume this crosswalk.

The notebook reports source path, size, and MD5 for provenance; source/pair and
tract counts; consistent count/percentage; class counts; zero-land relationships;
same/different consistent GEOIDs; non-consistent pair share distributions; and
land-area reconciliation diagnostics. It validates membership, keys, missingness,
types, flags, ranges, classifications, and saved Feather values. Unexpected
structural source conditions stop execution rather than triggering repairs.

Saving refuses an existing destination unless `overwrite_output` is explicitly
enabled; replacement is announced. The historical `tract_change.feather` and
raw source are preserved.
