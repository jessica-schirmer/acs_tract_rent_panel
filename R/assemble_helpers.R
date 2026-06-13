# assemble_helpers.R -----------------------------------------------------
# Helper functions for 02_assemble.Rmd (Step 2: assemble geographically
# consistent 2010-tract measures from 2020-2024 block groups, and prepare the
# 2012-2016 tract measures).
#
# This file is intentionally SELF-CONTAINED: 02_assemble.Rmd sources only this
# file. It therefore carries its own copies of a few small generic/diagnostic
# helpers (save_data, report_n, report_drop, print_numeric_summary, fmt_num) and
# its own `summ_var()` — which is a DISTRIBUTION-focused variant, distinct from
# the MOE/CV-focused `summ_var()` in R/helpers.R used by 01_acs.Rmd. Keeping the
# two notebooks' helpers in separate files avoids a name collision.
#
# Assumes the calling notebook has already loaded dplyr/tidyr/stringr/purrr
# (tidyverse), Hmisc / matrixStats (for weightedMean), and arrow.
#
# Load at the top of the notebook with:
#   source(here::here("R", "assemble_helpers.R"))


# ---- I/O helpers -------------------------------------------------------------

#' Load feather data with optional subfolder
#'
#' @param path Base data directory path
#' @param folder Optional subfolder name (NULL if file is in base directory)
#' @param name Filename including extension
#' @return Data frame from feather file
load_data <- function(path, folder = NULL, name) {
  file_path <- if (!is.null(folder)) {
    file.path(path, folder, name)
  } else {
    file.path(path, name)
  }

  if (!file.exists(file_path)) {
    stop("File not found: ", file_path)
  }

  arrow::read_feather(file_path)
}


#' Save data
#'
#' @param df Data frame
#' @param dir Directory (with trailing slash)
#' @param name File name including extension
#' @return Invisibly, the input df (after writing)
save_data <- function(df, dir, name) {
    df |>
        arrow::write_feather(paste0(dir,name))
}


# ---- Merge / filter helpers --------------------------------------------------

#' Merge data
#'
#' @param left_df left dataframe
#' @param right_df right dataframe
#' @param key_id join key column name
#' @return Merged dataframe with a `merge` indicator ("both"/"left_only"/"right_only")
merge_df <- function(left_df, right_df, key_id) {
  left_df |>
    select(-any_of(c("left_id", "right_id"))) |>
    mutate(left_id = TRUE) |>
    full_join(
      right_df |>
        select(-any_of(c("left_id", "right_id"))) |>
        mutate(right_id = TRUE),
      by = key_id
    ) |>
    mutate(
      merge = case_when(
        left_id == TRUE & right_id == TRUE ~ "both",
        left_id == TRUE & is.na(right_id) ~ "left_only",
        is.na(left_id) & right_id == TRUE ~ "right_only",
        .default = NA_character_
      )
    ) |>
    as_tibble()
}


#' Select target counties
#'
#' @param df A data frame
#' @param id Name of the ID column to filter on (unquoted)
#' @param target_counties Vector of target county codes
#' @return Data frame filtered to target counties
select_target_counties <- function(df, id, target_counties) {
  df <- df |>
    dplyr::filter((substr({{ id }}, 1, 2) == "06") &
                  (substr({{ id }}, 3, 5) %in% target_counties))
  return(df)
}


# ---- Top-code / missing / zero flagging --------------------------------------

#' Check top-coded values
#'
#' @param df Data frame
#' @param var_name ACS estimate name
#' @return Summary statistics, including number top-coded
check_tc <- function(df, var_name) {
  moe_name <- sub("E$", "M", var_name)
  cv_name <- sub("E$", "CV", var_name)
  summarise(
    df,
    var        = var_name,
    n          = sum(!is.na(.data[[var_name]])),
    n_missing  = sum(is.na(.data[[var_name]])),
    n_tc       = sum((.data[[var_name]]>=3500) , na.rm=TRUE),
    n_no_tc   = sum((.data[[var_name]]<3500) , na.rm=TRUE),
    # n_tc       = sum((.data[[var_name]]==3501 | .data[[var_name]]==3500), na.rm=TRUE),
    min        = min(.data[[var_name]],  na.rm = TRUE),
    max        = max(.data[[var_name]],  na.rm = TRUE),
  )
}

