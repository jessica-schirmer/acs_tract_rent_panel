# merge_helpers.R --------------------------------------------------------
# Helper functions for 04_assemble_tract_panel.Rmd (Step 4: merge the 2012-2016 and 2020-2024
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
#' @param source Native tract fields or retained 2024 block-group/panel fields.
#' @return Character vector used by survey preparation and 2024 bundle selection
merge_measure_columns <- function(source = c("tract", "bg_agg")) {
  source <- match.arg(source)
    est_var_list <- c("rentE", "lqcrentE", "popE", "huE", "rhuE",
                      "med_hvalE",
                     "med_hhincE", "pctrhuE", "pctvacE",
                     "pctblkE", "pcthspE", "pctaaE", "pctsfdE", "mf5E",
                     "nsfaE", "smfE", "sfd_detE", "pctrvacE", "pctsvacE", "rhu_inventoryE")
    moe_var_list <- c("rentM", "lqcrentM", "popM", "huM", "rhuM",
                      "med_hvalM",
                     "med_hhincM", "pctrhuM", "pctblkM", "pcthspM" )
    cv_var_list <- c("rentCV",  "popCV", "huCV", "rhuCV",
                      "med_hvalCV",
                     "med_hhincCV", "pctrhuCV", "pctblkCV" , "pcthspCV")
  fields <- c(est_var_list, moe_var_list, cv_var_list)
  if (source == "bg_agg") {
    fields <- setdiff(fields, c("rentE", "rentM", "rentCV", "lqcrentE", "lqcrentM",
                               "med_hvalE", "med_hvalM", "med_hvalCV"))
  }
  fields
}

