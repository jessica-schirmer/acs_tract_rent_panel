# Diagnostic-only helpers for 04_merge.Rmd. Source after merge_helpers.R and
# geography_qa.R; uses the notebook's existing dplyr/tidyr/purrr packages.

merge_relationship_classes <- c(
  "consistent", "one_to_one_changed", "split", "merge", "many_to_many"
)

assert_merge_measures <- function(df, key, label) {
  required <- c(key, "rentE", "rhuE", "rhu_inventoryE")
  if (!all(required %in% names(df))) stop(label, ": missing documented input fields")
  assert_unique_key(df, key, label)
  if (!is.character(df[[key]]) || !all(grepl("^06[0-9]{9}$", df[[key]]))) {
    stop(label, ": expected 11-digit California tract keys")
  }
  for (column in required[-1]) {
    x <- df[[column]]
    if (!is.numeric(x) || any(!is.na(x) & (!is.finite(x) | x < 0))) {
      stop(label, ": ", column, " must be numeric, finite and nonnegative when observed")
    }
  }
  invisible(df)
}

# Reduce only agreeing status records; retain a 2020 measurement link only for
# the documented consistent subset. Missing multi-partner IDs stay unresolved.
prepare_merge_geography <- function(xwalk) {
  required <- c("tr2020_id", "tr2010_id", "geo_consistent", "relationship_class",
                "same_geoid", "n_2010_partners", "n_2020_partners")
  if (!all(required %in% names(xwalk))) stop("Crosswalk: missing documented fields")
  assert_unique_key(xwalk, "tr2020_id", "Geographic-consistency input")
  if (!is.character(xwalk$tr2020_id) || !is.character(xwalk$tr2010_id) ||
      !all(grepl("^06[0-9]{9}$", xwalk$tr2020_id)) ||
      !all(is.na(xwalk$tr2010_id) | grepl("^[0-9]{11}$", xwalk$tr2010_id))) {
    stop("Crosswalk: invalid native tract keys")
  }
  if (!is.double(xwalk$geo_consistent) || anyNA(xwalk$geo_consistent) ||
      !all(xwalk$geo_consistent %in% c(0, 1)) ||
      !is.character(xwalk$relationship_class) || anyNA(xwalk$relationship_class) ||
      !all(xwalk$relationship_class %in% merge_relationship_classes) ||
      !all((xwalk$geo_consistent == 1) == (xwalk$relationship_class == "consistent"))) {
    stop("Crosswalk: invalid consistency encoding or classification")
  }
  unique_partner <- xwalk$relationship_class %in%
    c("consistent", "one_to_one_changed", "split")
  one_to_one <- xwalk$relationship_class %in% c("consistent", "one_to_one_changed")
  if (!is.integer(xwalk$n_2010_partners) || !is.integer(xwalk$n_2020_partners) ||
      anyNA(xwalk$n_2010_partners) || any(xwalk$n_2010_partners < 1L) ||
      !identical(!is.na(xwalk$tr2010_id), unique_partner) ||
      !all((xwalk$n_2010_partners == 1L) == unique_partner) ||
      !identical(!is.na(xwalk$n_2020_partners), unique_partner) ||
      any(xwalk$n_2020_partners[unique_partner] < 1L) ||
      any(xwalk$n_2020_partners[one_to_one] != 1L) ||
      any(xwalk$n_2020_partners[xwalk$relationship_class == "split"] <= 1L)) {
    stop("Crosswalk: partner counts or retained 2010 keys disagree with classes")
  }
  if (!is.double(xwalk$same_geoid) ||
      !identical(!is.na(xwalk$same_geoid), unique_partner) ||
      !all(xwalk$same_geoid[unique_partner] ==
             as.double(xwalk$tr2020_id[unique_partner] == xwalk$tr2010_id[unique_partner]))) {
    stop("Crosswalk: invalid same_geoid diagnostic")
  }
  statuses <- xwalk |>
    dplyr::filter(!is.na(tr2010_id)) |>
    dplyr::distinct(tr2010_id, geo_consistent, relationship_class)
  assert_unique_key(statuses, "tr2010_id", "Agreeing 2010 status records")
  report_n(statuses, "Available 2010 statuses after collapsing agreeing links")
  consistent <- xwalk |>
    dplyr::filter(geo_consistent == 1) |>
    dplyr::select(tr2010_id, tr2020_id, same_geoid)
  assert_unique_key(consistent, "tr2010_id", "Consistent links, 2010 key")
  assert_unique_key(consistent, "tr2020_id", "Consistent links, 2020 key")
  report_n(consistent, "Consistent links eligible for paired measurement diagnostics")
  list(statuses = statuses, consistent = consistent)
}

