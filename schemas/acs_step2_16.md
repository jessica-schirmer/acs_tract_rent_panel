# Schema: `acs_step2_16.feather`

**Produced by:** `02_assemble.Rmd` (Step 2) · **Source:** `acs_step1_16.feather`

**Grain:** one row per 2010-vintage California tract **in the five SCAG-region
counties** (Los Angeles 037, Orange 059, Riverside 065, San Bernardino 071,
Ventura 111).
**Key:** `tr2010_id` (unique, non-missing).

This file is the 2012–2016 tract table restricted to the SCAG region, with
top-code/missing/zero flags, structure-type aggregates, and share/CV measures
added.

## Base columns

All columns from `acs_step1_16.feather` carry through — see
`schemas/acs_step1_16.md` for the full `<name>E` / `<name>M` measure list, plus
`tr2010_id`, `NAME`, `rhu_lrE`, `rhu_lr2E`, and `rent_id`. Note that `rentE` and
`lqcrentE` are **censored** here: values `>= 3500` are set to `NA` (top-code
removal). See the §2.4 / §3.2 decision blocks in the notebook.

## Added structure-type aggregates

| column | type | description |
|---|---|---|
| `mf5E` | numeric | Multifamily units in 5+ structures: `mf_5_9E + mf_10_19E + mf_20_49E + mf_50E` (renamed from `mfE`). |
| `smfE` | numeric | Small multifamily: `sfd_attE + duplexE + quadplexE`. |
| `nsfaE` | numeric | Non-single-family **attached** units: `smfE + mf5E`; excludes single-family detached, mobile homes, and other units. |

## Added share measures

| column | type | description |
|---|---|---|
| `pctrhuE` | numeric | Renter-occupied share of housing units (`rhuE / huE`). |
| `pctvacE` | numeric | Vacant share (`tot_vacE / tot_vac_baseE`). |
| `pctblkE` | numeric | Black share of population (`pop_blkE / pop_raceE`). |
| `pcthspE` | numeric | Hispanic share (`pop_hspE / pop_ethnE`). |
| `pctaaE` | numeric | Asian share (`pop_aaE / pop_raceE`). |
| `pctsfdE` | numeric | Single-family-detached share (`sfd_detE / sfd_baseE`). |
| `pctrvacE` | numeric | Rental vacancy rate (`vac_forrentE / (rhuE + vac_forrentE)`); `NA` if denominator ≤ 0. |
| `pctsvacE` | numeric | For-sale vacancy rate (`vac_forsaleE / (ohuE + vac_forsaleE)`); `NA` if denominator ≤ 0. |

## Added margin-of-error / coefficient-of-variation measures

| column | type | description |
|---|---|---|
| `pctrhuM`, `pctblkM`, `pcthspM` | numeric | Derived MOEs for the corresponding share measures (ratio MOE formula). |
| `rentCV`, `med_hhincCV`, `med_hvalCV` | numeric | CVs for median rent / income / value (`(M/1.645)/E`). |
| `pctrhuCV`, `pctblkCV`, `pcthspCV` | numeric | CVs for the corresponding shares. |
| `rhuCV`, `huCV`, `popCV` | numeric | CVs for renter units / housing units / population. |

## Data-quality flag columns (0/1 integers)

| column pattern | description |
|---|---|
| `tc_flag_rent`, `tc_flag_lqcrent`, `tc_flag_med_hval` | 1 if top-coded (rent/lqcrent `>= 3500`; median value `>= 2,000,000`). |
| `m_flag_rent`, `m_flag_lqcrent`, `m_flag_rhu`, `m_flag_rhucash`, `m_flag_med_hval` | 1 if the estimate is missing (`NA`). |
| `zero_flag_rhu`, `zero_flag_rhucash`, `zero_flag_med_hval` | 1 if the estimate is zero. |

**Known quirk (carried unchanged from source logic):** `censor_tc_vars()` censors
`med_hhincE` using the condition `rentE >= 2000000`, which never fires — so
`med_hhincE` is effectively not censored in this stage. Flagged for awareness; not
modified.
