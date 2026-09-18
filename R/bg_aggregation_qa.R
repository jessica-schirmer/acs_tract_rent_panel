# BG-only contributor and count QA. Load after assemble_helpers.R/geography_qa.R.
# Diagnostics never enter the production Feather.

bg_weight_columns <- function() c("wt_pop", "wt_hh", "wt_hu", "wt_renthu")

bg_count_measure_map <- function() {
  families <- list(
    wt_pop = c("popE", "pop_blkE", "pop_hspE", "pop_aaE", "pop_raceE", "pop_ethnE"),
    wt_hh = "hhE",
    wt_hu = c("huE", "tot_vacE", "tot_vac_baseE", "sfd_detE", "sfd_baseE", "mf5E",
              "vac_forrentE", "vac_forsaleE", "ohuE", "smfE"),
    wt_renthu = c("rhuE", "rhu_baseE", "rhucashE", paste0("grentcat", 1:24, "E"),
                  "rhu_miss_rent")
  )
  tibble(measure = unlist(families, use.names = FALSE),
         family = rep(names(families), lengths(families))) |>
    mutate(source = if_else(measure == "mf5E", "mfE", measure))
}

bg_inventory_measure_map <- function() {
  tibble(measure = c("rhuE", "vac_forrentE", "vac_rentedE"),
         family = "wt_renthu", source = measure)
}

bg_validate_links <- function(df) {
  keys <- c("bg2020_id", "tr2010_id")
  weights <- bg_weight_columns()
  if (!is.data.frame(df) || anyDuplicated(names(df)) ||
      !all(c(keys, weights) %in% names(df))) stop("BG links require keys and all four weights")
  for (key in keys) {
    digits <- if (key == "bg2020_id") 12 else 11
    if (!is.character(df[[key]]) || anyNA(df[[key]]) ||
        !all(grepl(paste0("^[0-9]{", digits, "}$"), df[[key]]))) {
      stop("BG links require valid character GEOIDs: ", key)
    }
  }
  if (anyDuplicated(df[keys])) stop("BG links contain duplicate allocation pairs")
  if (!all(vapply(df[weights], function(w) {
    is.numeric(w) && !is.complex(w) && all(is.finite(w) & w >= 0 & w <= 1)
  }, logical(1)))) stop("BG weights must be numeric finite fractions in [0, 1]")
  invisible(TRUE)
}

# Construct once from the original target links AFTER the full-source weight audit.
# Locked bindings prevent later reference edits, including nested replacements.
new_bg_aggregation_reference <- function(original_target_links) {
  bg_validate_links(original_target_links)
  reference <- new.env(parent = emptyenv())
  reference$links <- original_target_links |>
    ungroup() |>
    as_tibble() |>
    select(bg2020_id, tr2010_id, all_of(bg_weight_columns())) |>
    arrange(bg2020_id, tr2010_id)
  reference$targets <- sort(unique(reference$links$tr2010_id))
  reference$contributors <- reference$links |>
    pivot_longer(all_of(bg_weight_columns()), names_to = "family", values_to = "weight") |>
    filter(weight > 0)
  lockEnvironment(reference, bindings = TRUE)
  reference
}

# ACS row presence is an explicit join marker, independent of estimate missingness.
assert_bg_contributors <- function(df, reference) {
  bg_validate_links(df)
  if (!".acs_present" %in% names(df) || !is.logical(df$.acs_present) || length(df$.acs_present) != nrow(df) ||
      anyNA(df$.acs_present)) stop("BG allocations require a nonmissing logical .acs_present join marker")
  keys <- c("bg2020_id", "tr2010_id")
  missing <- anti_join(reference$links, df, by = keys)
  unexpected <- anti_join(df, reference$links, by = keys) |>
    select(all_of(names(reference$links)))
  if (nrow(missing) || nrow(unexpected) || !setequal(df$tr2010_id, reference$targets)) {
    print(head(missing, 10L), width = Inf)
    print(head(unexpected, 10L), width = Inf)
    stop("BG contributor integrity failed: missing/unexpected allocation pairs or lost targets")
  }
  actual <- df |> ungroup() |> as_tibble() |> select(all_of(names(reference$links))) |>
    arrange(bg2020_id, tr2010_id)
  if (!identical(actual, reference$links)) stop("BG contributor integrity failed: changed allocation weights")
  unmatched <- df |> filter(!.acs_present) |>
    select(all_of(names(reference$links)))
  required <- unmatched |> filter(if_any(all_of(bg_weight_columns()), ~ .x > 0))
  if (nrow(required)) {
    print(head(required, 10L), width = Inf)
    stop("BG contributor integrity failed: required links have no ACS source row")
  }
  invisible(unmatched)
}

