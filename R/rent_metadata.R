# Rent evidence and classification, in source-year dollars until Step 4.
# Uses existing dplyr/tibble and tidycensus dependencies httr/jsonlite.

rent_evidence_columns <- function() {
  c("rent_source_e", "rent_source_ea", "rent_source_m", "rent_source_ma",
    "rent_evidence_available")
}

rent_metadata_columns <- function(year) {
  paste0(c("tc_flag_rent_", "rent_status_", "rent_censor_bound_"), year)
}

# Raw character values preserve negative sentinels and annotations before
# tidycensus normalization. Never include the API key in errors or saved URLs.
fetch_rent_evidence <- function(year, county = "*", tract = "*",
                                key = Sys.getenv("CENSUS_API_KEY"), geography = "tract") {
  stopifnot(year %in% c(2016, 2024), length(year) == 1L)
  stopifnot(geography %in% c("tract", "block group"))
  if (!nzchar(key)) stop("Rent evidence retrieval requires CENSUS_API_KEY")
  response <- tryCatch(httr::GET(
    paste0("https://api.census.gov/data/", year, "/acs/acs5"),
    query = list(get = "B25064_001E,B25064_001EA,B25064_001M,B25064_001MA",
                 `for` = if (geography == "tract") paste0("tract:", paste(tract, collapse = ",")) else "block group:*",
                 `in` = paste0("state:06 county:", county,
                                if (geography == "block group") paste0(" tract:", paste(tract, collapse = ","))), key = key),
    httr::timeout(60)
  ), error = function(e) stop("Rent evidence request failed (transport error)", call. = FALSE))
  if (httr::status_code(response) != 200L) stop("Rent evidence request failed (HTTP ", httr::status_code(response), ")")
  body <- httr::content(response, as = "text", encoding = "UTF-8")
  raw <- tryCatch(jsonlite::fromJSON(body), error = function(e) NULL)
  required <- c("B25064_001E", "B25064_001EA", "B25064_001M", "B25064_001MA", "state", "county", "tract")
  if (geography == "block group") required <- c(required, "block group")
  if (!is.matrix(raw) || nrow(raw) < 2L || !all(required %in% raw[1, ])) {
    stop("Rent evidence response is not an ACS data table; check API credentials")
  }
  values <- as.data.frame(raw[-1, , drop = FALSE], stringsAsFactors = FALSE)
  names(values) <- raw[1, ]
  tibble::tibble(
    GEOID = paste0(values$state, values$county, values$tract,
                   if (geography == "block group") values[["block group"]] else ""),
    rent_source_e = values$B25064_001E, rent_source_ea = values$B25064_001EA,
    rent_source_m = values$B25064_001M, rent_source_ma = values$B25064_001MA,
    rent_evidence_available = TRUE
  )
}

retain_rent_evidence <- function(df, evidence = NULL, key = "GEOID") {
  if (!all(c(key, "rentE", "rentM") %in% names(df))) stop("Rent evidence requires source keys and E/M")
  if (is.null(evidence)) {
    df$rent_source_e <- as.character(df$rentE)
    df$rent_source_ea <- NA_character_
    df$rent_source_m <- as.character(df$rentM)
    df$rent_source_ma <- NA_character_
    df$rent_evidence_available <- FALSE
    return(df)
  }
  if (anyNA(df[[key]]) || anyDuplicated(df[[key]]) ||
      !all(c("GEOID", rent_evidence_columns()) %in% names(evidence)) ||
      anyNA(evidence$GEOID) || anyDuplicated(evidence$GEOID) ||
      !setequal(df[[key]], evidence$GEOID)) stop("Rent evidence keys must exactly match the source extract")
  evidence <- evidence[match(df[[key]], evidence$GEOID), ]
  normalized <- function(x) {
    x <- suppressWarnings(as.double(x))
    x[x %in% (-111111111 * 1:9)] <- NA_real_
    x
  }
  for (pair in list(c("rentE", "rent_source_e"), c("rentM", "rent_source_m"))) {
    x <- df[[pair[1]]]
    y <- normalized(evidence[[pair[2]]])
    if (!all((is.na(x) & is.na(y)) | (!is.na(x) & !is.na(y) & x == y))) {
      stop("Raw B25064 evidence disagrees with the same-vintage E/M extract")
    }
  }
  for (column in rent_evidence_columns()) df[[column]] <- evidence[[column]]
  df
}

# The analyst-run extract can retain normalized E/M when annotations cannot be
# retrieved; FALSE records that loss explicitly, and classification stays cautious.
download_rent_evidence <- function(df, year, geography = "tract") {
  evidence <- tryCatch(fetch_rent_evidence(year, geography = geography), error = function(e) {
    cat("REVIEW:", conditionMessage(e), "; retaining normalized E/M without annotations\n")
    NULL
  })
  retain_rent_evidence(df, evidence)
}

rent_count_columns <- function() c("rhucashE", paste0("grentcat", 1:24, "E"))

