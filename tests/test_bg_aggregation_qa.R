# Rscript --vanilla tests/test_bg_aggregation_qa.R
# Synthetic helper tests and selected 02a chunks; all Feather I/O is temporary.
source(here::here("tests", "test_rental_inventory_bg.R"))

stopifnot(identical(strict_weighted_sum(c(0, 4), c(1, 0.25)), 1),
          identical(strict_weighted_sum(numeric(), numeric()), 0),
          identical(strict_weighted_sum(c(NA_real_, NaN), c(0, 0)), 0),
          identical(strict_weighted_sum(c(2, NA_real_), c(1, 1e-30)), NA_real_),
          identical(strict_weighted_sum(c(2, NaN), c(1, 0.5)), NA_real_))

# Exact complete-fixture totals, including all rent bins and supplemental counts.
complete <- with_24$acs_2024_bg_aggregated_interp
expected <- list(popE = c(100, 50), hhE = c(100, 50), huE = c(160, 20),
                 rhuE = c(41.2, 75), mf5E = c(640, 80), smfE = c(480, 60),
                 vac_forrentE = c(9.6, 2), rhu_miss_rent = c(25, 75))
for (column in names(expected)) stopifnot(isTRUE(all.equal(complete[[column]], expected[[column]])))
for (column in paste0("grentcat", 1:24, "E")) {
  stopifnot(identical(complete[[column]], c((100 / 24) * 0.25 + (100 / 24) * 0.4, (100 / 24) * 0.75)))
}
stopifnot(all(with_24$bg_count_qa_2024$measure$complete),
          all(vapply(complete[names(expected)], typeof, "") == "double"))

assemble_allocations <- function(allocations) {
  env <- new.env(parent = environment())
  env$acs_2024_bg_allocations <- allocations
  env$bg_reference_2024 <- new_bg_aggregation_reference(allocations)
  env$target_tract_ids_2024_bg_aggregated <- env$bg_reference_2024$targets
  for (chunk in c("relative-weights-and-tc-2024-bg-aggregated",
                  "censor-and-structure-2024-bg-aggregated", "aggregate-to-tracts-2024-bg-aggregated",
                  "aggregate-supplemental-2024-bg-aggregated", "rental-inventory-2024-bg-aggregated",
                  "derive-measures-2024-bg-aggregated", "merge-flags-2024-bg-aggregated")) {
    run_chunk(chunk, env, bg_notebook)
  }
  env
}

# Positive weights define membership, independently for each family. The third
# row is an absent ACS source with four zero weights and is the only link to t2.
probe <- assembly_sources[c(1, 3, 1), ] |>
  mutate(bg2020_id = source_ids, tr2010_id = tract_ids[c(1, 1, 2)],
         wt_pop = c(1, 1e-30, 0), wt_hh = c(1, 0, 0),
         wt_hu = c(0, 1, 0), wt_renthu = c(1, 0, 0), .acs_present = c(TRUE, TRUE, FALSE),
         popE = c(100, NA_real_, NA_real_), hhE = c(100, NaN, NA_real_),
         huE = c(NaN, 0, NA_real_), rhuE = c(NA_real_, 40, NA_real_),
         rentE = c(1800, 3500, NA_real_),
         mf_10_19E = c(100, NA_real_, NA_real_), sfd_attE = c(100, NaN, NA_real_))
probe[3, setdiff(names(probe), c("bg2020_id", "tr2010_id", bg_weight_columns(), ".acs_present"))] <- NA_real_
mixed <- assemble_allocations(probe)
result <- mixed$acs_2024_bg_aggregated_interp
qa <- mixed$bg_count_qa_2024
stopifnot(is.na(result$popE[1]), result$hhE[1] == 100, result$huE[1] == 0,
          is.na(result$rhuE[1]), result$rhu_miss_rent[1] == 0,
          is.na(result$mf5E[1]), is.na(result$smfE[1]),
          all(qa$measure$zero_contributors[qa$measure$tr2010_id == tract_ids[2]]),
          all(qa$measure$expected_total[qa$measure$tr2010_id == tract_ids[2]] == 0),
          all(qa$measure$complete[qa$measure$tr2010_id == tract_ids[2]]),
          nrow(qa$zero_weight_unmatched) == 1L,
          mixed$inventory_2024_bg_aggregated$rhu_inventoryE[2] == 0,
          mixed$inventory_2024_bg_aggregated$n_contributing[2] == 0L)
