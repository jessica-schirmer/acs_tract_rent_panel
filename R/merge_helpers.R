# merge_helpers.R --------------------------------------------------------
# Helper functions for 04_merge.Rmd (Step 4: merge the 2012-2016 and 2020-2024
# tract measures into a panel and compute change variables).
#
# This file is intentionally SELF-CONTAINED: 04_merge.Rmd sources only this
# file. It therefore carries its own copies of a few small generic/diagnostic
# helpers (load_data, save_data, report_n, print_numeric_summary, fmt_num) and
# its own `merge_df()` — which joins two surveys on tr2010_id using base_id /
# post_id indicators, distinct from the `merge_df()` in R/assemble_helpers.R.
# Keeping each notebook's helpers in a separate file avoids name collisions.
#
# Assumes the calling notebook has already loaded dplyr/tidyr/stringr (tidyverse)
# and arrow.
#
# Load at the top of the notebook with:
#   source(here::here("R", "merge_helpers.R"))


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


# ---- Merge helper ------------------------------------------------------------

#' Merge two surveys on tract id
#'
#' Full-joins a "base" (earlier) and "post" (later) survey on `tr2010_id`, adding
#' `base_id` / `post_id` presence flags and a `merge` indicator
#' ("both"/"base"/"post").
#'
#' @param left_df left (base) dataframe
#' @param right_df right (post) dataframe
#' @return Merged dataframe
merge_df <- function(left_df, right_df) {
    left_df <- left_df |>
        mutate(base_id=TRUE)

    right_df <- right_df |>
        mutate(post_id=TRUE)

    join_df <- full_join(left_df, right_df, by = "tr2010_id") |>
        mutate(
        merge = case_when(
            base_id & post_id ~ "both",
            base_id ~ "base",
            post_id ~ "post",
            .default = NA_character_
        )

        )

        return(join_df)

}


# ---- Variable renaming / selection -------------------------------------------

#' Rename variables
#'
#' Appends a `_{yr}` suffix to the estimate / margin-of-error / coefficient-of-
#' variation variables listed below. NOTE: the three lists here implicitly
#' determine which measures are carried into the panel (only listed variables are
#' renamed, and `select_vars()` then keeps the suffixed columns).
#'
#' @param df Data frame
#' @param yr year of survey
#' @return Data frame with modified variable names, labeled for year of survey
rename_vars <- function(df, yr) {
    est_var_list <- c("rentE", "lqcrentE", "popE", "huE", "rhuE",
                      "med_hvalE",
                     "rhu_lrE", "rhu_lr2E",  "med_hhincE", "pctrhuE", "pctvacE",
                     "pctblkE", "pcthspE", "pctaaE", "pctsfdE", "mf5E",
                     "nsfaE", "pctrvacE", "pctsvacE")
    moe_var_list <- c("rentM", "lqcrentM", "popM", "huM", "rhuM",
                      "med_hvalM",
                    #  "rhu_lrM", "rhu_lr2M",  "pctvacM", "pcthspM", "pctaaM",
                     "med_hhincM", "pctrhuM", "pctblkM", "pcthspM" )
    cv_var_list <- c("rentCV",  "popCV", "huCV", "rhuCV",
                      "med_hvalCV",
                    #  "rhu_lrCV", "rhu_lr2CV",  "pctvacCV", "pctaaCV", "lqcrentCV",
                     "med_hhincCV", "pctrhuCV", "pctblkCV" , "pcthspCV")
  for (i in c(est_var_list, moe_var_list, cv_var_list)) {
    new_var_name <- paste0(i, "_", yr)
    df <- df |>
      dplyr::rename(!!new_var_name := !!i)
  }

  return(df)
}

#' Select variables
#'
#' @param df Data frame
#' @param yr year of survey
#' @param var_list List of additional variables
#' @return Data frame with only selected variables
select_vars <- function(df, yr, var_list) {

    df <- df |>
        select(ends_with("id"), ends_with(yr), var_list)


  return(df)
}


# ---- Inflation adjustment ----------------------------------------------------

#' Apply inflation adjustment
#'
#' Scales the 2016 dollar-denominated variables to 2024 dollars (factor 1.307,
#' CPI-U annual averages, BLS, U.S. city average, all items: 313.689 (2024) /
#' 240.007 (2016)). Only applied when `yr == "16"`.
#'
#' @param df Data frame
#' @param yr year of survey
#' @return Data frame with dollar values adjusted to 2023 values
infl_adj_vars <- function(df, yr, var_list) {
    dollar_vars <- c("rentE", "lqcrentE", "med_hhincE", "med_hvalE",
                    "rentM", "lqcrentM", "med_hhincM", "med_hvalM")
    for (i in dollar_vars) {
        if (yr=="16"){
            var_name <- paste0(i, "_", yr)
            df <- df |>
                dplyr::mutate(!!sym(var_name) := !!sym(var_name) * 1.307)

    }

}
  return(df)
}