# All new diagnostic joins preserve the left universe and reject name collisions.
merge_diagnostic_left_join <- function(left, right, by, label, left_key = "tr2010_id") {
  assert_unique_key(left, left_key, paste(label, "left"))
  assert_unique_key(right, by, paste(label, "right"))
  if (length(setdiff(intersect(names(left), names(right)), by))) {
    stop(label, ": explicitly name overlapping columns before joining")
  }
  joined <- dplyr::left_join(left, right, by = by, relationship = "many-to-one",
                           na_matches = "never")
  stopifnot("Diagnostic join must preserve left rows and key order" =
              identical(joined[[left_key]], left[[left_key]]))
  report_n(joined, paste0(label, " (expected ", nrow(left), "; no row multiplication)"))
  joined
}

diagnostic_ratio <- function(numerator, denominator) {
  stopifnot(length(numerator) == length(denominator))
  value <- rep(NA_real_, length(numerator))
  valid <- is.finite(numerator) & is.finite(denominator) & denominator > 0
  value[valid] <- numerator[valid] / denominator[valid]
  value
}

diagnostic_correlation <- function(x, y) {
  paired <- is.finite(x) & is.finite(y)
  if (sum(paired) < 2L || length(unique(x[paired])) < 2L ||
      length(unique(y[paired])) < 2L) return(NA_real_)
  stats::cor(x[paired], y[paired], method = "pearson")
}

# Empty/all-missing groups produce explicit NA statistics, never Inf/NaN.
diagnostic_summary <- function(x) {
  if (!is.numeric(x) || any(!is.na(x) & !is.finite(x))) {
    stop("Diagnostic measures must be numeric and finite when observed")
  }
  observed <- x[!is.na(x)]
  quantiles <- if (length(observed)) {
    unname(stats::quantile(observed, c(0, 0.25, 0.5, 0.75, 1)))
  } else rep(NA_real_, 5)
  tibble::tibble(
    n_total = length(x), n_observed = length(observed), n_missing = sum(is.na(x)),
    mean = if (length(observed)) mean(observed) else NA_real_,
    sd = if (length(observed) > 1L) stats::sd(observed) else NA_real_,
    min = quantiles[1], p25 = quantiles[2], median = quantiles[3],
    p75 = quantiles[4], max = quantiles[5]
  )
}

# Named masks include the full denominator and explicitly requested empty groups.
diagnostic_groups <- function(df, by = NULL, group_levels = NULL) {
  masks <- list(overall = rep(TRUE, nrow(df)))
  if (!is.null(by)) {
    values <- as.character(df[[by]])
    if (is.null(group_levels)) group_levels <- sort(unique(values[!is.na(values)]))
    if (!all(values[!is.na(values)] %in% group_levels)) stop("Unrecognized diagnostic group")
    for (level in group_levels) masks[[level]] <- !is.na(values) & values == level
    masks[["status_missing"]] <- is.na(values)
  }
  masks
}

summarize_diagnostic_measures <- function(df, measures, by = NULL, group_levels = NULL) {
  purrr::imap_dfr(diagnostic_groups(df, by, group_levels), function(mask, group) {
    purrr::map_dfr(measures, function(measure) {
      dplyr::bind_cols(tibble::tibble(group = group, measure = measure),
                       diagnostic_summary(df[[measure]][mask]))
    })
  })
}