present_but_missing <- probe |> mutate(.acs_present = TRUE)
stopifnot(is.na(assemble_allocations(present_but_missing)$acs_2024_bg_aggregated$rhuE[1]))
one_family <- probe[1, ] |> mutate(wt_hh = 0, wt_renthu = 0)
one_family_result <- assemble_allocations(one_family)
stopifnot(one_family_result$acs_2024_bg_aggregated$popE == 100,
          one_family_result$acs_2024_bg_aggregated$hhE == 0,
          one_family_result$acs_2024_bg_aggregated$rhuE == 0,
          one_family_result$inventory_2024_bg_aggregated$rhu_inventoryE == 0)
for (missing in c(NA_real_, NaN)) {
  conditional <- probe
  conditional$rhuE[1] <- missing
  conditional$rentE[1] <- 3500
  censored <- assemble_allocations(conditional)
  stopifnot(identical(censored$acs_2024_bg_aggregated$rhu_miss_rent[1], NA_real_),
            is.na(censored$acs_2024_bg_allocations$rentE[1]))
}

# Every ordinary/supplemental count uses its declared family, not a blanket flag.
for (i in seq_len(nrow(bg_count_measure_map()))) {
  spec <- bg_count_measure_map()[i, ]
  frame <- with_24$acs_2024_bg_allocations
  if (spec$source == "rhu_miss_rent") {
    frame$rhuE[1] <- NA_real_
    frame$rentE[1] <- NA_real_
  } else frame[[spec$source]][1] <- NaN
  diag <- bg_aggregation_diagnostics(frame, with_24$bg_reference_2024)
  target_diag <- filter(diag$measure, measure == spec$measure, tr2010_id == tract_ids[1])
  stopifnot(!target_diag$complete, target_diag$n_missing_values == 1L)
  ordinary <- calc_agg_vars(frame, tr2010_id)
  name <- if (spec$measure == "mf5E") "mfE" else spec$measure
  if (name %in% names(ordinary)) {
    stopifnot(is.na(ordinary[[name]][1]))
  } else {
    supplemental <- new.env(parent = environment())
    supplemental$acs_2024_bg_allocations <- frame
    supplemental$acs_2024_bg_aggregated <- ordinary
    supplemental$bg_reference_2024 <- with_24$bg_reference_2024
    supplemental$bg_count_qa_2024 <- diag
    supplemental$target_tract_ids_2024_bg_aggregated <- with_24$bg_reference_2024$targets
    run_chunk("aggregate-supplemental-2024-bg-aggregated", supplemental, bg_notebook)
    stopifnot(is.na(supplemental$acs_2024_bg_aggregated[[name]][1]))
  }
}

reference <- mixed$bg_reference_2024
frame <- mixed$acs_2024_bg_allocations
snapshot <- as.list(reference)
expect_error(reference$targets <- character(), "locked binding")
expect_error(reference$links$wt_pop[1] <- 0, "locked binding")
for (bad in list(frame[-1, ], frame[-c(1, 2), ], bind_rows(frame, frame[1, ]),
                 mutate(frame, bg2020_id = replace(bg2020_id, 1, "060379999999")),
                 mutate(frame, tr2010_id = replace(tr2010_id, 1, "06037999999")),
                 bind_rows(frame, mutate(frame[1, ], bg2020_id = "060379999999")))) {
  expect_error(assert_bg_contributors(bad, reference), "BG")
}
expect_error(assert_bg_contributors(mutate(frame, wt_pop = replace(wt_pop, 2, 2e-30)), reference),
             "changed allocation weights")
