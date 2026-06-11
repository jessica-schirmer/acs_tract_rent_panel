# Schema: `acs_full.feather`

**Produced by:** `03_merge.Rmd` (Step 3) · **Source:** `acs_step2_16.feather` + `acs_step2_23.feather`

**Grain:** one row per 2010-vintage tract in the SCAG region (the union of tracts
present in either survey; the merge keeps all tracts).
**Key:** `tr2010_id` (unique, non-missing).

This is the analysis panel: 2012–2016 and 2019–2023 tract measures side by side,
with the 2016 dollar values inflation-adjusted to 2023 dollars, plus
period-change ("POST") ratios.

## Year-suffixed level measures

The analytic measures from each survey carry a `_16` (2012–2016) or `_23`
(2019–2023) suffix. For each survey the following appear (see
`schemas/acs_step2_16.md` / `schemas/acs_step2_23.md` for definitions):

- **Estimates `_{yr}`:** `rentE`, `lqcrentE`, `popE`, `huE`, `rhuE`, `med_hvalE`,
  `rhu_lrE`, `rhu_lr2E`, `med_hhincE`, `pctrhuE`, `pctvacE`, `pctblkE`, `pcthspE`,
  `pctaaE`, `pctsfdE`, `mf5E`, `nsfaE`, `pctrvacE`, `pctsvacE`.
  (`mf5E` = units in 5+ structures, renamed from `mfE`; `nsfaE` =
  non-single-family attached count; `pctrvacE` / `pctsvacE` = rental / for-sale
  vacancy rates. These carry no MOE/CV column.)
- **Margins of error `_{yr}`:** `rentM`, `lqcrentM`, `popM`, `huM`, `rhuM`,
  `med_hvalM`, `med_hhincM`, `pctrhuM`, `pctblkM`, `pcthspM`.
- **Coefficients of variation `_{yr}`:** `rentCV`, `popCV`, `huCV`, `rhuCV`,
  `med_hvalCV`, `med_hhincCV`, `pctrhuCV`, `pctblkCV`, `pcthspCV`.

**Inflation adjustment:** the 2016 dollar estimates/MOEs (`rentE_16`,
`lqcrentE_16`, `med_hhincE_16`, `med_hvalE_16`, and the `*M_16` counterparts) are
multiplied by **1.27** to express them in 2023 dollars.

## Extra carried columns

| column | source | description |
|---|---|---|
| `interp_rent` | 2023 | Interpolated median rent (2023 only; not suffixed). |
| `pct_miss_rent`, `pct_miss_hval` | 2023 | Share of weighted units missing rent / value. |
| `tc_flag_rent_23` | 2023 | 1 if the tract had top-coded renter rent (0/1). |
| `m_flag_rent`, `m_flag_lqcrent`, `m_flag_rhu`, `m_flag_med_hval` | 2016 | Missing-value flags (0/1). |
| `zero_flag_rhu` | 2016 | Zero renter-units flag (0/1). |
| `tc_flag_rent`, `tc_flag_lqcrent`, `tc_flag_med_hval` | 2016 | Top-code flags (0/1). |

## Change measures

**Level changes (ratios, `*POST`).** Dollar- and count-denominated measures use
the ratio of the 2023 value to the inflation-adjusted 2016 value, defined only
where the 2016 denominator is positive (else `NA`).

| column | definition |
|---|---|
| `rentPOST` | `rentE_23 / rentE_16` |
| `interp_rentPOST` | `interp_rent / rentE_16` |
| `lqcrentPOST` | `lqcrentE_23 / lqcrentE_16` |
| `huPOST` | `huE_23 / huE_16` |
| `rhuPOST` | `rhuE_23 / rhuE_16` |
| `rhu_lrPOST`, `rhu_lr2POST` | low-rent renter-unit change ratios |
| `med_hhincPOST` | `med_hhincE_23 / med_hhincE_16` |
| `popPOST` | `popE_23 / popE_16` |

**Share / rate changes (percentage-point differences, `*PPC`).** Share and rate
measures use `value_23 − value_16` (range ≈ [−1, 1]), defined wherever both
periods are present (`NA` only if a period is missing).

| column | definition |
|---|---|
| `pctrhuPPC` | `pctrhuE_23 − pctrhuE_16` (renter-occupied share) |
| `pctvacPPC` | `pctvacE_23 − pctvacE_16` (overall vacant share) |
| `pctrvacPPC` | `pctrvacE_23 − pctrvacE_16` (rental vacancy rate) |
| `pctsvacPPC` | `pctsvacE_23 − pctsvacE_16` (for-sale vacancy rate) |

**Change-measure MOE/CV:** `moe_rentPOST`, `moe_rhuPOST`, `moe_med_hhincPOST`
(ratio-MOE propagation) and `rentPOSTCV`, `rhuPOSTCV`, `med_hhincPOSTCV`.

**Change flags (0/1):** `m_flag_rentPOST`, `m_flag_rhuPOST`.

## Join-indicator columns

| column | type | description |
|---|---|---|
| `base_id` | logical | Constant `TRUE` (set after the merge). |
| `post_id` | logical | `TRUE` if the tract is present in the 2023 survey, else `NA`. |
| `rent_id`, `rhu_id` | logical | Upstream join tags carried from the step-2 inputs. |
