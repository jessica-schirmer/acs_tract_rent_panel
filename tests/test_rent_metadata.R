# Rscript --vanilla tests/test_rent_metadata.R
# Synthetic classifications, source selection, inflation, and raw-evidence joins.
suppressPackageStartupMessages({ library(dplyr); library(tidyr); library(here) })
source(here::here("R", "rent_metadata.R"))
source(here::here("R", "assemble_helpers.R"))
source(here::here("R", "geography_qa.R"))
source(here::here("R", "merge_helpers.R"))
source(here::here("R", "merge_diagnostics.R"))
expect_error <- function(expr) stopifnot(inherits(tryCatch({ force(expr); NULL }, error = identity), "error"))

fixture <- function(n = 1L) {
  x <- tibble(tr2010_id = sprintf("06037%06d", seq_len(n)), rentE = 1800,
              rentM = 100, rhucashE = 20)
  for (column in paste0("grentcat", 1:24, "E")) x[[column]] <- 0
  x$grentcat20E <- 20
  x
}
x <- fixture(11)
x$rentE <- c(3501, 3500, NA, NA, 1800, 99, 3500, 1800, 3501, -666666666, 3500)
x$rentM[c(1, 3, 4, 5, 7)] <- NA_real_
x$grentcat20E[c(1, 4, 8, 11)] <- 0
x$grentcat24E[c(1, 4, 8, 11)] <- 20
x$lqcrentE <- 3500
x$med_hhincE <- 100000
native <- prepare_native_rent(x, "16", "tr2010_id")
stopifnot(identical(native$rent_status_16,
  c("top_coded", "observed", "unresolved", "unresolved", "observed", "unavailable_other",
    "unresolved", "unresolved", "unresolved", "unavailable_other", "unresolved")),
  is.na(native$rentE[1]), native$rent_censor_bound_16[1] == 3500,
  native$rentE[2] == 3500, native$tc_flag_rent_16[2] == 0,
  is.na(native$tc_flag_rent_16[3]), is.na(native$tc_flag_rent_16[4]),
  native$rentE[5] == 1800, is.na(native$rentM[5]),
  identical(native$tr2010_id, x$tr2010_id), identical(native$med_hhincE, x$med_hhincE),
  identical(censor_tc_vars(native)$rentE, native$rentE),
  all(is.na(censor_tc_vars(native)$lqcrentE)))

# Raw annotations establish unavailability even when B25063's median is bin 24.
raw <- retain_rent_evidence(x[c(3, 4), ], key = "tr2010_id")
raw$rent_source_e <- "-666666666"
raw$rent_source_ea <- "-"
raw$rent_source_m <- "-222222222"
raw$rent_source_ma <- "**"
raw$rent_evidence_available <- TRUE
stopifnot(all(prepare_native_rent(raw, "24", "tr2010_id")$rent_status_24 == "unavailable_other"))
raw$rent_source_ea[1] <- "3,500+"
raw$grentcat20E[1] <- 0
raw$grentcat24E[1] <- 20
annotated <- prepare_native_rent(raw, "24", "tr2010_id")
stopifnot(annotated$rent_status_24[1] == "top_coded", is.na(annotated$rentE[1]))
evidence <- raw |> transmute(GEOID = tr2010_id, across(all_of(rent_evidence_columns())))
normalized <- x[c(3, 4), ] |> mutate(rentM = NA_real_)
joined <- retain_rent_evidence(normalized, evidence[2:1, ], "tr2010_id")
stopifnot(identical(joined[names(normalized)], normalized), joined$rent_source_m[1] == "-222222222")
expect_error(retain_rent_evidence(normalized, evidence[1, ], "tr2010_id"))
expect_error(retain_rent_evidence(mutate(normalized, rentE = 1800), evidence, "tr2010_id"))

