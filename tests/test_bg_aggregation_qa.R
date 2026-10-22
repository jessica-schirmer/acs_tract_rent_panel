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
                 vac_forrentE = c(9.6, 2), rhu_miss_rent = c(0, 0))
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
  conditional$rentE[1] <- 3501
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

# Retained evidence gains a missing flag on unmatched links during the actual join.
join_source <- function(source, crosswalk = full_xwalk) {
  env <- new.env(parent = environment())
  env$xwalk <- crosswalk
  env$acs_2024_bg_source <- source
  env$target_counties <- "037"
  env$southern_california_counties <- "037"
  run_chunk("merge-and-restrict-2024-bg-aggregated", env, bg_notebook)
  env
}
retained_source <- retain_rent_evidence(full_source, key = "bg2020_id") |>
  mutate(rent_evidence_available = TRUE)
retained_source$rent_evidence_available[1] <- FALSE
with_evidence <- join_source(retained_source)
allocations <- with_evidence$acs_2024_bg_allocations
matched <- allocations |> filter(.acs_present)
unmatched <- allocations |> filter(!.acs_present)
stopifnot(identical(allocations[setdiff(names(allocations), rent_evidence_columns())],
                    joined$bg_original_allocations_2024),
          is.logical(allocations$rent_evidence_available),
          !anyNA(allocations$rent_evidence_available),
          identical(matched[rent_evidence_columns()],
                    retained_source[match(matched$bg2020_id, retained_source$bg2020_id),
                                    rent_evidence_columns()]),
          nrow(unmatched) == 1L, identical(unmatched$rent_evidence_available, FALSE),
          all(is.na(unmatched[setdiff(rent_evidence_columns(), "rent_evidence_available")])))
for (chunk in c("relative-weights-and-tc-2024-bg-aggregated",
                "censor-and-structure-2024-bg-aggregated")) {
  run_chunk(chunk, with_evidence, bg_notebook)
}
rent_columns <- c("rentE", rent_metadata_columns("24"), "rent_status_reason", "rent_median_bin")
stopifnot(identical(with_evidence$acs_2024_bg_allocations[rent_columns],
                    joined$acs_2024_bg_allocations[rent_columns]),
          identical(with_evidence$bg_reconciliation_source_2024[rent_columns],
                    joined$bg_reconciliation_source_2024[rent_columns]))

# Invalid evidence on matched rows and absent positive contributors still fail.
missing_flag <- retained_source
missing_flag$rent_evidence_available[1] <- NA
invalid_evidence <- join_source(missing_flag)
expect_error(run_chunk("relative-weights-and-tc-2024-bg-aggregated", invalid_evidence, bg_notebook),
             "Invalid retained B25064 evidence types")
for (weight in bg_weight_columns()) {
  positive_unmatched <- full_xwalk
  positive_unmatched[[weight]][positive_unmatched$bg2020_id == absent_zero$bg2020_id] <- 0.5
  expect_error(join_source(retained_source, positive_unmatched), "no ACS source row")
}
cat("Passed: retained evidence on zero-weight unmatched links, unchanged matched evidence, and strict contributor/evidence validation.\n")

# Every required bin gates interpolation, including bins after the median.
bins <- assembly_sources |> mutate(.acs_present = TRUE)
bins$grentcat24E[1] <- NA_real_
late_bin <- assemble_allocations(bins)
stopifnot(is.na(late_bin$acs_2024_bg_aggregated$grentcat24E[1]),
          is.na(late_bin$acs_2024_bg_aggregated_interp$interp_rent[1]))
count_expectations <- function(env) bg_count_parity_expectations(
  env$acs_2024_bg_allocations, env$bg_reference_2024, env$bg_original_allocations_2024)
late_expectations <- count_expectations(late_bin)
stopifnot("interp_rent" %in% late_expectations$variable)
bins$grentcat1E[1] <- NA_real_
early_bin <- assemble_allocations(bins)
early_expectations <- count_expectations(early_bin)
stopifnot(is.na(early_bin$acs_2024_bg_aggregated_interp$interp_rent[1]),
          "interp_rent" %in% early_expectations$variable)