# ---- Change variables --------------------------------------------------------

#' Calculate change variables
#'
#' Level (dollar/count) changes are 2023/2016 ratios (`*POST`); share and rate
#' changes are percentage-point differences, `value_24 - value_16` (`*PPC`).
#'
#' @param df
#' @return dataframe with change variables (`*POST` ratios, `*PPC` differences)
#'   and missing flags
calc_change_vars <- function(df) {
  df |>
    mutate(rentPOST = ifelse(rentE_16>0, rentE_24/rentE_16, NA),
           interp_rentPOST = ifelse(rentE_16>0, interp_rent/rentE_16, NA),
            lqcrentPOST = ifelse(lqcrentE_16>0, lqcrentE_24/lqcrentE_16, NA),
            # rentPRE = ifelse(rentE_09>0, rentE_16/rentE_09,NA),
            huPOST = ifelse(huE_16>0, huE_24/huE_16,NA),
            rhuPOST = ifelse(rhuE_16>0, rhuE_24/rhuE_16,NA),
            rhu_lrPOST = ifelse(rhu_lrE_16>0, rhu_lrE_24/rhu_lrE_16, NA),
            rhu_lr2POST = ifelse(rhu_lr2E_16>0, rhu_lr2E_24/rhu_lr2E_16, NA),
            # rhucashPOST = ifelse(rhucashE_16>0, rhucashE_24/rhucashE_16,NA),
            med_hhincPOST = ifelse(med_hhincE_16>0, med_hhincE_24/med_hhincE_16,NA),
            # Share / rate changes are percentage-point differences (value_24 - value_16),
            # not ratios: defined wherever both periods are present (NA if either is
            # missing), with no zero-denominator guard. Distinct *PPC names flag the
            # percentage-point-change convention.
            pctrhuPPC  = pctrhuE_24  - pctrhuE_16,
            pctvacPPC  = pctvacE_24  - pctvacE_16,
            pctrvacPPC = pctrvacE_24 - pctrvacE_16,
            pctsvacPPC = pctsvacE_24 - pctsvacE_16,
            popPOST = ifelse(popE_16>0, popE_24/popE_16, NA),
            ) |>
    mutate(m_flag_rentPOST = if_else(is.na(rentPOST), 1, 0),
           m_flag_rhuPOST = if_else(is.na(rhuPOST), 1, 0) )

}


#' Calculate comb MOE, CV
#'
#' Ratio-MOE propagation for the change variables, then their CVs.
#'
#' @param df
#' @return dataframe with CV calculations
calc_cv_change_vars <- function(df) {
  df |>
    mutate(
            # TEMPLATE: MOE FOR RATIO
            # MOE_RATIO = if_else(
            #     EST_DENOM != 0,
            #     sqrt(pmax(0, (MOE_NUM^2) - (RATIO^2) * (MOE_DENOM^2))) / EST_DENOM,
            #     NA_real_
            # ),
            moe_rentPOST = if_else(
                rentE_16 != 0,
                sqrt(pmax(0, (rentM_24^2) - (rentPOST^2) * (rentM_16^2))) / rentE_16,
                NA_real_
            ),
            # moe_interp_rentPOST = if_else(
            #     rentE_16 != 0,
            #     sqrt(pmax(0, (interp_rentM^2) - (interp_rentPOST^2) * (rentM_16^2))) / rentE_16,
            #     NA_real_
            # ),
            moe_rhuPOST = if_else(
                rhuE_16!= 0,
                sqrt(pmax(0, (rhuM_24^2) - (rhuPOST^2) * (rhuM_16^2))) / rhuE_16,
                NA_real_
            ),
            moe_med_hhincPOST = if_else(
                med_hhincE_16!= 0,
                sqrt(pmax(0, (med_hhincM_24^2) - (med_hhincPOST^2) * (med_hhincM_16^2))) / med_hhincE_16,
                NA_real_
            ),
            rentPOSTCV =  (moe_rentPOST/1.645)/rentPOST,
            # interp_rentPOSTCV =  (moe_interp_rentPOST/1.645)/rentPOST,
            rhuPOSTCV =  (moe_rhuPOST/1.645)/rhuPOST,
            med_hhincPOSTCV = (moe_med_hhincPOST/1.645)/med_hhincPOST,

            )
}


# ---- Diagnostic / validation helpers ----------------------------------------

#' Print a row-count line for an import, merge, or save step
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


#' Format a single numeric value for diagnostic printing
#'
#' Three decimals for small-magnitude values (e.g. ratios/shares near 1),
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