expect_error(assert_bg_contributors(mutate(frame, .acs_present = FALSE), reference), "no ACS source row")
expect_error(assert_bg_contributors(select(frame, -.acs_present), reference), "join marker")
expect_error(assert_bg_contributors(mutate(frame, .acs_present = NA), reference), "join marker")
for (weight in bg_weight_columns()) {
  for (bad in c(NA_real_, NaN, Inf, -Inf, -0.1, 1.1)) {
    broken <- frame
    broken[[weight]][1] <- bad
    expect_error(assert_bg_contributors(broken, reference), "finite fractions")
  }
}
expect_error(new_bg_aggregation_reference(select(frame, -wt_pop)), "all four weights")
expect_error(new_bg_aggregation_reference(mutate(frame, bg2020_id = "bad")), "character GEOIDs")
for (value in c(-1, Inf, -Inf)) {
  expect_error(bg_aggregation_diagnostics(mutate(frame, popE = value), reference), "finite and nonnegative")
}
expect_error(bg_aggregation_diagnostics(mutate(frame, popE = "100"), reference), "must be numeric")
quiet(assert_bg_contributors(frame[3:1, ], reference))
reordered_qa <- lapply(qa, function(x) x[rev(seq_len(nrow(x))), ])
quiet(assert_bg_diagnostics(frame, reference, reordered_qa))
for (field in c("n_expected", "n_matched", "n_missing_links", "n_missing_values",
                "zero_contributors", "complete", "expected_total")) {
  tampered <- qa
  tampered$measure[[field]][1] <- if (is.logical(tampered$measure[[field]])) {
    !tampered$measure[[field]][1]
  } else 123
  expect_error(assert_bg_diagnostics(frame, reference, tampered), "diagnostics disagree")
}
tampered <- qa
tampered$family$n_expected[1] <- 999L
expect_error(assert_bg_diagnostics(frame, reference, tampered), "diagnostics disagree")
wrong_counts <- result
wrong_counts$popE[1] <- 100
expect_error(assert_bg_count_aggregates(wrong_counts, frame, reference, qa), "source completeness")
wrong_counts <- result
wrong_counts$hhE[1] <- 101
expect_error(assert_bg_count_aggregates(wrong_counts, frame, reference, qa), "weighted totals")
for (field in c("n_contributing", "n_missing_rhuE", "n_missing_vac_forrentE",
                "n_missing_vac_rentedE", "inventory_incomplete", "inventory_vac_forrentE")) {
  tampered <- mixed$inventory_2024_bg_aggregated
  tampered[[field]][1] <- if (is.logical(tampered[[field]])) !tampered[[field]][1] else 999L
  expect_error(assert_bg_inventory_reference(frame, reference, tampered), "BG inventory")
}
stopifnot(identical(snapshot, as.list(reference)))
cat("Passed: family-specific missingness, zero contributors, immutable reference, integrity failures, and independent inventory QA.\n")

# Execute the actual join with complete original source weights, cross-county
# inputs, split destinations, and an unmatched zero-only target.
original_xwalk <- assembly_sources |> select(bg2020_id, tr2010_id, all_of(bg_weight_columns()))
outside <- original_xwalk[3, ] |>
  mutate(tr2010_id = "06073000001", across(all_of(bg_weight_columns()), ~ 1 - .x))
cross_county <- original_xwalk[1, ] |>
  mutate(bg2020_id = "060730000001", across(all_of(bg_weight_columns()), ~ 0.25))
absent_zero <- cross_county |>
  mutate(bg2020_id = "320030000001", tr2010_id = tract_ids[3], across(all_of(bg_weight_columns()), ~ 0))
full_xwalk <- bind_rows(original_xwalk, outside, cross_county,
                       mutate(cross_county, tr2010_id = "06073000001", across(all_of(bg_weight_columns()), ~ 0.75)),
                       absent_zero,
                       mutate(absent_zero, tr2010_id = "32003000001", across(all_of(bg_weight_columns()), ~ 1)))
full_source <- assembly_sources |> select(-tr2010_id, -starts_with("wt_")) |> distinct()
full_source <- bind_rows(full_source, mutate(full_source[1, ], bg2020_id = cross_county$bg2020_id))
joined <- new.env(parent = environment())
joined$xwalk <- full_xwalk
joined$acs_2024_bg_source <- full_source
joined$target_counties <- "037"
joined$southern_california_counties <- "037"
failed_join <- new.env(parent = environment())
failed_join$xwalk <- full_xwalk
failed_join$xwalk$wt_pop[1] <- 0.1
failed_join$acs_2024_bg_source <- full_source
failed_join$target_counties <- "037"
expect_error(run_chunk("merge-and-restrict-2024-bg-aggregated", failed_join, bg_notebook),
             "Full source weights must sum to one")
run_chunk("merge-and-restrict-2024-bg-aggregated", joined, bg_notebook)
stopifnot(nrow(joined$acs_2024_bg_allocations) == 5L,
          identical(joined$zero_weight_unmatched, absent_zero |> arrange(bg2020_id, tr2010_id)),
          nrow(joined$socal_boundary_contributions_2024_bg_aggregated) == 1L,
          sum(joined$acs_2024_bg_allocations$wt_renthu[joined$acs_2024_bg_allocations$bg2020_id == source_ids[2]]) == 0.4)
