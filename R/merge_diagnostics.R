# Geographic alignment and diagnostic helpers for 04_merge.Rmd. Source after merge_helpers.R and
# geography_qa.R; uses the notebook's existing dplyr/tidyr/purrr packages.

merge_relationship_classes <- c(
  "consistent", "one_to_one_changed", "split", "merge", "many_to_many"
)

assert_merge_measures <- function(df, key, label) {
  required <- c(key, "rentE", "rhuE", "rhu_inventoryE", "smfE", "sfd_detE")
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
  if (!is.double(xwalk$geo_consistent) || !is.character(xwalk$relationship_class)) {
    stop("Crosswalk: invalid consistency encoding storage")
  }
  status_qa <- summarize_merge_geography(xwalk, "Crosswalk before alignment")
  print(status_qa$status, n = Inf)
  print(status_qa$classes, n = Inf)
  known_status <- xwalk$geo_consistent %in% c(0, 1)
  known_class <- xwalk$relationship_class %in% merge_relationship_classes
  if (!all((xwalk$geo_consistent[known_status & known_class] == 1) ==
             (xwalk$relationship_class[known_status & known_class] == "consistent"))) {
    stop("Crosswalk: contradictory consistency flag and classification")
  }
  if (!is.integer(xwalk$n_2010_partners) || !is.integer(xwalk$n_2020_partners) ||
      anyNA(xwalk$n_2010_partners) || any(xwalk$n_2010_partners < 1L)) {
    stop("Crosswalk: invalid partner counts")
  }
  unique_partner <- xwalk$n_2010_partners == 1L
  one_to_one <- xwalk$relationship_class %in% c("consistent", "one_to_one_changed")
  consistent_flag <- xwalk$geo_consistent %in% 1
  if (!identical(!is.na(xwalk$tr2010_id), unique_partner) ||
      !identical(!is.na(xwalk$n_2020_partners), unique_partner) ||
      !all(unique_partner[known_class] == (xwalk$relationship_class[known_class] %in%
                                            c("consistent", "one_to_one_changed", "split"))) ||
      any(xwalk$n_2020_partners[unique_partner] < 1L) ||
      any(xwalk$n_2020_partners[one_to_one] != 1L) ||
      any(xwalk$n_2020_partners[xwalk$relationship_class %in% "split"] <= 1L) ||
      any(!unique_partner[consistent_flag]) ||
      any(xwalk$n_2020_partners[consistent_flag] != 1L)) {
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
  report_n(consistent, "Consistent links eligible for Census measurement and paired diagnostics")
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
    for (level in group_levels) masks[[level]] <- !is.na(values) & values == level
    masks[["status_missing"]] <- is.na(values)
    unexpected <- !is.na(values) & !values %in% group_levels
    if (any(unexpected)) masks[["status_unexpected"]] <- unexpected
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
    relationship_class = factor(dplyr::case_when(
      is.na(df$relationship_class) ~ "status_missing",
      df$relationship_class %in% merge_relationship_classes ~ df$relationship_class,
      .default = "status_unexpected"
    ), levels = c(merge_relationship_classes, "status_missing", "status_unexpected"))
  ) |>
    dplyr::count(relationship_class, .drop = FALSE, name = "n_tracts") |>
    dplyr::mutate(universe = label, share = diagnostic_ratio(n_tracts, rep(nrow(df), dplyr::n())))
  flag_counts <- tibble::tibble(
    geo_status = factor(dplyr::case_when(
      df$geo_consistent == 1 ~ "consistent", df$geo_consistent == 0 ~ "not_consistent",
      is.na(df$geo_consistent) ~ "status_missing", .default = "status_unexpected"
    ), levels = c("consistent", "not_consistent", "status_missing", "status_unexpected"))
  ) |>
    dplyr::count(geo_status, .drop = FALSE, name = "n_tracts") |>
    dplyr::mutate(universe = label, share = diagnostic_ratio(n_tracts, rep(nrow(df), dplyr::n())))
  stopifnot(sum(class_counts$n_tracts) == nrow(df), sum(flag_counts$n_tracts) == nrow(df))
  list(classes = class_counts, status = flag_counts)
}

