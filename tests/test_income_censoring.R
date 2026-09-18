# Run from the repository root: Rscript tests/test_income_censoring.R
# Synthetic checks only; no data files are read or written.
# Notebook code is read to exercise its income-expectation builders.
suppressPackageStartupMessages({
  library(dplyr)
  library(here)
  library(matrixStats)
  library(stringr)
})
source(here::here("R", "assemble_helpers.R"))
source(here::here("R", "geography_qa.R"))

# Frozen pre-correction helper for comparisons of unrelated columns.
censor_before_income_fix <- function(df) {
  df |>
    mutate(rentE = ifelse(rentE >= 3500, NA, rentE),
           lqcrentE = ifelse(lqcrentE >= 3500, NA, lqcrentE),
           med_hhincE = ifelse(rentE >= 2000000, NA, med_hhincE))
}

examples <- tibble(
  case = c("ordinary", "below_boundary", "at_boundary", "above_boundary",
           "missing_rent", "zero_rent", "missing_lqcrent", "topcoded_lqcrent",
           "missing_income", "large_income", "rent_at_2000000",
           "missing_both", "missing_income_topcoded_rent", "zero_income"),
  rentE = c(1800, 3499, 3500, 3501, NA, 0, 1800, 1800, 1800, 1800, 2000000,
            NA, 3500, NA),
  lqcrentE = c(1200, 1200, 1200, 1200, 1200, 0, NA, 3500, 1200, 1200, 1200,
               NA, 3501, 1200),
  med_hhincE = c(rep(80000, 8), NA, 2000000, 80000, NA, NA, 0)
) |>
  mutate(med_hvalE = rep(c(1999999, 2000000, 2000001, NA_real_), length.out = n()),
         rentM = 100, lqcrentM = 90, med_hhincM = 1000,
         rhuE = 100, rhucashE = 80) |>
  flag_tc_vars(c("rentE", "lqcrentE", "med_hvalE"))

corrected <- censor_tc_vars(examples)
previous <- censor_before_income_fix(examples)
other_columns <- setdiff(names(examples), "med_hhincE")
stopifnot(
  "Income must retain its source values and missingness" =
    identical(corrected$med_hhincE, examples$med_hhincE),
  "Rent censoring must retain the 3500 boundary" = identical(
    corrected$rentE,
    c(1800, 3499, NA, NA, NA, 0, 1800, 1800, 1800, 1800, NA, NA, NA, NA)),
  "Lower-quartile rent censoring must remain independent" = identical(
    corrected$lqcrentE,
    c(1200, 1200, 1200, 1200, 1200, 0, NA, NA, 1200, 1200, 1200, NA, NA, 1200)),
  "Helper column names and order must remain unchanged" =
    identical(names(corrected), names(previous)),
  "Every other column, type, and row order must match the previous helper" =
    identical(corrected[other_columns], previous[other_columns])
)

all_missing <- examples |> mutate(med_hhincE = NA_real_)
stopifnot("All-missing source income must retain its numeric type" = identical(
  censor_tc_vars(all_missing)$med_hhincE, all_missing$med_hhincE
))

# Small allocation fixture for the actual aggregation and CV helpers.
# IDs are descriptive synthetic groups, not empirical tract identifiers.
contributions <- tibble(
  tr2010_id = c(rep("mixed", 3), rep("rent_missing", 2),
                rep("income_missing", 2), rep("unaffected", 2)),
  rentE = c(1800, 3500, NA, NA, 3501, 1800, NA, 1800, 2000),
  lqcrentE = c(1200, 3500, NA, 1200, 1200, 1200, NA, 1200, 1500),
  med_hhincE = c(60000, 120000, 180000, 90000, 150000, NA, NA, 90000, 120000),
  hhE = c(100, 400, 200, 200, 400, 100, 200, 100, 200),
  wt_hh = c(1, 0.5, 0.5, 0.5, 0.5, 1, 0.5, 1, 0.5),
  wt_renthu = 0.5, wt_hu = 0.5, wt_pop = 0.5, med_hvalE = 800000
)
count_columns <- c(
  "huE", "rhuE", "rhu_baseE", "popE", "tot_vacE",
  "tot_vac_baseE", "pop_blkE", "pop_hspE", "pop_aaE", "pop_raceE", "pop_ethnE",
  "sfd_detE", "sfd_baseE", "mfE", "rhucashE", paste0("grentcat", 1:24, "E")
)
moe_columns <- c(
  "rentM", "lqcrentM", "med_hhincM", "med_hvalM", "rhuM", "rhu_baseM",
  "tot_vacM", "tot_vac_baseM", "pop_blkM", "pop_hspM", "pop_aaM",
  "pop_raceM", "sfd_detM", "sfd_baseM", "huM", "popM"
)
for (column in count_columns) contributions[[column]] <- 100
for (column in moe_columns) contributions[[column]] <- 10
contributions <- calc_rel_wt(contributions, tr2010_id)