#' Append a survey-year suffix to the fixed panel measurement columns
#' @param df Data frame
#' @param yr Survey-year suffix
#' @param source Native tract fields or retained block-group fields.
#' @return Data frame with renamed measurement columns
rename_vars <- function(df, yr, source = c("tract", "bg_agg")) {
  source <- match.arg(source)
  for (i in merge_measure_columns(source)) {
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
  c("m_flag_rhu", "zero_flag_rhu")
}

# Fixed panel fields from the Step 2 schemas, including source-specific flags.
merge_2024_field_map <- function() {
  fields <- c(merge_measure_columns("bg_agg"), merge_quality_columns(),
              "tc_flag_rent", "rent_status", "rent_censor_bound")
  tibble::tibble(canonical = c(paste0(fields, "_24"), "interp_rent"),
                 tract = c(paste0(fields, "_24_tract"), "rentE_24_tract"),
                 bg_agg = c(paste0(fields, "_24_bg_agg"), "interp_rent_24_bg_agg"))
}

prepare_2024_source <- function(df, source = c("tract", "bg_agg")) {
  source <- match.arg(source)
  key <- if (source == "tract") "tr2020_id" else "tr2010_id"
  measures <- merge_measure_columns("bg_agg")
  rent_source <- if (source == "tract") "rentE" else "interp_rent"
  required <- c(key, measures, rent_source, rent_metadata_columns("24"),
                if (source == "tract") merge_quality_columns())
  missing <- setdiff(required, names(df))
  if (length(missing)) stop(source, ": missing bundle fields: ", paste(missing, collapse = ", "))
  if (!all(vapply(df[setdiff(required, c(key, "rent_status_24"))], is.numeric, logical(1))) ||
      !is.character(df$rent_status_24)) {
    stop(source, ": measurement bundles must be numeric")
  }
  if (source == "bg_agg") {
    df$m_flag_rhu <- as.double(is.na(df$rhuE))
    df$zero_flag_rhu <- as.double(df$rhuE == 0)
  }
  for (column in rent_metadata_columns("24")) df[[sub("_24$", "", column)]] <- df[[column]]
  df |>
    dplyr::select(dplyr::all_of(c(key, measures, merge_quality_columns(),
                                "tc_flag_rent", "rent_status", "rent_censor_bound", rent_source))) |>
    dplyr::rename_with(~ paste0(.x, "_24_", source), -dplyr::all_of(key))
}

select_canonical_2024 <- function(df) {
  fields <- merge_2024_field_map()
  required <- c("geo_consistent", fields$tract, fields$bg_agg)
  if (!all(required %in% names(df)) || !is.double(df$geo_consistent)) {
    stop("Hierarchy: missing source fields or invalid geographic flag storage")
  }
  df$acs_source_24 <- dplyr::if_else(df$geo_consistent %in% 1, "tract", "bg_agg")
  for (i in seq_len(nrow(fields))) {
    df[[fields$canonical[i]]] <- dplyr::if_else(
      df$acs_source_24 == "tract", df[[fields$tract[i]]], df[[fields$bg_agg[i]]]
    )
  }
  df$rent_status_24 <- dplyr::coalesce(df$rent_status_24, "unresolved")
  df
}

# Documented hierarchy, inventory, and structure-level additions to older panels.
panel_schema_additions <- function() {
  c("rhu_inventoryE_16", "rhu_inventoryE_24", "rhu_inventoryPOST",
    "m_flag_rhu_inventoryPOST", "tr2020_id", "geo_consistent",
    "relationship_class", "acs_source_24",
    "smfE_16", "smfE_24", "sfd_detE_16", "sfd_detE_24",
    paste0(merge_quality_columns(), "_24"), rent_metadata_columns("16"),
    "rent_status_24", "rent_censor_bound_24")
}

# Fixed removal allowlist for the obsolete measures and their sole-use companions.
panel_schema_removals <- function() {
  c("tc_flag_rent", "m_flag_rent", "pct_tc_rent",
    "rhu_lrE_16", "rhu_lrE_24", "rhu_lr2E_16", "rhu_lr2E_24",
    "rhu_lrPOST", "rhu_lr2POST",
    "rentE_24", "rentM_24", "rentCV_24", "lqcrentE_24", "lqcrentM_24",
    "med_hvalE_24", "med_hvalM_24", "med_hvalCV_24",
    "rentPOST", "lqcrentPOST", "moe_rentPOST", "rentPOSTCV", "m_flag_rentPOST",
    "pct_miss_hval", "m_flag_rent_24", "m_flag_lqcrent_24", "m_flag_med_hval_24",
    "zero_flag_med_hval_24", "tc_flag_lqcrent_24", "tc_flag_med_hval_24")
}

# Uses the shared strict schema checker without relaxing other stages' checks.
assert_panel_schema <- function(current, previous = NULL) {
  additions <- panel_schema_additions()
  removals <- panel_schema_removals()
  if (any(names(current) %in% removals)) stop("Panel schema: retired fields present")
  if (!all(additions %in% names(current)) || anyDuplicated(names(current))) {
    stop("Panel schema: missing required fields or duplicate columns")
  }
  strings <- c("tr2020_id", "relationship_class", "acs_source_24", "rent_status_16", "rent_status_24")
  if (!all(vapply(current[strings], is.character, logical(1))) ||
      !all(vapply(current[setdiff(additions, strings)], is.double, logical(1)))) {
    stop("Panel schema: invalid required column storage types")
  }
  if (!all(is.na(current$acs_source_24) | current$acs_source_24 %in% c("tract", "bg_agg")) ||
      !all(is.na(current$tr2020_id) | grepl("^06[0-9]{9}$", current$tr2020_id))) {
    stop("Panel schema: invalid source label or linked 2020 key")
  }
  flags <- c(paste0(merge_quality_columns(), "_24"), "tc_flag_rent_16", "tc_flag_rent_24", "m_flag_rhu_inventoryPOST")
  if (!all(vapply(current[flags], function(x) {
    is.double(x) && all(is.na(x) | x %in% c(0, 1))
  }, logical(1)))) stop("Panel schema: quality flags must be double 0/1/NA")
  if (!is.null(previous)) {
    added <- setdiff(names(current), names(previous))
    removed <- setdiff(names(previous), names(current))
    print(tibble::tibble(change = c(rep("added", length(added)), rep("removed", length(removed))),
                         variable = c(added, removed)), n = Inf)
    if (!all(added %in% additions) || !all(removed %in% removals) || anyDuplicated(names(previous))) {
      stop("Panel schema: unapproved additions/removals")
    }
    assert_same_schema(current[, !names(current) %in% added, drop = FALSE],
                       previous[, !names(previous) %in% removed, drop = FALSE],
                       "Panel schema shared columns versus prior output")
  }
  invisible(TRUE)
}


# ---- Inflation adjustment ----------------------------------------------------

inflation_factor_2016 <- function() 1.307

#' Apply inflation adjustment
#'
#' Scales the 2016 dollar-denominated variables to 2024 dollars (factor 1.307,
#' CPI-U annual averages, BLS, U.S. city average, all items: 313.689 (2024) /
#' 240.007 (2016)). Only applied when `yr == "16"`.
#'
#' @param df Data frame
#' @param yr year of survey
#' @return Data frame with dollar values and censoring bounds in 2024 dollars
infl_adj_vars <- function(df, yr, var_list) {
    dollar_vars <- c("rentE", "lqcrentE", "med_hhincE", "med_hvalE",
                    "rentM", "lqcrentM", "med_hhincM", "med_hvalM", "rent_censor_bound")
    for (i in dollar_vars) {
        if (yr=="16"){
            var_name <- paste0(i, "_", yr)
            df <- df |>
                dplyr::mutate(!!sym(var_name) := !!sym(var_name) * inflation_factor_2016())

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
    mutate(interp_rentPOST = ifelse(rentE_16>0, interp_rent/rentE_16, NA),
            # rentPRE = ifelse(rentE_09>0, rentE_16/rentE_09,NA),
            huPOST = ifelse(huE_16>0, huE_24/huE_16,NA),
            rhuPOST = ifelse(rhuE_16>0, rhuE_24/rhuE_16,NA),
            rhu_inventoryPOST = ifelse(rhu_inventoryE_16>0,
                                      rhu_inventoryE_24/rhu_inventoryE_16, NA_real_),
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
    mutate(m_flag_rhuPOST = if_else(is.na(rhuPOST), 1, 0),
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