dependent <- assembly_sources |> mutate(.acs_present = TRUE)
dependent$rhuE[3] <- NA_real_
dependent_result <- assemble_allocations(dependent)
dependent_expectations <- count_expectations(dependent_result)
stopifnot(all(c("pctrhuE", "pctrhuM", "pctrhuCV", "rhuCV", "pctrvacE", "pct_miss_rent") %in%
                dependent_expectations$variable),
          filter(dependent_expectations, variable == "pctrhuE")$legacy == 25 / 160,
          is.na(dependent_result$acs_2024_bg_aggregated$pctrhuM[1]))


observed_zero <- assembly_sources[1, ] |> mutate(.acs_present = TRUE, rhuE = 0)
zero_result <- assemble_allocations(observed_zero)$acs_2024_bg_aggregated_interp
stopifnot(zero_result$rhuE == 0, zero_result$pctrhuE == 0, zero_result$pctrvacE == 1,
          is.na(zero_result$rhuCV), zero_result$tc_flag_rent_24 == 0)

# An interior median has an independently calculated dollar value. All 25 count
# inputs gate it; missing MOEs and unrelated counts do not. Keep every target key.
rent_fixture <- complete[rep(1L, 5), c("tr2010_id", "rhucashE", paste0("grentcat", 1:24, "E"))]
rent_fixture$tr2010_id <- sprintf("06037%06d", 1:5)
rent_fixture$rhucashE <- c(20, 20, 20, 0, 0)
rent_fixture[paste0("grentcat", 1:24, "E")] <- 0
rent_fixture$grentcat17E[1] <- 4
rent_fixture$grentcat18E[1] <- 16
rent_fixture$grentcat1E[2] <- 20
rent_fixture$grentcat24E[3] <- 20
rent_fixture$grentcat18E[5] <- 20
rent_result <- calc_interp_rent(rent_fixture)
stopifnot(identical(rent_result$tr2010_id, rent_fixture$tr2010_id),
          rent_result$interp_rent[1] == 1000 + 249 * (10 - 4) / 16,
          all(is.na(rent_result$interp_rent[2:5])))
for (count in c("rhucashE", paste0("grentcat", 1:24, "E"))) {
  for (missing in c(NA_real_, NaN)) {
    partial <- rent_fixture
    partial[[count]][1] <- missing
    stopifnot(is.na(calc_interp_rent(partial)$interp_rent[1]))
  }
}
expect_error(calc_interp_rent(select(rent_fixture, -grentcat24E)), "grentcat24E")
all_bins_missing <- rent_fixture |> mutate(across(starts_with("grentcat"), ~ NA_real_))
stopifnot(all(is.na(calc_interp_rent(all_bins_missing)$interp_rent)))
stopifnot(identical(calc_interp_rent(mutate(rent_fixture, rhuE = NA_real_, grentcat18M = NA_real_)),
                    rent_result))

# Missing late-bin sources at zero weights are harmless; any positive weight counts.
zero_bin_source <- bins |> mutate(wt_renthu = replace(wt_renthu, 1, 0))
zero_bin_source$grentcat1E[1] <- 100 / 24
zero_bin_result <- assemble_allocations(zero_bin_source)
tiny_bin_source <- zero_bin_source |> mutate(wt_renthu = replace(wt_renthu, 1, 1e-30))
tiny_bin_result <- assemble_allocations(tiny_bin_source)
stopifnot(is.finite(zero_bin_result$acs_2024_bg_aggregated_interp$interp_rent[1]),
          is.na(tiny_bin_result$acs_2024_bg_aggregated_interp$interp_rent[1]),
          any(tiny_bin_result$bg_dependent_qa_2024$missing_sources$dependent == "interp_rent"))