corrected_tracts <- contributions |>
  censor_tc_vars() |>
  calc_agg_vars(tr2010_id) |>
  calc_pct_vars() |>
  calc_cv(source = "bg_agg") |>
  arrange(tr2010_id)
previous_tracts <- contributions |>
  censor_before_income_fix() |>
  calc_agg_vars(tr2010_id) |>
  calc_pct_vars() |>
  calc_cv(source = "bg_agg") |>
  arrange(tr2010_id)
assert_step2_cleanup(corrected_tracts, "2024")
stopifnot(all(c("med_hhincE", "med_hhincM", "med_hhincCV") %in% names(corrected_tracts)))
corrected_income <- setNames(corrected_tracts$med_hhincE, corrected_tracts$tr2010_id)
previous_income <- setNames(previous_tracts$med_hhincE, previous_tracts$tr2010_id)
other_tract_columns <- setdiff(names(previous_tracts), c("med_hhincE", "med_hhincCV"))
stopifnot(
  "Mixed-rent income must include all available household-weighted contributions" =
    corrected_income[["mixed"]] == 120000,
  "Mixed-rent fixture must expose the previous income loss" =
    previous_income[["mixed"]] == 60000,
  "Income must remain available when all rent is missing after censoring" =
    corrected_income[["rent_missing"]] == 130000 &&
      is.na(previous_income[["rent_missing"]]),
  "Missing source income must remain missing after aggregation" =
    is.na(corrected_income[["income_missing"]]),
  "Unaffected income must retain its weighted mean" =
    corrected_income[["unaffected"]] == 105000 &&
      corrected_income[["unaffected"]] == previous_income[["unaffected"]],
  "Aggregated column names and order must remain unchanged" =
    identical(names(corrected_tracts), names(previous_tracts)),
  "All other aggregated measures, MOEs, keys, types, and row counts must match" =
    identical(corrected_tracts[other_tract_columns], previous_tracts[other_tract_columns])
)

cat("Passed: 14 censoring cases, all-missing income, and four synthetic tract groups.\n")
cat("Unrelated columns match the previous helper before and after aggregation.\n")

# Exercise the actual notebook expectation chunks with synthetic inputs.
income_expectations <- function(vintage, sources, reference) {
  lines <- readLines(here::here(if (vintage == "24")
    "02a_aggregate_2024_block_groups.Rmd" else "02b_prepare_tract_sources.Rmd"))
  product <- if (vintage == "24") "2024_bg_aggregated" else "16"
  chunk_suffix <- if (vintage == "24") "2024-bg-aggregated" else "16"
  start <- match(paste0("```{r income-expectations-", chunk_suffix, "}"), lines)
  stopifnot(!is.na(start))
  end <- which(seq_along(lines) > start & lines == "```")[1]
  env <- new.env(parent = environment())
  env$prior_outputs <- setNames(list(reference), product)
  assign(if (vintage == "24") "acs_2024_bg_allocations" else "acs_16", sources, envir = env)
  assign(paste0("target_tract_ids_", product), unique(sources$tr2010_id), envir = env)
  invisible(capture.output(eval(parse(text = lines[seq.int(start + 1L, end - 1L)]), env)))
  get(paste0("expected_income_", product), envir = env)
}

parity <- function(current, previous = current, expected_income = NULL,
                   boundary_ids = character()) {
  invisible(capture.output(result <- compare_socal_parity(
    current, previous, "037", boundary_ids, expected_income = expected_income
  )))
  result
}