#' Flag missing variables
#'
#' @param df
#' @param var_list
#' @return Creates a flag equal to 1 if missing, 0 if non-missing
flag_missing_vars <- function(df, var_list) {
    for (i in var_list){
        flag_name <- paste0("m_flag_", sub("E.*", "", i))
        df <- df |>
            mutate(!!flag_name := if_else(is.na(.data[[i]]), 1,0)   # Flag tracts missing median rent, with rent housing units that rent for cash)
             )
    }
    return(df)
}

#' Check missing variables
#'
#' @param df
#' @param var_list
#' @return Creates a flag equal to 1 if missing, 0 if non-missing
check_missing_vars <- function(df, var_list) {
  map_dfr(var_list, function(i) {
    flag_name <- paste0("m_flag_", sub("E.*", "", i))
    tibble(
      variable = i,
      flag = flag_name,
      n_missing = sum(df[[flag_name]] == 1, na.rm = TRUE),
      n_present = sum(df[[flag_name]] == 0, na.rm = TRUE),
      pct_missing = mean(df[[flag_name]], na.rm = TRUE) * 100
    )
  })
}

#' Flag zero val variables
#'
#' @param df
#' @param var_list
#' @return Creates a flag equal to 1 if zero, 0 if non-zero
flag_zero_vars <- function(df, var_list) {
    for (i in var_list){
        flag_name <- paste0("zero_flag_", sub("E.*", "", i))
        df <- df |>
            mutate(!!flag_name := if_else(.data[[i]]==0, 1,0)   # Flag tracts with 0 values
             )
    }
    return(df)
}

#' Flag top-coded variables
#'
#' Rent variables are top-coded at $3,500; median house value at $2,000,000.
#' (An earlier, superseded definition of this function — which top-coded any
#' variable at 3500 conditional on rhuE — was removed; this grepl-dispatched
#' version is the one the notebook actually used.)
#'
#' @param df
#' @param var_list
#' @return Creates a flag equal to 1 if top-coded, 0 if not top-coded
flag_tc_vars <- function(df, var_list) {
    for (i in var_list){
        flag_name <- paste0("tc_flag_", sub("E.*", "", i))
        if (grepl("rent", i)) {
        df <- df |>
            mutate(!!flag_name := if_else(.data[[i]]>=3500, 1,0))
        }
        else if (grepl("med_hval", i)) {
            df <- df |>
                mutate(!!flag_name := if_else(.data[[i]]>=2000000, 1,0))
        }
    }
    return(df)
}


# ---- Weighting / aggregation -------------------------------------------------

#' Calculate relative weight
#'
#' @param df
#' @param id grouping geographic id (unquoted)
#' @return Creates a relative weight for count variables
calc_rel_wt <- function(df, id) {
  df |>
    group_by({{id}}) |>
    mutate(
    #   moe_wt_rhu = rhuE * wt_renthu / sum(rhuE * wt_renthu, na.rm = TRUE),
    #   moe_wt_hu = huE * wt_hu / sum(huE * wt_hu, na.rm = TRUE),
    #   moe_wt_pop = popE * wt_pop / sum(popE * wt_pop, na.rm = TRUE)
      rel_wt_rhu = rhuE * wt_renthu / sum(rhuE * wt_renthu, na.rm = TRUE),
      rel_wt_hu = huE * wt_hu / sum(huE * wt_hu, na.rm = TRUE),
      rel_wt_pop = popE * wt_pop / sum(popE * wt_pop, na.rm = TRUE)
    ) |>
    ungroup()
}


