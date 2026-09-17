# helpers.R --------------------------------------------------------------
# Reusable helper functions for the ACS tract cleaning pipeline.
#
# These functions assume the calling script has already loaded dplyr (for the
# data-masking helpers used below) and arrow (for feather I/O). Load them at the
# top of a notebook with:
#   source(here::here("R", "helpers.R"))


# ---- ACS estimate helpers ----------------------------------------------------

#' Summary statistics for a single ACS estimate column
#'
#' Reports the estimate's count, missingness, and distribution, and — when the
#' matching margin-of-error (`*M`) and coefficient-of-variation (`*CV`) columns
#' are present — their mean and upper-quantile values. The CV/MOE columns are
#' looked up by swapping the trailing `E` of `var_name` for `M`/`CV`.
#'
#' @param df Data frame containing the estimate column.
#' @param var_name Character. Name of the estimate column (e.g. `"rentE"`).
#' @return One-row data frame of summary statistics for `var_name`.
summ_var <- function(df, var_name) {
  moe_name <- sub("E$", "M", var_name)
  cv_name <- sub("E$", "CV", var_name)
  summarise(
    df,
    var        = var_name,
    n          = sum(!is.na(.data[[var_name]])),
    n_missing  = sum(is.na(.data[[var_name]])),
    mean       = mean(.data[[var_name]], na.rm = TRUE),
    min        = min(.data[[var_name]],  na.rm = TRUE),
    max        = max(.data[[var_name]],  na.rm = TRUE),
    mean_error = if (moe_name %in% names(df)) mean(.data[[moe_name]], na.rm = TRUE) else NA_real_,
    mean_cv    = if (cv_name %in% names(df)) mean(.data[[cv_name]], na.rm = TRUE) else NA_real_,
    p75_cv     = if (cv_name %in% names(df)) quantile(.data[[cv_name]], 0.75, na.rm = TRUE) else NA_real_,
    p90_cv     = if (cv_name %in% names(df)) quantile(.data[[cv_name]], 0.9, na.rm = TRUE) else NA_real_
  )
}


#' Rename a geographic ID column and tag the table with a join flag
#'
#' Renames `old_name` to `new_name` and adds a logical `rent_id = TRUE` column
#' used downstream as a "this row came from an ACS rent table" join indicator.
#'
#' @param df Data frame.
#' @param new_name Bare (unquoted) target column name for the ID.
#' @param old_name Bare (unquoted) source column name to rename.
#' @return Data frame with the renamed ID column and a `rent_id` flag.
rename_id <- function(df, new_name, old_name) {
  df <- df |>
    rename({{new_name}} := {{old_name}}) |>
    mutate(rent_id = TRUE)
}


# ---- I/O helper --------------------------------------------------------------

#' Write a data frame to a feather file
#'
#' @param df Data frame to write.
#' @param dir Character directory path, with a trailing slash (e.g. `"../../../data/"`).
#' @param name Character file name (e.g. `"acs_step1_2016_tract.feather"`).
#' @return Invisibly, the input `df` (after writing).
save_data <- function(df, dir, name) {
    df |>
        arrow::write_feather(paste0(dir,name))
}


# ---- Diagnostic / validation helpers ----------------------------------------

#' Print a row-count line for an import, save, or transform step
#'
#' Emits a one-line, comma-formatted row count for auditing. When `expected` is
#' supplied it is printed alongside the actual count for an explicit
#' expected-vs-actual comparison. The notebook performs no row-dropping filters,
#' so this is used to confirm import and save sizes rather than drop counts.
#'
#' @param df Data frame whose rows are counted.
#' @param label Character. Short description of the step being reported.
#' @param expected Optional numeric. A reference row count to print for comparison.
#' @return Invisibly, the input `df` (so the call can be piped through).
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
#' Uses three decimal places for small-magnitude values (e.g. allocation weights
#' in [0, 1]) and whole numbers with thousands separators for larger values
#' (e.g. ACS counts and dollar amounts). Non-finite inputs print as `"NA"`.
#'
#' @param x Numeric scalar.
#' @return Character scalar, formatted for display.
fmt_num <- function(x) {
  if (!is.finite(x)) return("NA")
  digits <- if (abs(x) < 100) 3 else 0
  formatC(x, format = "f", big.mark = ",", digits = digits)
}


#' Print mean, min, and max for every numeric column in a data frame
#'
#' Prints one line per numeric column in the form
#' `colname: mean=... | min=... | max=...`, formatted with thousands separators.
#' All-`NA` numeric columns print `NA` for each statistic.
#'
#' @param df Data frame to summarize.
#' @param name Optional character label printed as a header before the lines.
#' @return Invisibly, the input `df`.
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