bg_measure_values <- function(df, source) {
  if (source == "rhu_miss_rent") {
    if (!all(c("rentE", "rhuE") %in% names(df))) stop("BG missing-rent count requires rentE and rhuE")
    return(if_else(is.na(df$rentE), df$rhuE, 0))
  }
  if (!source %in% names(df)) stop("Missing BG source count: ", source)
  df[[source]]
}

# Family missing-value counts are missing cells across that family's measures.
# Measure rows distinguish absent ACS links from present rows with NA/NaN counts.
bg_aggregation_diagnostics <- function(df, reference, measures = bg_count_measure_map()) {
  exempt <- assert_bg_contributors(df, reference)
  presence <- df |> ungroup() |> select(bg2020_id, tr2010_id, .acs_present)
  contributors <- reference$contributors |>
    left_join(presence, by = c("bg2020_id", "tr2010_id"), relationship = "many-to-one")
  families <- expand_grid(tr2010_id = reference$targets, family = bg_weight_columns()) |>
    left_join(contributors |> group_by(tr2010_id, family) |>
                summarise(n_expected = n(), n_matched = sum(.acs_present), .groups = "drop"),
              by = c("tr2010_id", "family"), relationship = "one-to-one") |>
    mutate(n_expected = coalesce(n_expected, 0L), n_matched = coalesce(n_matched, 0L),
           n_missing_links = n_expected - n_matched, zero_contributors = n_expected == 0L)
  if (is.null(measures)) {
    families <- families |> mutate(complete = n_missing_links == 0L)
    return(list(family = families, zero_weight_unmatched = exempt))
  }
  if (anyDuplicated(measures$measure) || !all(measures$family %in% bg_weight_columns())) {
    stop("Invalid BG measure map")
  }
  missing_sources <- list()
  measure_qa <- lapply(seq_len(nrow(measures)), function(i) {
    spec <- measures[i, ]
    values <- bg_measure_values(df, spec$source)
    if (!is.numeric(values) || is.complex(values)) stop("BG source counts must be numeric: ", spec$source)
    source <- presence |> mutate(value = values)
    required <- contributors |> filter(family == spec$family) |>
      left_join(select(source, bg2020_id, tr2010_id, value),
                by = c("bg2020_id", "tr2010_id"), relationship = "many-to-one")
    observed <- required$value[!is.na(required$value)]
    if (any(!is.finite(observed) | observed < 0)) {
      stop("Observed contributing BG counts must be finite and nonnegative: ", spec$source)
    }
    missing_sources[[i]] <<- required |>
      filter(.acs_present & is.na(value)) |> mutate(measure = spec$measure)
    totals <- required |> group_by(tr2010_id) |>
      summarise(n_missing_values = sum(.acs_present & is.na(value)),
                expected_total = if (any(!.acs_present | is.na(value))) NA_real_ else sum(value * weight),
                .groups = "drop")
    families |> filter(family == spec$family) |>
      left_join(totals, by = "tr2010_id", relationship = "one-to-one") |>
      mutate(measure = spec$measure,
             n_missing_values = coalesce(n_missing_values, 0L),
             expected_total = if_else(zero_contributors, 0, expected_total),
             complete = n_missing_links == 0L & n_missing_values == 0L)
  }) |> bind_rows() |> arrange(tr2010_id, measure)
  families <- families |>
    left_join(measure_qa |> group_by(tr2010_id, family) |>
                summarise(n_missing_values = sum(n_missing_values),
                          n_incomplete_measures = sum(!complete), .groups = "drop"),
              by = c("tr2010_id", "family"), relationship = "one-to-one") |>
    mutate(n_missing_values = coalesce(n_missing_values, 0L),
           n_incomplete_measures = coalesce(n_incomplete_measures, 0L),
           complete = n_missing_links == 0L & n_incomplete_measures == 0L)
  list(family = families, measure = measure_qa,
       missing_sources = bind_rows(missing_sources) |> arrange(tr2010_id, measure, bg2020_id),
       zero_weight_unmatched = exempt |> arrange(bg2020_id, tr2010_id))
}

assert_bg_diagnostics <- function(df, reference, diagnostics, measures = bg_count_measure_map()) {
  expected <- bg_aggregation_diagnostics(df, reference, measures)
  keys <- list(family = c("tr2010_id", "family"), measure = c("tr2010_id", "measure"),
               missing_sources = c("tr2010_id", "measure", "bg2020_id"),
               zero_weight_unmatched = c("bg2020_id", "tr2010_id"))
  agrees <- is.list(diagnostics) && identical(names(diagnostics), names(expected)) &&
    all(vapply(names(expected), function(name) {
      actual <- diagnostics[[name]]
      is.data.frame(actual) && all(keys[[name]] %in% names(actual)) &&
        identical(arrange(actual, across(all_of(keys[[name]]))),
                  arrange(expected[[name]], across(all_of(keys[[name]]))))
    }, logical(1)))
  if (!agrees) {
    stop("BG diagnostics disagree with the reference or aggregation frame")
  }
  invisible(TRUE)
}