# Equality treats NA and NaN as missing, and compares every observed value exactly.
assert_hierarchical_2024 <- function(df) {
  fields <- merge_2024_field_map()
  required <- c("geo_consistent", "acs_source_24", unlist(fields, use.names = FALSE))
  if (!all(required %in% names(df))) stop("Hierarchy QA: missing canonical/source fields")
  masks <- list(tract = df$geo_consistent %in% 1, bg_agg = !(df$geo_consistent %in% 1))
  if (!identical(df$acs_source_24[masks$tract], rep("tract", sum(masks$tract))) ||
      !identical(df$acs_source_24[masks$bg_agg], rep("bg_agg", sum(masks$bg_agg)))) {
    stop("Hierarchy QA: selected source disagrees with geographic consistency")
  }
  purrr::imap_dfr(masks, function(mask, source) {
    alternative <- if (source == "tract") "bg_agg" else "tract"
    purrr::map_dfr(seq_len(nrow(fields)), function(i) {
      canonical <- df[[fields$canonical[i]]]
      selected <- df[[fields[[source]][i]]]
      other <- df[[fields[[alternative]][i]]]
      missing_mismatch <- is.na(canonical[mask]) != is.na(selected[mask])
      observed <- mask & !is.na(canonical) & !is.na(selected)
      n_mismatch <- sum(missing_mismatch) + sum(canonical[observed] != selected[observed])
      if (n_mismatch) {
        stop("Hierarchy QA: ", fields$canonical[i], " violates ", source,
             " selection or missingness")
      }
      tibble::tibble(source = source, measure = fields$canonical[i], n_selected = sum(mask),
                     n_selected_missing = sum(mask & is.na(selected)),
                     n_alternative_available_when_selected_missing =
                       sum(mask & is.na(selected) & !is.na(other)),
                     n_mismatch = n_mismatch)
    })
  })
}

# Reconstruct old-rule missingness on the current inputs; no saved panel is read.
summarize_hierarchy_correction <- function(df) {
  fields <- merge_2024_field_map()
  required <- c("geo_consistent", fields$canonical, fields$bg_agg)
  if (!all(required %in% names(df))) stop("Hierarchy correction QA: missing canonical/source fields")
  not_consistent <- !(df$geo_consistent %in% 1)
  old_bg_selected <- df$geo_consistent %in% 0
  purrr::map_dfr(seq_len(nrow(fields)), function(i) {
    bg_observed <- !is.na(df[[fields$bg_agg[i]]])
    missing_before <- !old_bg_selected | !bg_observed
    missing_after <- is.na(df[[fields$canonical[i]]])
    tibble::tibble(
      measure = fields$canonical[i],
      n_not_consistent = sum(not_consistent),
      n_bg_observed = sum(not_consistent & bg_observed),
      n_canonical_missing_before = sum(not_consistent & missing_before),
      n_canonical_missing_after = sum(not_consistent & missing_after),
      n_bg_observed_canonical_missing_before = sum(not_consistent & bg_observed & missing_before),
      n_bg_observed_canonical_missing_after = sum(not_consistent & bg_observed & missing_after)
    )
  })
}

summarize_source_selection <- function(df) {
  counts <- tibble::tibble(source = factor(
    dplyr::coalesce(df$acs_source_24, "unassigned"), levels = c("tract", "bg_agg", "unassigned")
  )) |>
    dplyr::count(source, .drop = FALSE, name = "n_tracts") |>
    dplyr::mutate(share = diagnostic_ratio(n_tracts, rep(nrow(df), dplyr::n())))
  stopifnot(sum(counts$n_tracts) == nrow(df))
  missingness <- summarize_diagnostic_measures(
    df, c("rentE_24", "interp_rent", "rhuE_24", "rhu_inventoryE_24", "med_hhincE_24",
          "rentPOST", "interp_rentPOST", "rhu_inventoryPOST"), "acs_source_24", c("tract", "bg_agg")
  ) |>
    dplyr::mutate(group = dplyr::recode(group, status_missing = "unassigned"),
                  share_missing = diagnostic_ratio(n_missing, n_total))
  list(counts = counts, missingness = missingness,
       geography = summarize_merge_geography(df, "Canonical 2010 panel"))
}