# Run source-level incompleteness through each weighted denominator family.
affected <- list(
  hhE = c("med_hhincE", "med_hhincCV"),
  rhuE = c("rhuM", "med_hhincM", "med_hhincCV", "pct_miss_rent"),
  huE = c("huM", "rhu_baseM", "tot_vacM", "tot_vac_baseM", "sfd_detM", "sfd_baseM", "pctrhuM"),
  popE = c("popM", "pop_blkM", "pop_hspM", "pop_aaM", "pop_raceM", "pctblkM", "pcthspM")
)
for (count in names(affected)) {
  source <- assembly_sources |> mutate(.acs_present = TRUE)
  source[[count]][3] <- NA_real_
  if (count == "hhE") source$med_hhincE[3] <- NA_real_
  env <- assemble_allocations(source)
  output <- env$acs_2024_bg_aggregated_interp
  stopifnot(all(is.na(output[1, affected[[count]]])),
            is.finite(output$interp_rent[1]),
            identical(output[2, ], complete[2, ]))
  for (column in affected[[count]]) {
    bad <- output
    bad[[column]][1] <- 0
    expect_error(assert_bg_dependent_measures(bad, env$bg_count_qa_2024), "incomplete required counts")
  }
  if (count %in% c("rhuE", "huE", "popE")) {
    relative <- c(rhuE = "rel_wt_rhu", huE = "rel_wt_hu", popE = "rel_wt_pop")[[count]]
    stopifnot(all(is.na(env$acs_2024_bg_allocations[[relative]][source$tr2010_id == tract_ids[1]])))
  }
}
stopifnot(result$tc_flag_rent_24[1] == 0, is.na(result$tc_flag_rent_24[2]),
          is.na(result$interp_rent[2]), result$nsfaE[2] == 0)
for (column in c("interp_rent", "nsfaE", "pctrvacE", "pctrhuE", "popCV")) {
  env <- if (column == "interp_rent") late_bin else mixed
  bad <- env$acs_2024_bg_aggregated_interp
  bad[[column]][1] <- 0
  expect_error(assert_bg_dependent_measures(bad, env$bg_count_qa_2024), "incomplete required counts")
}

# Production and freshly recalculated QA cannot agree their way around the
# original source snapshot. Complete wrong totals and numeric partials both fail.
altered <- with_24$acs_2024_bg_allocations |> mutate(popE = popE + 10)
altered_qa <- bg_aggregation_diagnostics(altered, with_24$bg_reference_2024)
expect_error(assert_bg_count_aggregates(complete, with_24$bg_reconciliation_source_2024,
                                        with_24$bg_reference_2024, altered_qa), "diagnostics disagree")
stopifnot(identical(with_24$bg_original_allocations_2024$rentE, assembly_sources$rentE))
cat("Passed: all-bin interpolation gate, endpoints, source/weight edge cases, dependent gates, and original-source reconciliation.\n")

# Two-sided count expectations are source-derived and limited to declared counts
# and their dependencies. A missing reference remains explicitly unchecked.
expectations <- count_expectations(mixed)
stopifnot(all(c("popE", "rhuE", "mf5E", "nsfaE") %in% expectations$variable),
          "popM" %in% expectations$variable,
          !"rhu_inventoryE" %in% expectations$variable)
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
expect_error(parity_count(expected = mutate(expectations, variable = "rhu_inventoryE")), "Count expectations require")
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

# Missing estimates survive readback; coverage still requires its denominator.
mixed$acs_2024_bg_aggregated_out <- mixed$acs_2024_bg_aggregated_interp
mixed$target_counties <- "037"
run_chunk("validate-county-rent-step2", mixed, bg_notebook)
stopifnot(all(is.na(mixed$acs_2024_bg_aggregated_out$pct_miss_rent)))
path <- tempfile(fileext = ".feather")
tryCatch({
  arrow::write_feather(result, path)
  reloaded <- arrow::read_feather(path)
  stopifnot(identical(reloaded, result))
  quiet(assert_bg_count_aggregates(reloaded, frame, reference, qa))
  quiet(assert_bg_dependent_measures(reloaded, qa))
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
cat("Passed: incomplete-count Feather readback, missing-safe rent decomposition, and code parsing.\n")