#' Calculate % missing / top-coded rent at the tract level
#'
#' Returns the weighted share of renter housing units per tract whose
#' block-group rent is missing (`pct_m_rent`) or top-coded (`pct_tc_rent`),
#' computed on the **uncensored** block-group rent. Both are true shares in
#' `[0, 1]`: numerator is the weighted renter units in the qualifying block
#' groups, denominator the tract's total weighted renter units.
#'
#' NOTE: the denominator summary is named `rhuE_tot` (not `rhuE`) deliberately.
#' `summarise()` evaluates its expressions in order, so naming it `rhuE` would
#' shadow the block-group `rhuE` column in the later numerator expressions,
#' collapsing them to the tract total and turning each "share" into a sum of
#' weights (values > 1). Keeping the names distinct preserves the intended
#' per-block-group weighting.
#'
#' @param df
#' @param id grouping geographic id (unquoted)
#' @return dataframe with % missing / % top-coded rent calculations
calc_pct_tc_m <- function(df, id) {
  tr_df <- df |>
    group_by({{id}}) |>
    summarise(
    #   huE     = sum(huE * wt_hu, na.rm = TRUE),
      rhuE_tot    = sum(rhuE * wt_renthu, na.rm = TRUE),
      rhu_m_rent = sum(is.na(rentE) * rhuE * wt_renthu, na.rm = TRUE),
      rhu_tc_rent = sum((!is.na(rhuE) & rhuE!=0 & !is.na(rentE) & rentE >= 3500) * rhuE * wt_renthu, na.rm = TRUE),
    #   hu_tc_hval = sum((!is.na(med_hvalE) & med_hvalE >= 2000000) * huE * wt_hu, na.rm = TRUE),
      .groups = "drop"
    )

  tr_df <- tr_df |>
    mutate(pct_m_rent = if_else(rhuE_tot > 0, rhu_m_rent / rhuE_tot, NA_real_),
            pct_tc_rent = if_else(rhuE_tot > 0, rhu_tc_rent / rhuE_tot, NA_real_),

         ) |>
    select({{id}}, pct_m_rent, pct_tc_rent)

  return(tr_df)
}


#' Censor top-coded
#'
#' @param df
#' @return dataframe with censored top-coded variables
censor_tc_vars <- function(df) {
  df |>
    mutate(rentE=ifelse(rentE>=3500,NA, rentE),
           lqcrentE=ifelse(lqcrentE>=3500,NA, lqcrentE),
           med_hhincE=ifelse(rentE>=2000000,NA, med_hhincE)
    )

}