expect_parity_error <- function(expr, message = "Southern California parity failed") {
  error <- tryCatch({ force(expr); NULL }, error = identity)
  stopifnot("Expected parity error was not raised" = inherits(error, "error"))
  stopifnot("Unexpected error message" = grepl(message, conditionMessage(error), fixed = TRUE))
}

tract_sources <- examples |>
  mutate(tr2010_id = sprintf("06037%06d", seq_len(n())))
corrected_16 <- censor_tc_vars(tract_sources) |>
  mutate(med_hhincCV = (med_hhincM / 1.645) / med_hhincE)
legacy_16 <- censor_before_income_fix(tract_sources) |>
  mutate(med_hhincCV = (med_hhincM / 1.645) / med_hhincE)
expected_16 <- income_expectations("16", tract_sources, legacy_16)
stopifnot(
  "Identical outputs pass without expectations" = nrow(parity(legacy_16)$differences) == 0L,
  "Row order does not affect parity" =
    nrow(parity(legacy_16[nrow(legacy_16):1, ], legacy_16)$differences) == 0L,
  "2016 corrected expectations retain source income" =
    identical(expected_16$corrected_med_hhincE, tract_sources$med_hhincE),
  "2016 legacy expectations reproduce the frozen helper" =
    identical(expected_16$legacy_med_hhincE, legacy_16$med_hhincE)
)
expect_parity_error(parity(corrected_16, legacy_16))
audit_16 <- parity(corrected_16, legacy_16, expected_16[nrow(expected_16):1, ])
restored_ids <- tract_sources$tr2010_id[
  !is.na(corrected_16$med_hhincE) & is.na(legacy_16$med_hhincE)
]
stopifnot(
  "Every restored income and CV remains in the differences" =
    nrow(audit_16$differences) == 2L * length(restored_ids),
  "Income exceptions do not change geographic classification" =
    all(audit_16$differences$allocation == "unaffected"),
  "Every 2016 income difference is individually verified" =
    all(audit_16$differences$classification == "verified_income_correction"),
  "Verified tracts remain marked changed" =
    setequal(audit_16$tracts$tr2010_id[audit_16$tracts$changed], restored_ids),
  "The difference summary accounts for every changed cell" =
    sum(audit_16$difference_summary$cells) == nrow(audit_16$differences)
)

# Map the allocation fixtures to synthetic Southern California IDs.
fixture_ids <- setNames(sprintf("06037%06d", seq_along(corrected_income)), names(corrected_income))
to_tract_ids <- function(df) {
  df |> mutate(tr2010_id = unname(fixture_ids[tr2010_id]))
}
corrected_24 <- to_tract_ids(corrected_tracts)
legacy_24 <- to_tract_ids(previous_tracts)
expected_24 <- income_expectations("24", to_tract_ids(contributions), legacy_24)
audit_24 <- parity(corrected_24, legacy_24, expected_24)
stopifnot(
  "Weighted income and CV changes pass and remain visible" =
    nrow(audit_24$differences) == 4L &&
      all(audit_24$differences$classification == "verified_income_correction"),
  "Both vintage builders return no expectations without a reference" =
    is.null(income_expectations("16", tract_sources, NULL)) &&
      is.null(income_expectations("24", to_tract_ids(contributions), NULL))
)
expect_parity_error(parity(corrected_24, legacy_24))

# Wrong values on either side cannot use the income exception.
for (column in c("med_hhincE", "med_hhincCV")) {
  wrong_candidate <- corrected_24
  mixed <- match(fixture_ids[["mixed"]], wrong_candidate$tr2010_id)
  wrong_candidate[[column]][mixed] <- wrong_candidate[[column]][mixed] + 1
  expect_parity_error(parity(wrong_candidate, legacy_24, expected_24))
  wrong_reference <- legacy_24
  wrong_reference[[column]][mixed] <- wrong_reference[[column]][mixed] + 1
  expect_parity_error(parity(corrected_24, wrong_reference, expected_24))

  wrong_candidate[[column]][mixed] <- NA_real_
  expect_parity_error(parity(wrong_candidate, legacy_24, expected_24))
  wrong_reference[[column]][mixed] <- NA_real_
  expect_parity_error(parity(corrected_24, wrong_reference, expected_24))
}
wrong_restoration <- corrected_16 |>
  mutate(med_hhincE = if_else(tr2010_id %in% restored_ids, med_hhincE + 1, med_hhincE),
         med_hhincCV = (med_hhincM / 1.645) / med_hhincE)
