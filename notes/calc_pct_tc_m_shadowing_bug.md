# Finding: `calc_pct_tc_m()` name-shadowing bug — and why `pct_miss_rent` was unaffected

**Date:** 2026-06-12
**Fixed in commit:** `1a7ac1a` ("Carry corrected pct_tc_rent share into acs_full; fix calc_pct_tc_m shadowing bug")
**Files:** `R/assemble_helpers.R` (`calc_pct_tc_m()`), surfaced while adding `pct_tc_rent` to `02_assemble.Rmd` / `03_merge.Rmd`.

## Summary

While adding the tract-level top-coded-rent share (`pct_tc_rent`) to the
outputs, verification on real `acs_step1_*` data showed it taking impossible
values (up to 9; 154 tracts > 1). The cause was a pre-existing bug in
`calc_pct_tc_m()`. **The separately-computed `pct_miss_rent` — the
percent-missing-rent variable saved to the data and used downstream — was not
affected and remains correct.**

## The bug

In `calc_pct_tc_m()` the `summarise()` named the tract-total denominator `rhuE`:

```r
summarise(
  rhuE        = sum(rhuE * wt_renthu, na.rm = TRUE),                 # tract total
  rhu_m_rent  = sum(is.na(rentE) * rhuE * wt_renthu, na.rm = TRUE),  # <- rhuE here is now the TOTAL
  rhu_tc_rent = sum((... & rhuE!=0 & ... & rentE >= 3500) * rhuE * wt_renthu, na.rm = TRUE),
  ...
)
```

dplyr evaluates `summarise()` arguments in order, so once `rhuE` is created as
the tract total, the later numerator expressions see that **scalar total**, not
the original block-group `rhuE` vector. The total then cancels in the division
`rhu_* / rhuE`, leaving `sum(weights over qualifying block groups)` — a **sum of
allocation weights, not a share**. Hence values above 1.

**Fix:** rename the denominator to `rhuE_tot` so it no longer shadows the
block-group column. Both `pct_m_rent` and `pct_tc_rent` then become true shares
in `[0, 1]`.

## What was and was not affected

| Variable | Computed by | Affected? | Notes |
|---|---|---|---|
| **`pct_miss_rent`** (saved; used downstream) | `calc_agg_vars()` → `calc_missing_vars()` | **No — correct** | `calc_agg_vars()` names its aggregate `rhuE_agg` (suffix avoids the shadow), so its `rhu_miss_rent` numerator weights by the block-group `rhuE`. |
| `pct_m_rent`, `pct_tc_rent` | `calc_pct_tc_m()` | Yes — buggy pre-`1a7ac1a` | **Never saved** to any output. Appeared only in the §2.3 in-notebook diagnostic printout (`check_tc_out`). |
| `tc_flag_rent_24` (`= pct_tc_rent > 0`) | `02_assemble.Rmd` §2.3 | No change | The flag is identical before/after the fix (0 tracts change). |

## Magnitudes (real `acs_step1_24` data, SCAG region)

Historical filename: these magnitudes use the original `acs_step1_24.feather`
cache. Since the 2026-09-12 stage-1 revision, its current counterpart is
`acs_step1_2024_block_group.feather`, with a revised variable contract requiring
regeneration. The recorded findings refer to the original input; see the
[migration note](../README.md#stage-1-input-migration).

| measure | buggy (old §2.3 printout) | corrected |
|---|---|---|
| `pct_m_rent` | mean **0.55**, max **8.0**, 558 tracts > 1 | mean 0.084, max 1.0 |
| `pct_tc_rent` | mean **0.20**, max **9.0**, 154 tracts > 1 | mean 0.065, max 1.0 |
| `pct_miss_rent` | — *(unaffected)* | mean **0.149**, max 1.0 |

## Effect on previously reported estimates

- Estimates pulled from **`pct_miss_rent`** (the saved dataset, the §2.9 / §4
  validation summaries, or downstream analysis) are **correct** — no revision
  needed. A tract-average missing-rent share around **~15%** is the right figure.
- Any missing-/top-coded-rent figure read off the **§2.3 diagnostic table**
  (`pct_m_rent` / `pct_tc_rent`) before `1a7ac1a` was inflated. Those values were
  self-evidently broken as percentages (means of 55% / 20%, maxima of 800% /
  900%), so they were unlikely to have been reported as-is.

## Definitional note (not a bug)

`pct_miss_rent` counts top-coded block groups as "missing" because top-coded
`rentE` is censored to `NA` before aggregation (§2.4). So it decomposes as:

```
pct_miss_rent  ≈  pct_m_rent  +  pct_tc_rent
   (≈0.149)        (≈0.084)       (≈0.065)
 missing|tc      truly missing    top-coded
```

verified to ~1e-16 on the real data. The newly-saved `pct_tc_rent` isolates the
top-coded slice; the corrected `pct_m_rent` is the genuinely-missing slice. This
is documented in `02_assemble.Rmd` §2.6.