#' Calculate aggregated var
#'
#' @param df
#' @param id geographic id to aggregate
#' @return Calculate weight sum/ median
calc_agg_vars <- function(df, id) {
  df |>
    group_by({{id}}) |>
    summarise(
      # Count missing values FIRST using original data
      rhu_miss_rent = sum(if_else(is.na(rentE), rhuE * wt_renthu, 0), na.rm = TRUE),
      hu_miss_hval = sum(if_else(is.na(med_hvalE), huE * wt_hu, 0), na.rm = TRUE),

      # Calculate weighted medians/means BEFORE aggregating the weight variables
      rentE_agg = weightedMean(rentE, w = rhuE * wt_renthu, na.rm = TRUE),
      lqcrentE_agg = weightedMean(lqcrentE, w = rhuE * wt_renthu, na.rm = TRUE),
      med_hhincE_agg = weightedMean(med_hhincE, w = hhE * wt_hh, na.rm = TRUE),
      med_hvalE_agg = weightedMean(med_hvalE, w = huE * wt_hu, na.rm = TRUE),

      rentM_agg = weightedMean(rentM, w = rhuE * wt_renthu, na.rm = TRUE),
      lqcrentM_agg = weightedMean(lqcrentM, w = rhuE * wt_renthu, na.rm = TRUE),
      med_hhincM_agg = weightedMean(med_hhincM, w = rhuE * wt_renthu, na.rm = TRUE),
      med_hvalM_agg = weightedMean(med_hvalM, w = huE * wt_hu, na.rm = TRUE),

      # MOE calculations using row-level data
      rhuM_agg = if (sum(rhuE * wt_renthu, na.rm = TRUE) != 0) sqrt(sum((rhuM * rel_wt_rhu)^2, na.rm = TRUE)) else NA,
      rhu_baseM_agg = sqrt(sum((rhu_baseM * rel_wt_hu)^2, na.rm = TRUE)),
      tot_vacM_agg = sqrt(sum((tot_vacM * rel_wt_hu)^2, na.rm = TRUE)),
      tot_vac_baseM_agg = sqrt(sum((tot_vac_baseM * rel_wt_hu)^2, na.rm = TRUE)),
      pop_blkM_agg = sqrt(sum((pop_blkM * rel_wt_pop)^2, na.rm = TRUE)),
      pop_hspM_agg = sqrt(sum((pop_hspM * rel_wt_pop)^2, na.rm = TRUE)),
      pop_aaM_agg = sqrt(sum((pop_aaM * rel_wt_pop)^2, na.rm = TRUE)),
      pop_raceM_agg = sqrt(sum((pop_raceM * rel_wt_pop)^2, na.rm = TRUE)),
      sfd_detM_agg = sqrt(sum((sfd_detM * rel_wt_hu)^2, na.rm = TRUE)),
      sfd_baseM_agg = sqrt(sum((sfd_baseM * rel_wt_hu)^2, na.rm = TRUE)),
      huM_agg = if (sum(huE * wt_hu, na.rm = TRUE) != 0) sqrt(sum((huM * rel_wt_hu)^2, na.rm = TRUE)) else NA,
      popM_agg = if (sum(popE * wt_pop, na.rm = TRUE) != 0) sqrt(sum((popM * rel_wt_pop)^2, na.rm = TRUE)) else NA,

      # Now aggregate counts (labeled with _agg)
      huE_agg     = sum(huE * wt_hu, na.rm = TRUE),
      rhuE_agg    = sum(rhuE * wt_renthu, na.rm = TRUE),
      rhu_lrE_agg = sum(rhu_lrE * wt_renthu, na.rm = TRUE),
      rhu_lr2E_agg = sum(rhu_lr2E * wt_renthu, na.rm = TRUE),
      rhu_baseE_agg    = sum(rhu_baseE * wt_renthu, na.rm = TRUE),
      hhE_agg     = sum(hhE * wt_hh, na.rm = TRUE),
      popE_agg    = sum(popE * wt_pop, na.rm = TRUE),
      tot_vacE_agg    = sum(tot_vacE * wt_hu, na.rm = TRUE),
      tot_vac_baseE_agg    = sum(tot_vac_baseE * wt_hu, na.rm = TRUE),
      pop_blkE_agg = sum(pop_blkE * wt_pop, na.rm = TRUE),
      pop_hspE_agg = sum(pop_hspE * wt_pop, na.rm = TRUE),
      pop_aaE_agg = sum(pop_aaE * wt_pop, na.rm = TRUE),
      pop_raceE_agg =  sum(pop_raceE * wt_pop, na.rm = TRUE),
      pop_ethnE_agg =  sum(pop_ethnE * wt_pop, na.rm = TRUE),
      sfd_detE_agg =  sum(sfd_detE * wt_hu, na.rm = TRUE),
      sfd_baseE_agg = sum(sfd_baseE * wt_hu, na.rm = TRUE),
      mfE_agg = sum(mfE * wt_hu, na.rm = TRUE),

      rhucashE_agg = sum(rhucashE * wt_renthu, na.rm = TRUE),

      # Use across() for grentcat1E through grentcat24E
      across(starts_with("grentcat") & ends_with("E"),
             ~sum(.x * wt_renthu, na.rm = TRUE),
             .names = "{.col}_agg"),


      .groups = "drop"
    ) |>
    # Rename everything back to original names
    rename(
      rentE = rentE_agg,
      lqcrentE = lqcrentE_agg,
      med_hhincE = med_hhincE_agg,
      med_hvalE = med_hvalE_agg,
      rentM = rentM_agg,
      lqcrentM = lqcrentM_agg,
      med_hhincM = med_hhincM_agg,
      med_hvalM = med_hvalM_agg,

      rhuM = rhuM_agg,
      rhu_baseM = rhu_baseM_agg,
      tot_vacM = tot_vacM_agg,
      tot_vac_baseM = tot_vac_baseM_agg,
      pop_blkM = pop_blkM_agg,
      pop_hspM = pop_hspM_agg,
      pop_aaM = pop_aaM_agg,
      pop_raceM = pop_raceM_agg,
      sfd_detM = sfd_detM_agg,
      sfd_baseM = sfd_baseM_agg,
      huM = huM_agg,
      popM = popM_agg,

      huE = huE_agg,
      rhuE = rhuE_agg,
      rhu_lrE = rhu_lrE_agg,
      rhu_lr2E = rhu_lr2E_agg,
      rhu_baseE = rhu_baseE_agg,
      hhE = hhE_agg,
      popE = popE_agg,
      tot_vacE = tot_vacE_agg,
      tot_vac_baseE = tot_vac_baseE_agg,
      pop_blkE = pop_blkE_agg,
      pop_hspE = pop_hspE_agg,
      pop_aaE = pop_aaE_agg,
      pop_raceE = pop_raceE_agg,
      pop_ethnE = pop_ethnE_agg,
      sfd_detE = sfd_detE_agg,
      sfd_baseE = sfd_baseE_agg,
      mfE = mfE_agg,
      rhucashE = rhucashE_agg
    ) |>
    # Rename all grentcat variables at once
    rename_with(~str_remove(.x, "_agg$"), starts_with("grentcat")) |>
    mutate(rhu_id = TRUE) |>
    select(-ends_with("_agg"))
}