# One calculation supplies the numeric estimate, median bin, and classification.
# Reconciliation tolerance never changes the exact >= half median threshold.
rent_distribution <- function(df, n_contributing = rep(1L, nrow(df))) {
  required <- rent_count_columns()
  missing <- setdiff(required, names(df))
  if (length(missing)) stop("Rent distribution requires: ", paste(missing, collapse = ", "))
  stopifnot(all(vapply(df[required], is.numeric, logical(1))), length(n_contributing) == nrow(df))
  bins <- as.matrix(df[paste0("grentcat", 1:24, "E")])
  cash <- df$rhucashE
  out <- tibble::tibble(rent = rep(NA_real_, nrow(df)),
    rent_median_bin = rep(NA_integer_, nrow(df)),
    rent_status = rep("unresolved", nrow(df)),
    rent_status_reason = rep("invalid_distribution", nrow(df)))
  lower <- c(0, 100, 150, 200, 250, 300, 350, 400, 450, 500, 550, 600,
             650, 700, 750, 800, 900, 1000, 1250, 1500, 2000, 2500, 3000, 3500)
  upper <- c(99, 149, 199, 249, 299, 349, 399, 449, 499, 549, 599, 649,
             699, 749, 799, 899, 999, 1249, 1499, 1999, 2499, 2999, 3499, NA)
  for (i in seq_len(nrow(df))) {
    if (is.na(n_contributing[i]) || n_contributing[i] <= 0) {
      out$rent_status_reason[i] <- "no_positive_weight_sources"
      next
    }
    counts <- c(cash[i], bins[i, ])
    if (anyNA(counts)) {
      out$rent_status[i] <- "unavailable_other"
      out$rent_status_reason[i] <- "incomplete_distribution"
      next
    }
    if (any(!is.finite(counts) | counts < 0)) next
    if (abs(sum(bins[i, ]) - cash[i]) > 1e-6) {
      out$rent_status_reason[i] <- "cash_bin_total_conflict"
      next
    }
    if (cash[i] == 0) {
      out$rent_status[i] <- "unavailable_other"
      out$rent_status_reason[i] <- "zero_cash_rent_units"
      next
    }
    cumulative <- cumsum(bins[i, ])
    k <- which(cumulative >= cash[i] / 2)[1]
    if (is.na(k)) next
    out$rent_median_bin[i] <- k
    out$rent_status[i] <- if (k == 24L) "top_coded" else if (k == 1L) "unavailable_other" else "observed"
    out$rent_status_reason[i] <- if (k == 24L) "median_in_open_top_bin" else if (k == 1L)
      "median_in_excluded_bottom_bin" else "interior_distribution_median"
    if (k > 1L && k < 24L) {
      out$rent[i] <- lower[k] + (upper[k] - lower[k]) *
        (cash[i] / 2 - cumulative[k - 1L]) / bins[i, k]
    }
  }
  out
}

add_rent_metadata <- function(df, status, year) {
  df[[paste0("tc_flag_rent_", year)]] <- dplyr::case_when(
    status == "top_coded" ~ 1, status == "observed" ~ 0, .default = NA_real_)
  df[[paste0("rent_status_", year)]] <- status
  df[[paste0("rent_censor_bound_", year)]] <- dplyr::if_else(status == "top_coded", 3500, NA_real_)
  df
}

prepare_native_rent <- function(df, year, key) {
  stopifnot(year %in% c("16", "24"))
  present <- rent_evidence_columns() %in% names(df)
  if (any(present) && !all(present)) stop("Incomplete retained B25064 evidence columns")
  if (!any(present)) df <- retain_rent_evidence(df, key = key)
  if (!is.logical(df$rent_evidence_available) || anyNA(df$rent_evidence_available) ||
      !all(vapply(df[setdiff(rent_evidence_columns(), "rent_evidence_available")], is.character, logical(1)))) {
    stop("Invalid retained B25064 evidence types")
  }
  dist <- rent_distribution(df)
  raw <- suppressWarnings(as.double(df$rent_source_e))
  moe <- suppressWarnings(as.double(df$rent_source_m))
  ea <- trimws(df$rent_source_ea)
  available <- df$rent_evidence_available %in% TRUE
  upper_annotation <- available & ea %in% c("3,500+", "3500+")
  unavailable_code <- raw %in% c(-666666666, -999999999, -888888888)
  unavailable_annotation <- available & ea %in% c("-", "N", "(X)")
  upper <- raw %in% 3501 | upper_annotation
  observed <- is.finite(raw) & raw >= 100 & raw < 3500
  boundary <- raw %in% 3500 & is.finite(moe) & moe >= 0 & dist$rent_status == "observed"
  status <- rep("unresolved", nrow(df))
  reason <- rep("insufficient_native_evidence", nrow(df))
  status[observed | boundary] <- "observed"
  reason[observed] <- "native_numeric_estimate"
  reason[boundary] <- "native_3500_finite_moe_and_non_top_distribution"
  status[upper] <- "top_coded"
  reason[upper] <- "native_upper_code_or_annotation"
  known_missing <- (unavailable_code | unavailable_annotation) & !upper_annotation
  status[known_missing] <- "unavailable_other"
  reason[known_missing] <- "native_source_unavailable"
  bottom <- raw %in% 99 | (available & ea %in% c("100-", "99-"))
  status[bottom] <- "unavailable_other"
  reason[bottom] <- "native_lower_interval_not_exact"
  conflict <- (upper & (unavailable_annotation | dist$rent_status == "observed")) |
    ((observed | boundary) & (unavailable_annotation | dist$rent_status == "top_coded")) |
    (upper_annotation & is.finite(raw) & raw >= 0 & raw != 3501) |
    (bottom & upper)
  status[conflict] <- "unresolved"
  reason[conflict] <- "native_evidence_conflict"
  df$rentE <- dplyr::if_else(status == "observed", raw, NA_real_)
  df$rent_status_reason <- reason
  df$rent_median_bin <- dist$rent_median_bin
  df <- add_rent_metadata(df, status, year)
  assert_rent_metadata(df, "rentE", year)
  df
}

