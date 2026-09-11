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
compare_socal_parity <- function(current, previous, socal_counties,
                                 boundary_ids = character(), tolerance = 1e-10) {
  if (is.null(previous)) {
    cat("PARITY NOT CHECKED: no prior output; supply parity_reference_dir.\n")
    return(invisible(NULL))
  }
  assert_same_schema(current, previous, "Southern California parity")
  assert_unique_key(previous, "tr2010_id", "Prior output")
  assert_unique_key(current, "tr2010_id", "Candidate output")
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
  differences <- lapply(setdiff(names(after), "tr2010_id"), function(column) {
    old <- before[[column]]
    new <- after[[column]]
    same <- (is.na(old) & is.na(new)) | (!is.na(old) & !is.na(new) & old == new)
    if (is.numeric(old)) {
      finite <- is.finite(old) & is.finite(new)
      same[finite] <- abs(old[finite] - new[finite]) <=
        tolerance * pmax(1, abs(old[finite]), abs(new[finite]))
    }
    changed <- which(!same)
    tibble(
      tr2010_id = shared_ids[changed], variable = rep(column, length(changed)),
      prior = as.character(old[changed]), candidate = as.character(new[changed]),
      difference = if (is.numeric(old)) new[changed] - old[changed] else rep(NA_real_, length(changed))
    )
  }) |>
    bind_rows() |>
    left_join(select(tract_audit, tr2010_id, allocation), by = "tr2010_id")
  tract_audit <- tract_audit |>
    mutate(changed = membership != "both" | tr2010_id %in% differences$tr2010_id)
  summary <- tract_audit |>
    dplyr::count(allocation, membership, changed, name = "tracts")
  print(summary, n = Inf)
  print(filter(tract_audit, membership != "both"), n = Inf)
  print(differences, n = Inf, width = Inf)
  if (any(tract_audit$allocation == "unaffected" & tract_audit$changed)) {
    stop("Southern California parity failed for unaffected tracts; inspect differences above")
  }
  invisible(list(summary = summary, tracts = tract_audit, differences = differences))
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
