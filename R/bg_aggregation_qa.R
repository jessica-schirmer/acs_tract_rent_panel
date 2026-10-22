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

# Reconstruct only the source transformations needed by count QA, from the
# uncensored allocation snapshot rather than the mutable production frame.
bg_reconciliation_sources <- function(original) {
  original |>
    censor_bg_coverage_rent() |>
    mutate(mfE = mf_5_9E + mf_10_19E + mf_20_49E + mf_50E,
           smfE = sfd_attE + duplexE + quadplexE)
}

# Transitive required counts, including count denominators of weighted results.
# Missing source income/MOEs retain their established available-case treatment.
bg_dependent_count_map <- function() {
  c(bg_weighted_count_dependencies(), list(
    nsfaE = c("smfE", "mf5E"),
    pct_miss_rent = c("rhu_miss_rent", "rhuE"),
    tc_flag_rent_24 = rent_count_columns(), rent_censor_bound_24 = rent_count_columns(),
    pctrhuE = c("rhuE", "huE"), pctvacE = c("tot_vacE", "tot_vac_baseE"),
    pctblkE = c("pop_blkE", "pop_raceE"), pcthspE = c("pop_hspE", "pop_ethnE"),
    pctaaE = c("pop_aaE", "pop_raceE"), pctsfdE = c("sfd_detE", "sfd_baseE"),
    pctrvacE = c("rhuE", "vac_forrentE"), pctsvacE = c("ohuE", "vac_forsaleE"),
    pctrhuM = c("rhuE", "huE", "rhu_baseE"),
    pctblkM = c("pop_blkE", "pop_raceE", "popE"),
    pcthspM = c("pop_hspE", "pop_ethnE", "pop_raceE", "popE"),
    pctrhuCV = c("rhuE", "huE", "rhu_baseE"),
    pctblkCV = c("pop_blkE", "pop_raceE", "popE"),
    pcthspCV = c("pop_hspE", "pop_ethnE", "pop_raceE", "popE"),
    rhuCV = "rhuE", huCV = "huE", popCV = "popE", med_hhincCV = c("hhE", "rhuE"),
    interp_rent = c("rhucashE", paste0("grentcat", 1:24, "E"))
  ))
}

bg_dependent_diagnostics <- function(diagnostics, measures = names(bg_dependent_count_map())) {
  dependencies <- bg_dependent_count_map()[measures]
  if (any(vapply(dependencies, is.null, logical(1)))) stop("Unknown BG dependent measure")
  map <- tibble(dependent = rep(names(dependencies), lengths(dependencies)),
                measure = unlist(dependencies, use.names = FALSE))
  targets <- sort(unique(diagnostics$measure$tr2010_id))
  required <- expand_grid(tr2010_id = targets, dependent = measures) |>
    left_join(map, by = "dependent", relationship = "many-to-many") |>
    left_join(diagnostics$measure, by = c("tr2010_id", "measure"), relationship = "many-to-one")
  if (anyNA(required$complete)) stop("Missing BG dependent count diagnostics")
  summary <- required |> group_by(tr2010_id, dependent) |>
    summarise(complete = all(complete), zero_contributors = all(zero_contributors),
              missing_counts = paste(measure[!complete], collapse = ", "), .groups = "drop")
  missing_sources <- map |>
    inner_join(diagnostics$missing_sources, by = "measure", relationship = "many-to-many") |>
    select(tr2010_id, dependent, measure, bg2020_id, family, weight)
  list(measure = summary, missing_sources = missing_sources)
}