# x is the numerator / minuend; y is the denominator / subtrahend. The values
# table retains tract identifiers so every discrepancy can be inspected.
compare_diagnostic_measures <- function(df, x, y, by = NULL, group_levels = NULL) {
  diagnostic_summary(df[[x]])
  diagnostic_summary(df[[y]])
  values <- df |>
    dplyr::select(dplyr::any_of(c("tr2010_id", "tr2020_id", "geo_consistent",
                                "relationship_class", by))) |>
    dplyr::mutate(x_value = df[[x]], y_value = df[[y]],
                  difference = x_value - y_value,
                  absolute_difference = abs(difference),
                  ratio = diagnostic_ratio(x_value, y_value))
  masks <- diagnostic_groups(df, by, group_levels)
  coverage <- purrr::imap_dfr(masks, function(mask, group) {
    a <- values$x_value[mask]
    b <- values$y_value[mask]
    paired <- !is.na(a) & !is.na(b)
    n_paired <- sum(paired)
    n_below <- sum(a[paired] < b[paired])
    tibble::tibble(
      group = group, x = x, y = y, n_total = length(a),
      n_x_observed = sum(!is.na(a)), n_x_missing = sum(is.na(a)),
      n_y_observed = sum(!is.na(b)), n_y_missing = sum(is.na(b)),
      n_paired = n_paired, n_y_missing_denominator = sum(is.na(b)),
      n_y_nonpositive_denominator = sum(!is.na(b) & b <= 0),
      n_paired_nonpositive_denominator = sum(paired & b <= 0, na.rm = TRUE),
      n_ratio = sum(!is.na(values$ratio[mask])),
      n_x_below_y = n_below,
      share_x_below_y = diagnostic_ratio(n_below, n_paired),
      correlation = diagnostic_correlation(a, b)
    )
  })
  summaries <- purrr::imap_dfr(masks, function(mask, group) {
    purrr::map_dfr(c("x_value", "y_value", "difference", "absolute_difference", "ratio"),
                   function(series) {
      dplyr::bind_cols(tibble::tibble(group = group, x = x, y = y, series = series),
                       diagnostic_summary(values[[series]][mask]))
    })
  })
  stopifnot(all(coverage$n_x_observed + coverage$n_x_missing == coverage$n_total),
            all(coverage$n_y_observed + coverage$n_y_missing == coverage$n_total),
            all(coverage$n_ratio + coverage$n_paired_nonpositive_denominator == coverage$n_paired))
  list(values = values, coverage = coverage, summaries = summaries)
}

summarize_merge_geography <- function(df, label) {
  class_counts <- tibble::tibble(
    relationship_class = factor(df$relationship_class,
                                levels = c(merge_relationship_classes, "status_missing"))
  ) |>
    dplyr::mutate(relationship_class = tidyr::replace_na(relationship_class, "status_missing")) |>
    dplyr::count(relationship_class, .drop = FALSE, name = "n_tracts") |>
    dplyr::mutate(universe = label, share = diagnostic_ratio(n_tracts, rep(nrow(df), dplyr::n())))
  flag_counts <- tibble::tibble(
    geo_status = factor(dplyr::case_when(
      df$geo_consistent == 1 ~ "consistent", df$geo_consistent == 0 ~ "not_consistent",
      .default = "status_missing"
    ), levels = c("consistent", "not_consistent", "status_missing"))
  ) |>
    dplyr::count(geo_status, .drop = FALSE, name = "n_tracts") |>
    dplyr::mutate(universe = label, share = diagnostic_ratio(n_tracts, rep(nrow(df), dplyr::n())))
  stopifnot(sum(class_counts$n_tracts) == nrow(df), sum(flag_counts$n_tracts) == nrow(df))
  list(classes = class_counts, status = flag_counts)
}