#' Calculate interpolated rent
#'
#' @param df
#' @return dataframe with linearly interpolated median rent per tract
calc_interp_rent <- function(df) {
    # Identify the median rent category
    tr_rhu <- df |>
      select(tr2010_id, rhucashE)

    tr_median_cat <- df |>
      select(tr2010_id, rhucashE, starts_with("grentcat")) |>
      pivot_longer(
        cols = starts_with("grentcat"),
        names_to = "grentcat",
        values_to = "count",
        names_pattern = "grentcat(\\d+)E",
        names_transform = list(grentcat = as.integer)
      ) |>
      arrange(tr2010_id, grentcat) |>
      group_by(tr2010_id) |>
      mutate(
        cum_count = cumsum(count),
        median_threshold = first(rhucashE) / 2
      ) |>
      filter(cum_count >= median_threshold) |>
      slice_min(grentcat, with_ties = FALSE) |>
      ungroup() |>
      rename(grentcat_median = grentcat) |>
      select(tr2010_id, grentcat_median, count, cum_count, median_threshold)

    # Define rent cat ranges
    grentcat_ranges <- tibble(
      grentcat = 1:24,
      lower = c(0, 100, 150, 200, 250, 300, 350, 400, 450, 500, 550, 600,
                650, 700, 750, 800, 900, 1000, 1250, 1500, 2000, 2500, 3000, 3500),
      upper = c(99, 149, 199, 249, 299, 349, 399, 449, 499, 549, 599, 649,
                699, 749, 799, 899, 999, 1249, 1499, 1999, 2499, 2999, 3499, NA)  # NA for open-ended
    )


    # Calculate interpolated rent
    tr_interp_rent <- tr_rhu |>
      select(tr2010_id, rhucashE) |>
      left_join(tr_median_cat ,
                by = "tr2010_id") |>
      left_join(grentcat_ranges,
                by = c("grentcat_median" = "grentcat")) |>
      mutate(prop= (median_threshold-(cum_count-count))/count,
            width=upper-lower,
            interp_rent=lower+width*prop)


    tr_interp_rent <- tr_interp_rent |>
      mutate(interp_rent= case_when(grentcat_median>1 & grentcat_median<24 ~ interp_rent,
                                      grentcat_median==1 | rhucashE==0 ~ NA,
                                      grentcat_median==24 ~ NA)
                                      )|>
      select(c(tr2010_id, interp_rent))
    #   select(c(tr2010_id, interp_rent,  lower, upper, width, prop, cum_count, median_threshold, count))

    return(tr_interp_rent)

}

#' Calculate % missing vars
#'
#' @param df
#' @return dataframe with % missing calculations
calc_missing_vars <- function(df) {
  df |>
    mutate(pct_miss_rent = if_else(rhuE > 0, rhu_miss_rent / rhuE, NA_real_),
           pct_miss_hval = if_else(huE > 0,  hu_miss_hval / huE, NA_real_)
         )
}

