# Step 1 input and Feather QA. Uses the notebook's existing dplyr/tidyr packages.

# Wide ACS output uses the first alias for each distinct requested Census code.
acs_request_columns <- function(variables) {
  aliases <- names(variables)[!duplicated(variables)]
  as.vector(outer(aliases, c("E", "M"), paste0))
}

bg_allocation_weight_columns <- function() {
  c("wt_pop", "wt_hh", "wt_hu", "wt_renthu")
}

assert_step1_columns <- function(df, required, label) {
  if (!is.data.frame(df) || nrow(df) == 0L) {
    stop(label, ": expected a nonempty data frame")
  }
  if (anyDuplicated(names(df))) stop(label, ": duplicate column names")
  missing <- setdiff(required, names(df))
  if (length(missing)) {
    stop(label, ": missing required columns: ", paste(missing, collapse = ", "))
  }
  invisible(df)
}

assert_step1_geoid <- function(x, column, digits, label) {
  if (!is.character(x)) stop(label, ": ", column, " must be character")
  if (anyNA(x) || !all(grepl(paste0("^[0-9]{", digits, "}$"), x))) {
    stop(label, ": ", column, " must contain nonmissing ", digits, "-digit GEOIDs")
  }
  invisible(x)
}

assert_acs_bg_input <- function(df, variables, key = "bg2020_id",
                                require_flag = TRUE,
                                label = "2024 ACS block groups") {
  numeric_columns <- acs_request_columns(variables)
  assert_step1_columns(df, c(key, "NAME", numeric_columns,
                            if (require_flag) "rent_id"), label)
  assert_step1_geoid(df[[key]], key, 12L, label)
  if (anyDuplicated(df[[key]])) stop(label, ": duplicate BG keys after reshaping")
  if (!is.character(df$NAME)) stop(label, ": NAME must be character")
  nonnumeric <- numeric_columns[!vapply(df[numeric_columns], is.numeric, logical(1))]
  if (length(nonnumeric)) {
    stop(label, ": estimate/MOE columns must be numeric: ", paste(nonnumeric, collapse = ", "))
  }
  if (require_flag && (!is.logical(df$rent_id) || anyNA(df$rent_id) || !all(df$rent_id))) {
    stop(label, ": rent_id must be logical, nonmissing, and TRUE")
  }
  invisible(df)
}

# Returns full-source sums for review; does not change links or weights.
assert_bg_crosswalk <- function(df, tolerance = 1e-6,
                                label = "BG-to-2010-tract crosswalk") {
  keys <- c("bg2020_id", "tr2010_id")
  weights <- bg_allocation_weight_columns()
  assert_step1_columns(df, c(keys, weights, "x_id"), label)
  assert_step1_geoid(df$bg2020_id, "bg2020_id", 12L, label)
  assert_step1_geoid(df$tr2010_id, "tr2010_id", 11L, label)
  if (anyDuplicated(df[keys])) stop(label, ": duplicate allocation pairs")
  nonnumeric <- weights[!vapply(df[weights], is.numeric, logical(1))]
  if (length(nonnumeric)) {
    stop(label, ": allocation weights must be numeric: ", paste(nonnumeric, collapse = ", "))
  }
  invalid <- weights[!vapply(df[weights], function(w) {
    all(is.finite(w) & w >= 0 & w <= 1)
  }, logical(1))]
  if (length(invalid)) {
    stop(label, ": allocation weights must be finite and within [0, 1]: ",
         paste(invalid, collapse = ", "))
  }
  if (!is.logical(df$x_id) || anyNA(df$x_id) || !all(df$x_id)) {
    stop(label, ": x_id must be logical, nonmissing, and TRUE")
  }
  weight_sums <- df |>
    dplyr::group_by(bg2020_id) |>
    dplyr::summarise(dplyr::across(dplyr::all_of(weights), sum), .groups = "drop") |>
    tidyr::pivot_longer(dplyr::all_of(weights), names_to = "weight", values_to = "weight_sum") |>
    dplyr::mutate(absolute_error = abs(weight_sum - 1))
  summary <- weight_sums |>
    dplyr::group_by(weight) |>
    dplyr::summarise(n_sources = dplyr::n(), min_sum = min(weight_sum),
                     max_sum = max(weight_sum), max_error = max(absolute_error),
                     n_failed = sum(absolute_error > tolerance), .groups = "drop")
  cat(label, "| full-source weight reconciliation (tolerance", tolerance, "):\n")
  print(summary, n = Inf, width = Inf)
  failed <- dplyr::filter(weight_sums, absolute_error > tolerance)
  if (nrow(failed)) {
    print(utils::head(failed, 10L), width = Inf)
    stop(label, ": full source weights must sum to one within ", tolerance,
         " (", nrow(failed), " source/weight failures; first 10 shown)")
  }
  invisible(weight_sums)
}

# Inputs have already passed structural checks; coverage never filters either input.
bg_coverage_diagnostics <- function(acs, crosswalk) {
  acs_ids <- dplyr::distinct(acs, bg2020_id)
  crosswalk_ids <- dplyr::distinct(crosswalk, bg2020_id)
  acs_only <- dplyr::anti_join(acs_ids, crosswalk_ids, by = "bg2020_id") |>
    dplyr::arrange(bg2020_id)
  crosswalk_only <- dplyr::anti_join(crosswalk_ids, acs_ids, by = "bg2020_id") |>
    dplyr::arrange(bg2020_id)
  by_county <- dplyr::bind_rows(
    dplyr::mutate(acs_only, coverage = "acs_only"),
    dplyr::mutate(crosswalk_only, coverage = "crosswalk_only")
  ) |>
    dplyr::mutate(source_state_fips = substr(bg2020_id, 1, 2),
                  source_county_fips = substr(bg2020_id, 1, 5)) |>
    dplyr::count(coverage, source_state_fips, source_county_fips, name = "n_bg")
  list(
    summary = dplyr::tibble(coverage = c("acs_only", "crosswalk_only"),
                            n_bg = c(nrow(acs_only), nrow(crosswalk_only))),
    by_county = by_county,
    acs_only = acs_only,
    crosswalk_only = crosswalk_only,
    crosswalk_only_links = dplyr::semi_join(crosswalk, crosswalk_only, by = "bg2020_id")
  )
}

# Feather preserves row order; compare every column exactly, including NA/NaN.
assert_step1_readback <- function(saved, validated, keys, label) {
  if (nrow(saved) != nrow(validated)) stop(label, ": readback row count changed")
  if (!identical(names(saved), names(validated))) {
    stop(label, ": readback column names or order changed")
  }
  types_match <- vapply(names(validated), function(column) {
    identical(typeof(saved[[column]]), typeof(validated[[column]])) &&
      identical(class(saved[[column]]), class(validated[[column]]))
  }, logical(1))
  if (!all(types_match)) {
    stop(label, ": readback column types changed: ",
         paste(names(validated)[!types_match], collapse = ", "))
  }
  if (!all(vapply(keys, function(key) identical(saved[[key]], validated[[key]]), logical(1)))) {
    stop(label, ": readback keys or row order changed")
  }
  values_match <- vapply(names(validated), function(column) {
    identical(saved[[column]], validated[[column]], num.eq = FALSE)
  }, logical(1))
  if (!all(values_match)) {
    stop(label, ": readback values changed (exact comparison): ",
         paste(names(validated)[!values_match], collapse = ", "))
  }
  cat(label, "| exact readback passed:", nrow(saved), "rows; keys, types, and all values preserved\n")
  invisible(saved)
}
