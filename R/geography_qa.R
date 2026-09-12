# Geographic and key diagnostics shared by 02_assemble.Rmd and 03_merge.Rmd.
# Uses the notebooks' existing dplyr/tidyr packages; does not modify outputs.

assert_unique_key <- function(df, key, label) {
  keys <- df[, key, drop = FALSE]
  cat(label, ":", nrow(df), "rows |", nrow(unique(keys)), "unique keys\n")
  if (anyNA(keys) || any(duplicated(keys))) {
    stop(label, ": missing or duplicate key (", paste(key, collapse = ", "), ")")
  }
  invisible(df)
}

assert_tract_keys <- function(df, expected_ids, label) {
  assert_unique_key(df, "tr2010_id", label)
  if (!setequal(df$tr2010_id, expected_ids)) {
    stop(label, ": tract membership changed unexpectedly")
  }
  invisible(df)
}

assert_complete_tract_join <- function(df, expected_ids, label) {
  assert_tract_keys(df, expected_ids, label)
  if (anyNA(df$merge) || !all(df$merge == "both")) {
    stop(label, ": unmatched tract records")
  }
  invisible(df)
}

report_tract_counties <- function(df, target_counties, label) {
  assert_unique_key(df, "tr2010_id", label)
  observed <- df |>
    transmute(state = substr(tr2010_id, 1, 2), county = substr(tr2010_id, 3, 5)) |>
    dplyr::count(state, county, name = "tracts")
  county_counts <- full_join(
    tibble(state = "06", county = unname(target_counties)), observed,
    by = c("state", "county")
  ) |>
    mutate(tracts = coalesce(tracts, 0L)) |>
    arrange(state, county)
  print(county_counts, n = Inf)
  if (!all(grepl("^06[0-9]{9}$", df$tr2010_id)) ||
      !setequal(observed$county, unname(target_counties))) {
    stop(label, ": missing target counties or unintended destination geography")
  }
  invisible(county_counts)
}

# Compare ordered columns and their R storage types/classes, including join tags.
assert_same_schema <- function(current, previous, label) {
  column_types <- function(df) {
    vapply(df, function(x) paste(typeof(x), paste(class(x), collapse = "/")), "")
  }
  if (!identical(names(current), names(previous)) ||
      !identical(column_types(current), column_types(previous))) {
    stop(label, ": output column names, order, or types differ from the reference")
  }
  invisible(TRUE)
}