# Highest-bin mass/component medians never substitute for the final median bin.
dist <- fixture(8)
dist$grentcat20E <- c(9, 10, 11, 20, 20, 0, 0, 20)
dist$grentcat24E <- c(11, 10, 9, NA, 0, 0, 0, 0)
dist$rhucashE[c(6, 8)] <- c(0, 25)
dist$grentcat1E[7] <- 20
dist$rentE <- c(1800, 3501, 3501, rep(1800, 5))
agg <- calc_interp_rent(dist)
stopifnot(identical(agg$rent_status_24,
  c("top_coded", "observed", "observed", "unavailable_other", "observed",
    "unavailable_other", "unavailable_other", "unresolved")),
  agg$rent_median_bin[1] == 24L, agg$rent_median_bin[2] == 20L,
  agg$interp_rent[2] == 1999, agg$rent_censor_bound_24[1] == 3500,
  is.na(agg$tc_flag_rent_24[6]), is.na(agg$tc_flag_rent_24[8]),
  calc_interp_rent(dist[6, ], n_contributing = 0)$rent_status_24 == "unresolved")
expect_error(assert_rent_metadata(mutate(agg, tc_flag_rent_24 = 0), "interp_rent", "24"))
expect_error(assert_rent_metadata(mutate(agg, interp_rent = 3501), "interp_rent", "24"))
expect_error(assert_rent_metadata(mutate(agg, rent_censor_bound_24 = 3501), "interp_rent", "24"))

# Corrected component coverage preserves a real $3,500, independent of tract status.
bg <- fixture(2) |> mutate(bg2020_id = paste0(tr2010_id, "1"),
                           rentE = c(3500, 3501), lqcrentE = 1000)
bg$grentcat20E[2] <- 0
bg$grentcat24E[2] <- 20
coverage <- censor_bg_coverage_rent(bg)
stopifnot(coverage$rentE[1] == 3500, is.na(coverage$rentE[2]))

# Migration reconstructs the old component flag and coverage with unchanged
# allocation weights/denominator; only those verified cells may differ.
bg$tr2010_id <- bg$tr2010_id[1]
bg$rhuE <- c(100, 300)
bg$wt_renthu <- c(.5, .25)
allocated <- bg |> summarise(tr2010_id = first(tr2010_id),
  across(all_of(rent_count_columns()), ~ sum(.x * wt_renthu)))
bg_current <- calc_interp_rent(allocated) |> mutate(rhuE = 125, rhu_miss_rent = 75,
                                                    pct_miss_rent = 75 / 125)
bg_old <- bg_current |>
  select(-rent_status_24, -rent_censor_bound_24, -rent_median_bin, -rent_status_reason) |>
  mutate(tc_flag_rent_24 = 1, rhu_miss_rent = 125, pct_miss_rent = 1, pct_tc_rent = 1) |>
  relocate(tc_flag_rent_24, .before = interp_rent)
bg_expected <- bg_rent_parity_expectations(bg, bg_current)
invisible(capture.output(bg_migration <- compare_socal_parity(
  bg_current, bg_old, "037", schema_migration = "2024", expected_rent = bg_expected)))
stopifnot(nrow(bg_migration$differences) == 3L,
  all(bg_migration$differences$classification == "verified_rent_metadata_correction"))
invisible(capture.output(expect_error(compare_socal_parity(
  mutate(bg_current, pct_miss_rent = .5), bg_old, "037", schema_migration = "2024",
  expected_rent = bg_expected))))

# Bundles select status/flag/bound from the exact same source as rent, no fallback.
make_source <- function(bg = FALSE) {
  x <- tibble(tr2010_id = sprintf("06037%06d", 1:4))
  for (column in merge_measure_columns("bg_agg")) x[[column]] <- rep(10, 4)
  x[[if (bg) "interp_rent" else "rentE"]] <- if (bg) c(NA, 1500, 1600, NA) else c(1200, NA, NA, 1800)
  status <- if (bg) c("top_coded", "observed", "observed", "unavailable_other") else c("observed", "top_coded", "unresolved", "observed")
  x <- add_rent_metadata(x, status, "24")
  if (!bg) x <- x |> rename(tr2020_id = tr2010_id) |> mutate(m_flag_rhu = 0, zero_flag_rhu = 0)
  x
}
a <- prepare_2024_source(make_source(), "tract")
b <- prepare_2024_source(make_source(TRUE), "bg_agg")
panel <- bind_cols(tibble(tr2010_id = b$tr2010_id, geo_consistent = c(1, 0, 1, 0)),
                   select(a, -tr2020_id), select(b, -tr2010_id))