# The default covers every saved numeric dependent measure.
assert_bg_dependent_measures <- function(output, diagnostics,
                                         measures = names(bg_dependent_count_map())) {
  qa <- bg_dependent_diagnostics(diagnostics, measures)
  assert_tract_keys(output, unique(qa$measure$tr2010_id), "BG dependent completeness")
  if (!all(measures %in% names(output)) ||
      !all(vapply(output[measures], is.numeric, logical(1)))) stop("BG dependent columns missing or nonnumeric")
  actual <- output |> select(tr2010_id, all_of(measures)) |>
    pivot_longer(-tr2010_id, names_to = "dependent", values_to = "actual")
  checked <- left_join(qa$measure, actual, by = c("tr2010_id", "dependent"), relationship = "one-to-one")
  bad <- filter(checked, !complete & !is.na(actual))
  if (nrow(bad)) {
    print(head(bad, 10L), width = Inf)
    print(head(semi_join(qa$missing_sources, bad, by = c("tr2010_id", "dependent")), 10L), width = Inf)
    stop("BG dependent measure populated despite incomplete required counts")
  }
  invisible(qa)
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
    bad <- reconciliation |>
      filter((!complete & !is.na(actual)) |
               (complete & (!is.finite(actual) |
                              abs(actual - expected_total) > tolerance * pmax(1, abs(actual), abs(expected_total)))))
    print(head(bad, 10L), width = Inf)
    print(head(semi_join(diagnostics$missing_sources, bad, by = c("tr2010_id", "measure")), 10L), width = Inf)
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

# Historical partial-count weights are reconstructed only for two-sided parity.
bg_legacy_weighted_values <- function(df) {
  df |> group_by(tr2010_id) |>
    mutate(rel_wt_rhu = rhuE * wt_renthu / sum(rhuE * wt_renthu, na.rm = TRUE),
           rel_wt_hu = huE * wt_hu / sum(huE * wt_hu, na.rm = TRUE),
           rel_wt_pop = popE * wt_pop / sum(popE * wt_pop, na.rm = TRUE)) |>
    summarise(
      med_hhincE = weightedMean(med_hhincE, w = hhE * wt_hh, na.rm = TRUE),
      med_hhincM = weightedMean(med_hhincM, w = rhuE * wt_renthu, na.rm = TRUE),
      rhuM = if (sum(rhuE * wt_renthu, na.rm = TRUE) != 0)
        sqrt(sum((rhuM * rel_wt_rhu)^2, na.rm = TRUE)) else NA_real_,
      across(all_of(c("rhu_baseM", "tot_vacM", "tot_vac_baseM", "sfd_detM", "sfd_baseM")),
             ~ sqrt(sum((.x * rel_wt_hu)^2, na.rm = TRUE))),
      across(all_of(c("pop_blkM", "pop_hspM", "pop_aaM", "pop_raceM")),
             ~ sqrt(sum((.x * rel_wt_pop)^2, na.rm = TRUE))),
      huM = if (sum(huE * wt_hu, na.rm = TRUE) != 0)
        sqrt(sum((huM * rel_wt_hu)^2, na.rm = TRUE)) else NA_real_,
      popM = if (sum(popE * wt_pop, na.rm = TRUE) != 0)
        sqrt(sum((popM * rel_wt_pop)^2, na.rm = TRUE)) else NA_real_,
      .groups = "drop")
}

# Expectations isolate the count policy, including newly gated dependent cells.
# Income's independent rent-censoring correction keeps its own notebook audit.
bg_count_parity_expectations <- function(df, reference, uncensored_df) {
  qa <- bg_aggregation_diagnostics(df, reference)
  assert_bg_contributors(uncensored_df, reference)
  corrected <- calc_agg_vars(df, tr2010_id) |> rename(mf5E = mfE)
  map <- bg_count_measure_map()
  legacy <- corrected
  old_weighted <- bg_legacy_weighted_values(df)
  for (column in names(bg_weighted_count_dependencies())) {
    legacy[[column]] <- old_weighted[[column]][match(legacy$tr2010_id, old_weighted$tr2010_id)]
  }
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
  derive <- function(counts, old = FALSE) {
    rents <- calc_interp_rent(counts)
    if (old) {
      # Frozen pre-metadata interpolation for parity against partial-count
      # snapshots, before the audited cash/bin consistency check was added.
      lower <- c(0, 100, 150, 200, 250, 300, 350, 400, 450, 500, 550, 600,
                 650, 700, 750, 800, 900, 1000, 1250, 1500, 2000, 2500, 3000, 3500)
      upper <- c(99, 149, 199, 249, 299, 349, 399, 449, 499, 549, 599, 649,
                 699, 749, 799, 899, 999, 1249, 1499, 1999, 2499, 2999, 3499, NA)
      for (i in seq_len(nrow(counts))) {
        bins <- as.numeric(counts[i, paste0("grentcat", 1:24, "E")])
        half <- counts$rhucashE[i] / 2
        if (anyNA(c(bins, half)) || half <= 0) next
        cumulative <- cumsum(bins)
        k <- which(cumulative >= half)[1]
        if (!is.na(k) && k > 1L && k < 24L) rents$interp_rent[i] <-
          lower[k] + (upper[k] - lower[k]) * (half - cumulative[k - 1L]) / bins[k]
      }
    }
    counts |> calc_missing_vars() |> calc_pct_vars() |> calc_cv(source = "bg_agg") |>
      mutate(nsfaE = smfE + mf5E,
             pctrvacE = if_else((rhuE + vac_forrentE) > 0,
                                vac_forrentE / (rhuE + vac_forrentE), NA_real_),
             pctsvacE = if_else((ohuE + vac_forsaleE) > 0,
                                vac_forsaleE / (ohuE + vac_forsaleE), NA_real_)) |>
      left_join(select(rents, tr2010_id, interp_rent), by = "tr2010_id", relationship = "one-to-one") |>
      select(tr2010_id, all_of(bg_count_correction_columns())) |>
      pivot_longer(-tr2010_id, names_to = "variable", values_to = "value")
  }
  left_join(derive(legacy, old = TRUE) |> rename(legacy = value),
            derive(corrected) |> rename(corrected = value),
            by = c("tr2010_id", "variable"), relationship = "one-to-one") |>
    filter(xor(is.na(legacy), is.na(corrected)) |
             (!is.na(legacy) & !is.na(corrected) & legacy != corrected))
}