# Boundary IDs identify destination tracts receiving sources excluded by the old
# Southern California source filter. Differences there require analyst review.
# Optional expected_income is uniquely keyed by tr2010_id, with numeric
# legacy_med_hhincE, corrected_med_hhincE, legacy_med_hhincCV, and
# corrected_med_hhincCV columns computed from uncensored inputs/reference MOEs.
# Only income cells matching both expectations qualify for the correction.
# Optional schema_migration is "2016" or "2024" for the Step 2 migration only.
# Its fixed allowlist applies to additions/removals; shared columns stay strict.
compare_socal_parity <- function(current, previous, socal_counties,
                                 boundary_ids = character(), tolerance = 1e-10,
                                 expected_income = NULL, schema_migration = NULL) {
  if (is.null(previous)) {
    cat("PARITY NOT CHECKED: no prior output; supply parity_reference_dir.\n")
    return(invisible(NULL))
  }
  added <- setdiff(names(current), names(previous))
  removed <- setdiff(names(previous), names(current))
  schema_changes <- tibble(change = c(rep("added", length(added)), rep("removed", length(removed))),
                           variable = c(added, removed))
  if (is.null(schema_migration)) {
    assert_same_schema(current, previous, "Southern California parity")
  } else {
    if (!is.character(schema_migration) || length(schema_migration) != 1L ||
        is.na(schema_migration) || !schema_migration %in% c("2016", "2024")) {
      stop("schema_migration must be NULL, '2016', or '2024'")
    }
    removed_measures <- c("rentmv1yr", "rentmv5yr", "rentyrblt", "rentyrblt_14_16",
                          "rentyrblt_10_13", "rentyrblt_00_09", "rentyrblt_90_99")
    allowed_added <- c("rhu_inventoryE", if (schema_migration == "2016") c("vac_rentedE", "vac_rentedM"))
    allowed_removed <- if (schema_migration == "2016") {
      c(paste0(removed_measures, "E"), paste0(removed_measures, "M"))
    } else character()
    print(schema_changes, n = Inf)
    if (anyDuplicated(names(current)) || anyDuplicated(names(previous)) ||
        !all(added %in% allowed_added) || !all(removed %in% allowed_removed)) {
      stop("Southern California parity: unapproved schema additions/removals")
    }
    for (measure in removed_measures) {
      pair <- paste0(measure, c("E", "M"))
      if (any(pair %in% removed) && !all(pair %in% removed)) {
        stop("Southern California parity: schema removals must be estimate/MOE pairs")
      }
    }
    if (!all(vapply(current[added], is.numeric, logical(1)))) {
      stop("Southern California parity: added estimates/MOEs must be numeric")
    }
    assert_same_schema(current[, !names(current) %in% added, drop = FALSE],
                       previous[, !names(previous) %in% removed, drop = FALSE],
                       "Southern California parity shared columns")
  }
  shared_columns <- intersect(names(current), names(previous))
  assert_unique_key(previous, "tr2010_id", "Prior output")
  assert_unique_key(current, "tr2010_id", "Candidate output")
  income_columns <- c("med_hhincE", "med_hhincCV")
  if (!is.null(expected_income)) {
    expected_columns <- c(paste0("legacy_", income_columns),
                          paste0("corrected_", income_columns))
    if (!is.data.frame(expected_income) ||
        !all(c("tr2010_id", expected_columns) %in% names(expected_income)) ||
        anyDuplicated(names(expected_income)) ||
        !all(vapply(expected_income[expected_columns], is.numeric, logical(1)))) {
      stop("Income expectations require tr2010_id and numeric legacy/corrected income and CV columns")
    }
    assert_unique_key(expected_income, "tr2010_id", "Income expectations")
  }
  values_match <- function(old, new) {
    same <- (is.na(old) & is.na(new)) | (!is.na(old) & !is.na(new) & old == new)
    if (is.numeric(old)) {
      finite <- is.finite(old) & is.finite(new)
      same[finite] <- abs(old[finite] - new[finite]) <=
        tolerance * pmax(1, abs(old[finite]), abs(new[finite]))
    }
    same
  }
  select_socal <- function(df) {
    df |>
      filter(substr(tr2010_id, 1, 2) == "06",
             substr(tr2010_id, 3, 5) %in% socal_counties)
  }
  before <- select_socal(previous)
  after <- select_socal(current)
  ids <- union(before$tr2010_id, after$tr2010_id)
  tract_audit <- tibble(
    tr2010_id = ids,
    allocation = if_else(ids %in% boundary_ids, "boundary", "unaffected"),
    membership = case_when(
      ids %in% before$tr2010_id & ids %in% after$tr2010_id ~ "both",
      ids %in% before$tr2010_id ~ "prior_only",
      TRUE ~ "candidate_only"
    )
  )
  shared_ids <- tract_audit$tr2010_id[tract_audit$membership == "both"]
  before <- before[match(shared_ids, before$tr2010_id), , drop = FALSE]
  after <- after[match(shared_ids, after$tr2010_id), , drop = FALSE]
  expected_index <- match(shared_ids, expected_income$tr2010_id)
  differences <- lapply(setdiff(shared_columns, "tr2010_id"), function(column) {
    old <- before[[column]]
    new <- after[[column]]
    changed <- which(!values_match(old, new))
    verified_income <- rep(FALSE, length(changed))
    if (!is.null(expected_income) && column %in% income_columns) {
      expected_rows <- expected_index[changed]
      verified_income <- !is.na(expected_rows) &
        values_match(old[changed], expected_income[[paste0("legacy_", column)]][expected_rows]) &
        values_match(new[changed], expected_income[[paste0("corrected_", column)]][expected_rows])
    }
    tibble(
      tr2010_id = shared_ids[changed], variable = rep(column, length(changed)),
      prior = as.character(old[changed]), candidate = as.character(new[changed]),
      difference = if (is.numeric(old)) new[changed] - old[changed] else rep(NA_real_, length(changed)),
      classification = case_when(
        verified_income ~ "verified_income_correction",
        shared_ids[changed] %in% boundary_ids ~ "boundary_review",
        TRUE ~ "unexpected"
      )
    )
  }) |>
    bind_rows() |>
    left_join(select(tract_audit, tr2010_id, allocation), by = "tr2010_id")
  tract_audit <- tract_audit |>
    mutate(changed = membership != "both" | tr2010_id %in% differences$tr2010_id)
  summary <- tract_audit |>
    dplyr::count(allocation, membership, changed, name = "tracts")
  difference_summary <- differences |>
    dplyr::count(allocation, classification, variable, name = "cells")
  print(summary, n = Inf)
  print(difference_summary, n = Inf, width = Inf)
  print(filter(tract_audit, membership != "both"), n = Inf)
  print(differences, n = Inf, width = Inf)
  if (any(tract_audit$allocation == "unaffected" & tract_audit$membership != "both") ||
      any(differences$classification == "unexpected")) {
    stop("Southern California parity failed for unaffected tracts; inspect differences above")
  }
  invisible(list(summary = summary, tracts = tract_audit, differences = differences,
                 difference_summary = difference_summary, schema_changes = schema_changes))
}

# Reconstruct membership from the original input keys, even after base_id is TRUE.
audit_panel_keys <- function(df, keys_16, keys_24) {
  assert_tract_keys(df, union(keys_16, keys_24), "Full panel key union")
  audit <- tibble(
    tr2010_id = df$tr2010_id,
    in_16 = df$tr2010_id %in% keys_16,
    in_24 = df$tr2010_id %in% keys_24
  ) |>
    mutate(membership = case_when(
      in_16 & in_24 ~ "both", in_16 ~ "base", in_24 ~ "post"
    ))
  if ("merge" %in% names(df) && !identical(df$merge, audit$membership)) {
    stop("Panel merge indicators disagree with original input keys")
  }
  for (yr in c("16", "24")) {
    absent <- !audit[[paste0("in_", yr)]]
    measures <- df[absent, endsWith(names(df), paste0("_", yr)), drop = FALSE]
    if (!all(is.na(measures))) stop("Nonmissing measures for absent ", yr, " input keys")
  }
  change_columns <- grepl("POST$|POSTCV$|PPC$", names(df)) & !startsWith(names(df), "m_flag_")
  if (!all(is.na(df[!(audit$in_16 & audit$in_24), change_columns, drop = FALSE]))) {
    stop("Change measures must be missing for one-period-only tracts")
  }
  print(audit |>
          mutate(county = substr(tr2010_id, 3, 5)) |>
          dplyr::count(county, membership, name = "tracts"), n = Inf)
  print(filter(audit, membership != "both"), n = Inf)
  invisible(audit)
}