# Independently computed expected totals use no missing-value removal. Incomplete
# groups must be missing; numerical reconciliation applies only to complete groups.
assert_bg_count_aggregates <- function(output, df, reference, diagnostics, tolerance = 1e-10) {
  assert_bg_diagnostics(df, reference, diagnostics)
  assert_tract_keys(output, reference$targets, "BG count reconciliation")
  measures <- diagnostics$measure
  if (!all(unique(measures$measure) %in% names(output))) stop("BG aggregate count columns missing")
  actual <- output |> select(tr2010_id, all_of(unique(measures$measure))) |>
    pivot_longer(-tr2010_id, names_to = "measure", values_to = "actual")
  reconciliation <- left_join(measures, actual, by = c("tr2010_id", "measure"),
                              relationship = "one-to-one")
  complete <- reconciliation$complete
  observed <- reconciliation$actual[complete]
  expected <- reconciliation$expected_total[complete]
  if (any(!is.na(reconciliation$actual[!complete])) ||
      any(!is.finite(observed)) ||
      any(abs(observed - expected) > tolerance * pmax(1, abs(observed), abs(expected)))) {
    stop("BG aggregate counts disagree with source completeness or weighted totals")
  }
  invisible(reconciliation)
}

# Verify the existing inventory helper against reference-based component diagnostics.
assert_bg_inventory_reference <- function(df, reference, inventory) {
  qa <- bg_aggregation_diagnostics(df, reference, bg_inventory_measure_map())
  assert_tract_keys(inventory, reference$targets, "BG inventory reference")
  for (component in bg_inventory_measure_map()$measure) {
    expected <- qa$measure |> filter(measure == component)
    actual <- inventory[match(expected$tr2010_id, inventory$tr2010_id), ]
    if (!identical(actual$n_contributing, expected$n_expected) ||
        !identical(actual[[paste0("n_missing_", component)]], expected$n_missing_values) ||
        !isTRUE(all.equal(actual[[paste0("inventory_", component)]], expected$expected_total,
                          tolerance = 1e-10))) {
      stop("BG inventory diagnostics disagree with reference contributors/components")
    }
  }
  expected <- qa$family |> filter(family == "wt_renthu")
  actual <- inventory[match(expected$tr2010_id, inventory$tr2010_id), ]
  if (!identical(actual$inventory_incomplete, !expected$complete)) {
    stop("BG inventory completeness disagrees with reference")
  }
  assert_rental_inventory(inventory, inventory, "BG independently checked inventory")
  invisible(qa)
}

# Expectations isolate only the count policy. Income and raw MOEs are identical on
# both sides; dependent fields use the unchanged production formula helpers.
bg_count_parity_expectations <- function(df, reference) {
  qa <- bg_aggregation_diagnostics(df, reference)
  corrected <- calc_agg_vars(df, tr2010_id) |> rename(mf5E = mfE)
  map <- bg_count_measure_map()
  legacy <- corrected
  for (i in seq_len(nrow(map))) {
    values <- bg_measure_values(df, map$source[i])
    source <- df |> ungroup() |>
      transmute(tr2010_id, value = values, weight = .data[[map$family[i]]])
    old <- source |> group_by(tr2010_id) |>
      summarise(value = sum(value * weight, na.rm = TRUE), .groups = "drop")
    expected <- qa$measure |> filter(measure == map$measure[i])
    corrected[[map$measure[i]]] <- expected$expected_total[match(corrected$tr2010_id, expected$tr2010_id)]
    legacy[[map$measure[i]]] <- old$value[match(legacy$tr2010_id, old$tr2010_id)]
  }
  derive <- function(counts) {
    counts |> calc_missing_vars() |> calc_pct_vars() |> calc_cv(source = "bg_agg") |>
      mutate(nsfaE = smfE + mf5E,
             pctrvacE = if_else((rhuE + vac_forrentE) > 0,
                                vac_forrentE / (rhuE + vac_forrentE), NA_real_),
             pctsvacE = if_else((ohuE + vac_forsaleE) > 0,
                                vac_forsaleE / (ohuE + vac_forsaleE), NA_real_)) |>
      left_join(calc_interp_rent(counts), by = "tr2010_id", relationship = "one-to-one") |>
      select(tr2010_id, all_of(bg_count_correction_columns())) |>
      pivot_longer(-tr2010_id, names_to = "variable", values_to = "value")
  }
  left_join(derive(legacy) |> rename(legacy = value),
            derive(corrected) |> rename(corrected = value),
            by = c("tr2010_id", "variable"), relationship = "one-to-one") |>
    filter(xor(is.na(legacy), is.na(corrected)) |
             (!is.na(legacy) & !is.na(corrected) & legacy != corrected))
}