expect_parity_error(parity(wrong_restoration, legacy_16, expected_16))
wrong_missing_income <- corrected_16
missing_row <- match("missing_income", wrong_missing_income$case)
wrong_missing_income$med_hhincE[missing_row] <- 80000
expect_parity_error(parity(wrong_missing_income, legacy_16, expected_16))

# Candidate MOEs must match the reference even if income/CVs are otherwise valid.
for (column in c("rentE", "rentM", "rhuE", "med_hhincM", "med_hvalE", "tc_flag_rent")) {
  unrelated <- corrected_16
  unrelated[[column]][1] <- unrelated[[column]][1] + 1
  expect_parity_error(parity(unrelated, legacy_16, expected_16))
}
wrong_moe <- corrected_24 |>
  mutate(med_hhincM = med_hhincM + 1,
         med_hhincCV = (med_hhincM / 1.645) / med_hhincE)
expect_parity_error(parity(wrong_moe, legacy_24, expected_24))
wrong_tag <- corrected_16 |> mutate(case = "changed label")
expect_parity_error(parity(wrong_tag, legacy_16, expected_16))

# Schema, key, and membership checks remain active even for approved corrections.
expect_parity_error(parity(select(corrected_16, -rentE), legacy_16, expected_16),
                    "output column names, order, or types differ")
expect_parity_error(parity(mutate(corrected_16, extra = 1), legacy_16, expected_16),
                    "output column names, order, or types differ")
expect_parity_error(parity(select(corrected_16, tr2010_id, everything()), legacy_16, expected_16),
                    "output column names, order, or types differ")
expect_parity_error(parity(mutate(corrected_16, rhuE = as.integer(rhuE)), legacy_16, expected_16),
                    "output column names, order, or types differ")
expect_parity_error(parity(bind_rows(corrected_16, corrected_16[1, ]), legacy_16, expected_16),
                    "missing or duplicate key")
expect_parity_error(parity(corrected_16, bind_rows(legacy_16, legacy_16[1, ]), expected_16),
                    "missing or duplicate key")
missing_key <- corrected_16
missing_key$tr2010_id[1] <- NA_character_
expect_parity_error(parity(missing_key, legacy_16, expected_16), "missing or duplicate key")
expect_parity_error(parity(corrected_16[-1, ], legacy_16, expected_16))
expect_parity_error(parity(corrected_16, legacy_16[-1, ], expected_16))
changed_key <- corrected_16
changed_key$tr2010_id[1] <- "06037999999"
expect_parity_error(parity(changed_key, legacy_16, expected_16))

# Expectations are keyed; absent or invalid expectations never authorize a change.
expect_parity_error(parity(corrected_16, legacy_16, expected_16[0, ]))
expect_parity_error(parity(corrected_16, legacy_16,
                          filter(expected_16, !tr2010_id %in% restored_ids)))
expect_parity_error(parity(corrected_16, legacy_16, bind_rows(expected_16, expected_16[1, ])),
                    "missing or duplicate key")
bad_expected_key <- expected_16
bad_expected_key$tr2010_id[1] <- NA_character_
expect_parity_error(parity(corrected_16, legacy_16, bad_expected_key), "missing or duplicate key")
expect_parity_error(parity(corrected_16, legacy_16, select(expected_16, -legacy_med_hhincCV)),
                    "Income expectations require")
expect_parity_error(parity(corrected_16, legacy_16,
                          mutate(expected_16, corrected_med_hhincE = as.character(corrected_med_hhincE))),
                    "Income expectations require")

# The same tolerance applies to ordinary parity and both sides of an exception.
close_candidate <- corrected_24 |>
  mutate(rhuE = rhuE * (1 + 5e-11),
         med_hhincE = med_hhincE * (1 + 5e-11),
         med_hhincCV = med_hhincCV + 5e-11)
close_reference <- legacy_24 |>
  mutate(med_hhincE = med_hhincE * (1 + 5e-11),
         med_hhincCV = med_hhincCV + 5e-11)
