# merge_helpers.R --------------------------------------------------------
# Helper functions for 04_merge.Rmd (Step 4: merge the 2012-2016 and 2020-2024
# tract measures into a panel and compute change variables).
#
# This file carries its own copies of a few small generic/diagnostic
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

#' Fixed panel estimate, MOE, and CV columns from the Step 2 schemas
#' @return Character vector used by survey preparation and 2024 bundle selection
merge_measure_columns <- function() {
    est_var_list <- c("rentE", "lqcrentE", "popE", "huE", "rhuE",
                      "med_hvalE",
                     "rhu_lrE", "rhu_lr2E",  "med_hhincE", "pctrhuE", "pctvacE",
                     "pctblkE", "pcthspE", "pctaaE", "pctsfdE", "mf5E",
                     "nsfaE", "pctrvacE", "pctsvacE", "rhu_inventoryE")
    moe_var_list <- c("rentM", "lqcrentM", "popM", "huM", "rhuM",
                      "med_hvalM",
                    #  "rhu_lrM", "rhu_lr2M",  "pctvacM", "pcthspM", "pctaaM",
                     "med_hhincM", "pctrhuM", "pctblkM", "pcthspM" )
    cv_var_list <- c("rentCV",  "popCV", "huCV", "rhuCV",
                      "med_hvalCV",
                    #  "rhu_lrCV", "rhu_lr2CV",  "pctvacCV", "pctaaCV", "lqcrentCV",
                     "med_hhincCV", "pctrhuCV", "pctblkCV" , "pcthspCV")
  c(est_var_list, moe_var_list, cv_var_list)
}