#' Calculate % vars
#'
#' @param df
#' @return dataframe with % calculations
calc_pct_vars <- function(df) {

            df |>
                mutate(pctrhuE = if_else(huE > 0, rhuE / huE, NA_real_),
                        pctvacE =  if_else(tot_vac_baseE > 0, tot_vacE / tot_vac_baseE, NA_real_),
                        pctblkE =  if_else(pop_raceE > 0, pop_blkE / pop_raceE, NA_real_),
                        pcthspE =  if_else(pop_ethnE > 0, pop_hspE / pop_ethnE, NA_real_),
                        pctaaE =  if_else(pop_raceE > 0, pop_aaE / pop_raceE, NA_real_),
                        pctsfdE =  if_else(sfd_baseE > 0, sfd_detE / sfd_baseE, NA_real_),

                    )

}


#' Calculate comb MOE, CV
#'
#' @param df
#' @return dataframe with CV calculations
calc_cv <- function(df) {
  df |>
    mutate(
            # TEMPLATE: MOE FOR RATIO
            # MOE_RATIO = if_else(
            #     EST_DENOM != 0,
            #     sqrt(pmax(0, (MOE_NUM^2) - (RATIO^2) * (MOE_DENOM^2))) / EST_DENOM,
            #     NA_real_
            # ),
            pctrhuM = if_else(
                rhu_baseE != 0,
                sqrt(pmax(0, (rhuM^2) - (pctrhuE^2) * (rhu_baseM^2))) / rhu_baseE,
                NA_real_
            ),
            pctblkM = if_else(
                pop_raceE != 0,
                sqrt(pmax(0, (pop_blkM^2) - (pctblkE^2) * (pop_raceM^2))) / pop_raceE,
                NA_real_
            ),
            pcthspM = if_else(
                pop_raceE != 0,
                sqrt(pmax(0, (pop_hspM^2) - (pcthspE^2) * (pop_raceM^2))) / pop_raceE,
                NA_real_
            ),
           rentCV = (rentM/1.645)/rentE,
           med_hhincCV = (med_hhincM/1.645)/med_hhincE,
           med_hvalCV = (med_hvalM/1.645)/med_hvalE,
        #    pctrhuCV = (moe_pctrhu/1.645)/pctrhu,
        #    pctblkCV = (moe_pctblk/1.645)/pctblk,
           pctrhuCV = if_else(pctrhuE!=0, (pctrhuM/1.645)/pctrhuE, NA),
           pctblkCV = if_else(pctblkE!=0, (pctblkM/1.645)/pctblkE, NA),
           pcthspCV = if_else(pcthspE!=0, (pcthspM/1.645)/pcthspE, NA),
           rhuCV = if_else(rhuE!=0, (rhuM/1.645)/rhuE, NA),
           huCV = if_else(huE!=0, (huM/1.645)/huE, NA),
           popCV = if_else(popE!=0, (popM/1.645)/popE, NA)
            )
}


# ---- Summary helpers ---------------------------------------------------------

#' Summary statistics for a single variable
#'
#' @param df Data frame
#' @param col Column name (unquoted)
#' @return Data frame with summary statistics
summ_stats <- function(df, col) {
  df |>
    summarise(
      n = sum(!is.na({{col}})),
      n_lt12 = sum({{col}}<.12, na.rm=TRUE),
      mean = mean({{col}}, na.rm = TRUE),
      sd = sd({{col}}, na.rm = TRUE),
      min = min({{col}}, na.rm = TRUE),
      p75 = quantile({{col}}, 0.75, na.rm = TRUE),
      p90 = quantile({{col}}, 0.90, na.rm = TRUE),
      max = max({{col}}, na.rm = TRUE)
    )
}