joined_reference <- as.list(joined$bg_reference_2024)
joined$prior_outputs <- list(`2024_bg_aggregated` = NULL)
for (chunk in c("relative-weights-and-tc-2024-bg-aggregated", "income-expectations-2024-bg-aggregated",
                "censor-and-structure-2024-bg-aggregated", "aggregate-to-tracts-2024-bg-aggregated",
                "aggregate-supplemental-2024-bg-aggregated", "rental-inventory-2024-bg-aggregated",
                "derive-measures-2024-bg-aggregated", "merge-flags-2024-bg-aggregated",
                "acceptance-2024-bg-aggregated")) run_chunk(chunk, joined, bg_notebook)
stopifnot(identical(joined_reference, as.list(joined$bg_reference_2024)),
          joined$acs_2024_bg_aggregated$popE[3] == 0)
cat("Passed: original join, cross-county/split links, full-source audit, and unmatched all-zero target retention.\n")

# Unchanged interpolation may remain available when a later bin is missing.
bins <- assembly_sources |> mutate(.acs_present = TRUE)
bins$grentcat24E[1] <- NA_real_
late_bin <- assemble_allocations(bins)
stopifnot(is.na(late_bin$acs_2024_bg_aggregated$grentcat24E[1]),
          is.finite(late_bin$acs_2024_bg_aggregated_interp$interp_rent[1]))
late_expectations <- bg_count_parity_expectations(late_bin$acs_2024_bg_allocations, late_bin$bg_reference_2024)
stopifnot(!"interp_rent" %in% late_expectations$variable)
bins$grentcat1E[1] <- NA_real_
early_bin <- assemble_allocations(bins)
early_expectations <- bg_count_parity_expectations(early_bin$acs_2024_bg_allocations, early_bin$bg_reference_2024)
stopifnot(is.na(early_bin$acs_2024_bg_aggregated_interp$interp_rent[1]),
          "interp_rent" %in% early_expectations$variable)
dependent <- assembly_sources |> mutate(.acs_present = TRUE)
dependent$rhuE[3] <- NA_real_
dependent_result <- assemble_allocations(dependent)
dependent_expectations <- bg_count_parity_expectations(
  dependent_result$acs_2024_bg_allocations, dependent_result$bg_reference_2024)
stopifnot(all(c("pctrhuE", "pctrhuM", "pctrhuCV", "rhuCV", "pctrvacE", "pct_miss_rent") %in%
                dependent_expectations$variable),
          filter(dependent_expectations, variable == "pctrhuE")$legacy == 25 / 160,
          is.na(dependent_result$acs_2024_bg_aggregated$pctrhuM[1]))

# Two-sided count expectations are source-derived and limited to declared counts
# and their dependencies. A missing reference remains explicitly unchecked.
expectations <- bg_count_parity_expectations(frame, reference)
stopifnot(all(c("popE", "rhuE", "mf5E", "nsfaE") %in% expectations$variable),
          !any(c("med_hhincE", "med_hhincCV", "rhuM", "pct_tc_rent", "tc_flag_rent_24") %in% expectations$variable))
legacy <- result
for (i in seq_len(nrow(expectations))) {
  legacy[[expectations$variable[i]]][match(expectations$tr2010_id[i], legacy$tr2010_id)] <- expectations$legacy[i]
}
parity_count <- function(current = result, previous = legacy, expected = expectations, ...) {
  quiet(compare_socal_parity(current, previous, "037", expected_count_corrections = expected, ...))
}
audit <- parity_count()
stopifnot(nrow(audit$differences) == nrow(expectations),
          all(audit$differences$classification == "verified_count_correction"),
          all(audit$differences$allocation == "unaffected"))