selected <- select_canonical_2024(panel)
stopifnot(identical(selected$interp_rent, c(1200, 1500, NA_real_, NA_real_)),
  identical(selected$rent_status_24, c("observed", "observed", "unresolved", "unavailable_other")),
  all(assert_hierarchical_2024(selected)$n_mismatch == 0))
selected_top <- select_canonical_2024(mutate(panel, geo_consistent = c(0, 1, 1, 0)))
stopifnot(all(selected_top$tc_flag_rent_24[1:2] == 1), all(is.na(selected_top$interp_rent[1:2])))
missing_source <- panel
missing_source[3, a |> select(-tr2020_id) |> names()] <- NA
missing_selected <- select_canonical_2024(missing_source)
stopifnot(missing_selected$rent_status_24[3] == "unresolved", is.na(missing_selected$interp_rent[3]))
assert_rent_metadata(missing_selected, "interp_rent", "24")

# Source-stage $3,500 bounds inflate once alongside rent using the existing factor.
base <- tibble(rentE_16 = c(NA_real_, 3500), rent_status_16 = c("top_coded", "observed"),
               tc_flag_rent_16 = c(1, 0), rent_censor_bound_16 = c(3500, NA_real_))
for (column in c("lqcrentE", "med_hhincE", "med_hvalE", "rentM", "lqcrentM", "med_hhincM", "med_hvalM")) {
  base[[paste0(column, "_16")]] <- c(100, 200)
}
inflated <- infl_adj_vars(base, "16")
stopifnot(identical(inflated[c("tc_flag_rent_16", "rent_status_16")], base[c("tc_flag_rent_16", "rent_status_16")]),
  inflated$rent_censor_bound_16[1] == 3500 * inflation_factor_2016(),
  inflated$rentE_16[2] == 3500 * inflation_factor_2016(),
  isTRUE(all.equal(inflated$rent_censor_bound_16[1], 4574.5)),
  identical(infl_adj_vars(base, "24"), base))
assert_rent_metadata(inflated, "rentE_16", "16", 3500 * inflation_factor_2016())

# Migration permits only source-verified changes, retaining all unrelated cells.
old <- x |>
  mutate(tc_flag_rent = if_else(rentE >= 3500, 1, 0),
         rentE = if_else(rentE >= 3500, NA_real_, rentE),
         m_flag_rent = as.double(is.na(rentE)), rentCV = (rentM / 1.645) / rentE)
current <- native |> mutate(rentCV = (rentM / 1.645) / rentE)
expected <- native_rent_parity_expectations(x, "16", "tr2010_id")
invisible(capture.output(migration <- compare_socal_parity(
  current, old, "037", schema_migration = "2016", expected_rent = expected)))
stopifnot(all(migration$differences$classification == "verified_rent_metadata_correction"))
invisible(capture.output(expect_error(compare_socal_parity(
  mutate(current, med_hhincE = med_hhincE + 1), old, "037",
  schema_migration = "2016", expected_rent = expected))))
invisible(capture.output(expect_error(compare_socal_parity(
  mutate(current, rentE = replace(rentE, 2, 3499)), old, "037",
  schema_migration = "2016", expected_rent = expected))))

empty <- calc_interp_rent(fixture()[FALSE, ])
stopifnot(nrow(empty) == 0L, is.double(empty$tc_flag_rent_24), is.double(empty$rent_censor_bound_24))

for (file in list.files(here::here("R"), pattern = "[.]R$", full.names = TRUE)) parse(file)
for (file in list.files(here::here(), pattern = "[.]Rmd$", full.names = TRUE)) {
  lines <- readLines(file)
  for (start in grep("^```\\{r", lines)) {
    end <- which(seq_along(lines) > start & lines == "```")[1]
    parse(text = lines[seq.int(start + 1L, end - 1L)])
  }
}
cat("Passed rent metadata, raw evidence, boundary/distribution, hierarchy, inflation, and syntax checks.\n")