stopifnot(
  "Ordinary finite changes within tolerance pass strictly" =
    nrow(parity(mutate(legacy_24, rhuE = rhuE * (1 + 5e-11)), legacy_24)$differences) == 0L,
  "Expected values within tolerance verify on both sides" =
    nrow(parity(close_candidate, close_reference, expected_24)$differences) == 4L
)
expect_parity_error(parity(mutate(corrected_24, rhuE = rhuE * (1 + 2e-10)), legacy_24, expected_24))
for (column in c("med_hhincE", "med_hhincCV")) {
  too_far <- corrected_24
  too_far[[column]][mixed] <- too_far[[column]][mixed] +
    2e-10 * max(1, abs(too_far[[column]][mixed]))
  expect_parity_error(parity(too_far, legacy_24, expected_24))
}

# Missing values (NA/NaN) and signed infinities retain the existing comparison.
zero_row <- match("zero_income", corrected_16$case)
stopifnot("Restored zero income has an infinite CV" =
            corrected_16$med_hhincE[zero_row] == 0 && corrected_16$med_hhincCV[zero_row] == Inf)
nan_candidate <- corrected_16 |>
  mutate(med_hhincE = replace(med_hhincE, is.na(med_hhincE), NaN),
         med_hhincCV = replace(med_hhincCV, is.na(med_hhincCV), NaN))
stopifnot(nrow(parity(nan_candidate, legacy_16, expected_16)$differences) == nrow(audit_16$differences))
wrong_infinite_cv <- corrected_16
wrong_infinite_cv$med_hhincCV[zero_row] <- -Inf
expect_parity_error(parity(wrong_infinite_cv, legacy_16, expected_16))
zero_moe_sources <- tract_sources
zero_moe_sources$med_hhincM[zero_row] <- 0
zero_moe_legacy <- censor_before_income_fix(zero_moe_sources) |>
  mutate(med_hhincCV = (med_hhincM / 1.645) / med_hhincE)
zero_moe_corrected <- censor_tc_vars(zero_moe_sources) |>
  mutate(med_hhincCV = (med_hhincM / 1.645) / med_hhincE)
zero_moe_expected <- income_expectations("16", zero_moe_sources, zero_moe_legacy)
stopifnot(is.nan(zero_moe_corrected$med_hhincCV[zero_row]))
parity(zero_moe_corrected, zero_moe_legacy, zero_moe_expected) |> invisible()

# Boundary differences still require review, including added/removed boundary keys.
boundary_id <- legacy_16$tr2010_id[1]
boundary_candidate <- legacy_16
boundary_candidate$rentE[1] <- boundary_candidate$rentE[1] + 1
boundary_audit <- parity(boundary_candidate, legacy_16, boundary_ids = boundary_id)
stopifnot(nrow(boundary_audit$differences) == 1L,
          boundary_audit$differences$classification == "boundary_review",
          boundary_audit$differences$allocation == "boundary")
combined_candidate <- corrected_16
combined_candidate$rentE[1] <- combined_candidate$rentE[1] + 1
combined_audit <- parity(combined_candidate, legacy_16, expected_16, boundary_id)
stopifnot(setequal(combined_audit$differences$classification,
                   c("boundary_review", "verified_income_correction")))
expect_parity_error(parity(combined_candidate, legacy_16, boundary_ids = boundary_id))
removed_boundary <- parity(legacy_16[-1, ], legacy_16, boundary_ids = boundary_id)
added_boundary <- parity(legacy_16, legacy_16[-1, ], boundary_ids = boundary_id)
stopifnot(removed_boundary$tracts$membership[removed_boundary$tracts$tr2010_id == boundary_id] == "prior_only",
          added_boundary$tracts$membership[added_boundary$tracts$tr2010_id == boundary_id] == "candidate_only")

# A missing reference is explicitly unchecked, with or without expectations.
for (expected in list(NULL, expected_16)) {
  output <- capture.output(unchecked <- compare_socal_parity(
    corrected_16, NULL, "037", expected_income = expected
  ))
  stopifnot(is.null(unchecked), any(grepl("PARITY NOT CHECKED", output, fixed = TRUE)))
}
cat("Passed: notebook income expectations and strict/approved/boundary parity checks.\n")