expect_error(parity_count(expected = NULL), "parity failed")
expect_error(parity_count(expected = expectations[0, ]), "parity failed")
expect_error(parity_count(expected = expectations[-1, ]), "parity failed")
expect_error(parity_count(expected = bind_rows(expectations, expectations[1, ])), "duplicate key")
expect_error(parity_count(expected = mutate(expectations, variable = "rhuM")), "Count expectations require")
expect_error(parity_count(expected = mutate(expectations, corrected = "missing")), "Count expectations require")
expect_error(parity_count(expected = mutate(expectations, legacy = 123)), "parity failed")
expect_error(parity_count(expected = mutate(expectations, corrected = 123)), "parity failed")
expect_error(parity_count(expected = mutate(expectations, tr2010_id = NA_character_)), "missing or duplicate key")
expect_error(parity_count(mutate(result, popE = 123)), "parity failed")
expect_error(parity_count(previous = mutate(legacy, popE = 123)), "parity failed")
expect_error(parity_count(mutate(result, tc_flag_rent_24 = 123)), "parity failed")
expect_error(parity_count(mutate(result, med_hhincM = 123)), "parity failed")
expect_error(parity_count(mutate(result, extra = 123)), "order, or types differ")
expect_error(parity_count(mutate(result, hhE = as.integer(hhE))), "order, or types differ")
expect_error(parity_count(result[-1, ]), "parity failed")
stopifnot(is.null(parity_count(previous = NULL)))
shuffled <- parity_count(result[2:1, ], legacy[2:1, ], expectations[nrow(expectations):1, ])
stopifnot(nrow(shuffled$differences) == nrow(audit$differences))

# Shared helper's native-tract key/default schema and value checks still work.
native <- tibble(tr2020_id = tract_ids, rhuE = c(1, 0, NA_real_), med_hhincE = c(80000, NA, 0))
stopifnot(nrow(quiet(compare_socal_parity(native, native, "037", key = "tr2020_id",
                                       schema_migration = "2024_tract"))$differences) == 0L)
expect_error(compare_socal_parity(mutate(native, rhuE = 5), native, "037", key = "tr2020_id",
                                  schema_migration = "2024_tract"), "parity failed")
expect_error(compare_socal_parity(select(native, -rhuE), native, "037", key = "tr2020_id",
                                  schema_migration = "2024_tract"), "unapproved schema")
for (migration in c("2016", "2024")) {
  minimal <- tibble(tr2010_id = tract_ids, rhuE = c(1, 0, NA_real_))
  old <- mutate(minimal, rhu_lrE = 1, rhu_lr2E = 2)
  new <- mutate(minimal, rhu_inventoryE = c(2, 0, NA_real_))
  stopifnot(nrow(quiet(compare_socal_parity(new, old, "037", schema_migration = migration))$differences) == 0L)
  expect_error(compare_socal_parity(mutate(new, rhuE = 3), old, "037", schema_migration = migration), "parity failed")
}
cat("Passed: individually verified count parity, rejected unexplained differences, and shared-helper compatibility.\n")

# Missing estimates survive the Feather round trip; decomposition only checks
# complete required counts and retains incomplete groups for Pass 3 review.
mixed$acs_2024_bg_aggregated_out <- mixed$acs_2024_bg_aggregated_interp
mixed$target_counties <- "037"
run_chunk("validate-county-rent-step2", mixed, bg_notebook)
stopifnot(nrow(mixed$rent_share_deferred_2024) == 1L)
path <- tempfile(fileext = ".feather")
tryCatch({
  arrow::write_feather(result, path)
  reloaded <- arrow::read_feather(path)
  stopifnot(identical(reloaded, result))
  quiet(assert_bg_count_aggregates(reloaded, frame, reference, qa))
  quiet(assert_rental_inventory(reloaded, mixed$inventory_2024_bg_aggregated, "Synthetic reload"))
}, finally = unlink(path))

for (file in c("R/assemble_helpers.R", "R/geography_qa.R", "R/bg_aggregation_qa.R",
               "tests/test_rental_inventory.R", "tests/test_bg_aggregation_qa.R")) parse(here::here(file))
for (notebook in c(bg_notebook, tract_notebook)) {
  lines <- readLines(here::here(notebook))
  starts <- which(startsWith(lines, "```{r"))
  labels <- sub("^```\\{r ([^,}]+).*", "\\1", lines[starts])
  stopifnot(!anyDuplicated(labels))
  for (start in starts) {
    end <- which(seq_along(lines) > start & lines == "```")[1]
    parse(text = lines[seq.int(start + 1L, end - 1L)])
  }
  cat("Parsed", length(starts), "chunks:", notebook, "\n")
}
cat("Passed: incomplete-count Feather readback, complete-only rent decomposition, and code parsing.\n")