assert_rent_metadata <- function(df, rent_column, year, bound = 3500) {
  required <- c(rent_column, rent_metadata_columns(year))
  if (!all(required %in% names(df))) stop("Missing rent metadata: ", paste(setdiff(required, names(df)), collapse = ", "))
  status <- df[[paste0("rent_status_", year)]]
  flag <- df[[paste0("tc_flag_rent_", year)]]
  censor <- df[[paste0("rent_censor_bound_", year)]]
  rent <- df[[rent_column]]
  if (!is.character(status) || anyNA(status) ||
      !all(status %in% c("observed", "top_coded", "unavailable_other", "unresolved")) ||
      !is.double(flag) || !is.double(censor) || !is.numeric(rent)) stop("Invalid rent metadata types/status")
  observed <- status == "observed"
  top <- status == "top_coded"
  if (!all(is.finite(rent[observed]) & rent[observed] >= 0 & rent[observed] <= bound) ||
      !all(is.na(rent[!observed])) || anyNA(flag[observed | top]) ||
      !all(flag[observed] == 0) || !all(flag[top] == 1) || !all(is.na(flag[!observed & !top])) ||
      anyNA(censor[top]) || !all(censor[top] == bound) || !all(is.na(censor[!top]))) {
    stop("Invalid rent status/flag/bound/value combination")
  }
  invisible(TRUE)
}

# Narrow migration evidence: only shared native rent/CV cells may change.
native_rent_parity_expectations <- function(source, year, key) {
  corrected <- prepare_native_rent(source, year, key)
  legacy <- ifelse(source$rentE >= 3500, NA_real_, source$rentE)
  dplyr::bind_rows(
    tibble::tibble(!!key := source[[key]], variable = "rentE", legacy = legacy, corrected = corrected$rentE),
    tibble::tibble(!!key := source[[key]], variable = "rentCV",
                  legacy = (source$rentM / 1.645) / legacy,
                  corrected = (source$rentM / 1.645) / corrected$rentE)
  )
}

# Frozen old-flag reconstruction solely for comparison with preserved snapshots.
# No component-exposure share is produced or used in current classification.
bg_rent_parity_expectations <- function(source, corrected) {
  corrected_source <- censor_bg_coverage_rent(source)
  legacy <- source |>
    dplyr::group_by(tr2010_id) |>
    dplyr::summarise(
      complete = !any(is.na(rhuE[wt_renthu > 0])),
      legacy = if (!complete) NA_real_ else as.double(any(
        wt_renthu > 0 & !is.na(rentE) & rentE >= 3500 & rhuE > 0)),
      .groups = "drop")
  flags <- tibble::tibble(tr2010_id = corrected$tr2010_id, variable = "tc_flag_rent_24",
    legacy = legacy$legacy[match(corrected$tr2010_id, legacy$tr2010_id)],
    corrected = corrected$tc_flag_rent_24)
  coverage <- function(df, old) {
    df |> dplyr::group_by(tr2010_id) |>
      dplyr::summarise(
        rhu_miss_rent = strict_weighted_sum(dplyr::if_else(
          is.na(rentE) | (old & rentE >= 3500), rhuE, 0), wt_renthu),
        total = strict_weighted_sum(rhuE, wt_renthu), .groups = "drop") |>
      dplyr::mutate(pct_miss_rent = dplyr::if_else(total > 0, rhu_miss_rent / total, NA_real_)) |>
      dplyr::select(-total) |>
      tidyr::pivot_longer(-tr2010_id, names_to = "variable", values_to = "value")
  }
  changes <- dplyr::inner_join(
    dplyr::rename(coverage(source, TRUE), legacy = value),
    dplyr::rename(coverage(corrected_source, FALSE), corrected = value),
    by = c("tr2010_id", "variable"), relationship = "one-to-one")
  dplyr::bind_rows(flags, changes)
}