#' Append a survey-year suffix to the fixed panel measurement columns
#' @param df Data frame
#' @param yr Survey-year suffix
#' @return Data frame with renamed measurement columns
rename_vars <- function(df, yr) {
  for (i in merge_measure_columns()) {
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
        select(ends_with("id"), ends_with(yr), all_of(var_list))


  return(df)
}

# ---- Hierarchical 2024 measurement ------------------------------------------

merge_quality_columns <- function() {
  c("m_flag_rent", "m_flag_lqcrent", "m_flag_rhu", "m_flag_med_hval",
    "zero_flag_rhu", "zero_flag_med_hval",
    "tc_flag_rent", "tc_flag_lqcrent", "tc_flag_med_hval")
}

# Fixed panel fields from the Step 2 schemas, including source-specific flags.
merge_2024_field_map <- function() {
  fields <- c(merge_measure_columns(), merge_quality_columns())
  tibble::tibble(canonical = c(paste0(fields, "_24"), "interp_rent"),
                 tract = c(paste0(fields, "_24_tract"), "rentE_24_tract"),
                 bg_agg = c(paste0(fields, "_24_bg_agg"), "interp_rent_24_bg_agg"))
}

prepare_2024_source <- function(df, source = c("tract", "bg_agg")) {
  source <- match.arg(source)
  key <- if (source == "tract") "tr2020_id" else "tr2010_id"
  required <- c(key, merge_measure_columns(),
                if (source == "tract") merge_quality_columns() else c("tc_flag_rent_24", "interp_rent"))
  missing <- setdiff(required, names(df))
  if (length(missing)) stop(source, ": missing bundle fields: ", paste(missing, collapse = ", "))
  if (!all(vapply(df[setdiff(required, key)], is.numeric, logical(1)))) {
    stop(source, ": measurement bundles must be numeric")
  }
  if (source == "bg_agg") {
    for (measure in c("rent", "lqcrent", "rhu", "med_hval")) {
      df[[paste0("m_flag_", measure)]] <- as.double(is.na(df[[paste0(measure, "E")]]))
    }
    for (measure in c("rhu", "med_hval")) {
      df[[paste0("zero_flag_", measure)]] <- as.double(df[[paste0(measure, "E")]] == 0)
    }
    df$tc_flag_rent <- df$tc_flag_rent_24
    df$tc_flag_lqcrent <- rep(NA_real_, nrow(df))
    df$tc_flag_med_hval <- rep(NA_real_, nrow(df))
  }
  df |>
    dplyr::select(dplyr::all_of(c(key, merge_measure_columns(), merge_quality_columns(),
                                 if (source == "bg_agg") "interp_rent"))) |>
    dplyr::rename_with(~ paste0(.x, "_24_", source), -dplyr::all_of(key))
}

select_canonical_2024 <- function(df) {
  fields <- merge_2024_field_map()
  required <- c("geo_consistent", fields$tract, fields$bg_agg)
  if (!all(required %in% names(df)) || !is.double(df$geo_consistent)) {
    stop("Hierarchy: missing source fields or invalid geographic flag storage")
  }
  df$acs_source_24 <- dplyr::case_when(
    df$geo_consistent == 1 ~ "tract",
    df$geo_consistent == 0 ~ "bg_agg",
    .default = NA_character_
  )
  for (i in seq_len(nrow(fields))) {
    df[[fields$canonical[i]]] <- dplyr::case_when(
      df$acs_source_24 == "tract" ~ df[[fields$tract[i]]],
      df$acs_source_24 == "bg_agg" ~ df[[fields$bg_agg[i]]],
      .default = NA_real_
    )
  }
  df
}

# The only additions permitted relative to the pre-hierarchy panel contract.
panel_schema_additions <- function() {
  c("rhu_inventoryE_16", "rhu_inventoryE_24", "rhu_inventoryPOST",
    "m_flag_rhu_inventoryPOST", "tr2020_id", "geo_consistent",
    "relationship_class", "acs_source_24",
    setdiff(paste0(merge_quality_columns(), "_24"), "tc_flag_rent_24"))
}

# Uses the shared strict schema checker without relaxing other stages' checks.
assert_panel_schema <- function(current, previous = NULL) {
  additions <- panel_schema_additions()
  if (!all(additions %in% names(current)) || anyDuplicated(names(current))) {
    stop("Panel schema: missing required hierarchy fields or duplicate columns")
  }
  strings <- c("tr2020_id", "relationship_class", "acs_source_24")
  if (!all(vapply(current[strings], is.character, logical(1))) ||
      !all(vapply(current[setdiff(additions, strings)], is.double, logical(1)))) {
    stop("Panel schema: invalid hierarchy column storage types")
  }
  if (!all(is.na(current$acs_source_24) | current$acs_source_24 %in% c("tract", "bg_agg")) ||
      !all(is.na(current$tr2020_id) | grepl("^06[0-9]{9}$", current$tr2020_id))) {
    stop("Panel schema: invalid source label or linked 2020 key")
  }
  flags <- c(paste0(merge_quality_columns(), "_24"), "m_flag_rhu_inventoryPOST")
  if (!all(vapply(current[flags], function(x) {
    is.double(x) && all(is.na(x) | x %in% c(0, 1))
  }, logical(1)))) stop("Panel schema: quality flags must be double 0/1/NA")
  if (!is.null(previous)) {
    added <- setdiff(names(current), names(previous))
    removed <- setdiff(names(previous), names(current))
    print(tibble::tibble(change = c(rep("added", length(added)), rep("removed", length(removed))),
                         variable = c(added, removed)), n = Inf)
    if (!all(added %in% additions) || length(removed) || anyDuplicated(names(previous))) {
      stop("Panel schema: unapproved additions/removals")
    }
    assert_same_schema(current[, !names(current) %in% added, drop = FALSE], previous,
                       "Panel schema shared columns versus prior output")
  }
  invisible(TRUE)
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
#' Level (dollar/count) changes are 2024/2016 ratios (`*POST`); share and rate
#' changes are percentage-point differences, `value_24 - value_16` (`*PPC`).
#' Call after source selection so `interp_rentPOST` uses canonical `interp_rent`.
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
            rhu_inventoryPOST = ifelse(rhu_inventoryE_16>0,
                                      rhu_inventoryE_24/rhu_inventoryE_16, NA_real_),
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
           m_flag_rhuPOST = if_else(is.na(rhuPOST), 1, 0),
           m_flag_rhu_inventoryPOST = if_else(is.na(rhu_inventoryPOST), 1, 0) )

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