#' Summary statistics for a single ACS estimate included in a dataframe
#'
#' Distribution-focused variant used in this stage (counts of zeros / small
#' shares, quantiles). NOTE: distinct from the MOE/CV-focused `summ_var()` in
#' R/helpers.R used by 01_acs.Rmd.
#'
#' @param df Data frame
#' @param var_name ACS estimate name
#' @return Summary statistics
summ_var <- function(df, var_name) {
  summarise(
    df,
    var        = var_name,
    n          = sum(!is.na(.data[[var_name]])),
    n_missing  = sum(is.na(.data[[var_name]])),
    n_0      = sum(.data[[var_name]] == 0, na.rm = TRUE),
    n_gt0      = sum(.data[[var_name]] > 0, na.rm = TRUE),
    n_lt1      = sum(.data[[var_name]] < 1 , na.rm = TRUE),
    n_lt5pct   = sum(.data[[var_name]] < .05 , na.rm = TRUE),
    n_lt50pct   = sum(.data[[var_name]] < .5 , na.rm = TRUE),
    mean       = mean(.data[[var_name]], na.rm = TRUE),
    median     = median(.data[[var_name]], na.rm = TRUE),
    min        = min(.data[[var_name]],  na.rm = TRUE),
    p75     = quantile(.data[[var_name]], 0.75, na.rm = TRUE),
    p90     = quantile(.data[[var_name]], 0.9, na.rm = TRUE),
    p95     = quantile(.data[[var_name]], 0.95, na.rm = TRUE),
    max        = max(.data[[var_name]],  na.rm = TRUE)
  )
}


# ---- Diagnostic / validation helpers ----------------------------------------

#' Print a row-count line for an import, save, or transform step
#'
#' @param df Data frame whose rows are counted.
#' @param label Character. Short description of the step being reported.
#' @param expected Optional numeric reference row count, printed for comparison.
#' @return Invisibly, the input df.
report_n <- function(df, label, expected = NULL) {
  n <- nrow(df)
  msg <- sprintf("%s: %s rows", label, formatC(n, format = "d", big.mark = ","))
  if (!is.null(expected)) {
    msg <- sprintf("%s (expected ~%s)", msg, formatC(expected, format = "d", big.mark = ","))
  }
  cat(msg, "\n")
  invisible(df)
}


#' Print rows dropped by a filter step and the cumulative rows remaining
#'
#' @param after_df Data frame AFTER the filter.
#' @param n_before Integer row count BEFORE the filter.
#' @param reason Character. Plain-language reason for the drop.
#' @return Invisibly, after_df.
report_drop <- function(after_df, n_before, reason) {
  n_after <- nrow(after_df)
  cat(sprintf("Dropped %s rows (%s). Rows remaining: %s\n",
              formatC(n_before - n_after, format = "d", big.mark = ","),
              reason,
              formatC(n_after, format = "d", big.mark = ",")))
  invisible(after_df)
}


#' Format a single numeric value for diagnostic printing
#'
#' Three decimals for small-magnitude values (e.g. shares/weights in [0, 1]),
#' whole numbers with thousands separators otherwise. Non-finite prints "NA".
#'
#' @param x Numeric scalar.
#' @return Character scalar.
fmt_num <- function(x) {
  if (!is.finite(x)) return("NA")
  digits <- if (abs(x) < 100) 3 else 0
  formatC(x, format = "f", big.mark = ",", digits = digits)
}


#' Print mean, min, and max for every numeric column in a data frame
#'
#' One line per numeric column: `colname: mean=... | min=... | max=...`.
#'
#' @param df Data frame to summarize.
#' @param name Optional character label printed as a header.
#' @return Invisibly, the input df.
print_numeric_summary <- function(df, name = NULL) {
  if (!is.null(name)) cat("\nNumeric summary:", name, "\n")
  num_cols <- names(df)[vapply(df, is.numeric, logical(1))]
  if (length(num_cols) == 0) {
    cat("(no numeric columns)\n")
    return(invisible(df))
  }
  for (col in num_cols) {
    x  <- df[[col]]
    mn <- suppressWarnings(mean(x, na.rm = TRUE))
    lo <- suppressWarnings(min(x, na.rm = TRUE))
    hi <- suppressWarnings(max(x, na.rm = TRUE))
    cat(sprintf("%s: mean=%s | min=%s | max=%s\n",
                col, fmt_num(mn), fmt_num(lo), fmt_num(hi)))
  }
  invisible(df)
}
