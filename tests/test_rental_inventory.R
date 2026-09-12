# Run from the repository root: Rscript tests/test_rental_inventory.R
# Synthetic inputs only. Exercises helpers and selected notebook chunks, with
# temporary Feather round trips; never reads or writes canonical data outputs.
suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(here)
  library(matrixStats)
  library(purrr)
  library(stringr)
  library(arrow)
})
source(here::here("R", "assemble_helpers.R"))
source(here::here("R", "geography_qa.R"))

quiet <- function(expr) {
  invisible(capture.output(value <- force(expr)))
  invisible(value)
}
expect_error <- function(expr, message) {
  error <- tryCatch({ quiet(expr); NULL }, error = identity)
  stopifnot(inherits(error, "error"), grepl(message, conditionMessage(error), fixed = TRUE))
}
inventory <- function(df) calc_rental_inventory(df, tr2010_id, "wt_renthu")
components <- c("rhuE", "vac_forrentE", "vac_rentedE")
tract_ids <- sprintf("06037%06d", 1:3)
source_ids <- sprintf("06037%07d", 1:3)
one <- tibble(
  tr2010_id = tract_ids[1], bg2020_id = source_ids[1],
  rhuE = 100, vac_forrentE = 10, vac_rentedE = 5,
  rhuM = NA_real_, vac_forrentM = NA_real_, vac_rentedM = NA_real_,
  rentE = NA_real_, lqcrentE = NA_real_, med_hhincE = NA_real_,
  wt_renthu = 1, wt_hu = 0.8
)
direct <- calc_rental_inventory(one, tr2010_id)
stopifnot(direct$rhu_inventoryE == 115, direct$n_contributing == 1L,
          !direct$inventory_incomplete, typeof(direct$rhu_inventoryE) == "double")
quiet(assert_rental_inventory(select(direct, tr2010_id, rhu_inventoryE), direct, "Direct"))
stopifnot(calc_rental_inventory(mutate(one, rhuE = 0), tr2010_id)$rhu_inventoryE == 15)

# Every component uses renter weights, even when housing weights disagree.
split <- one[c(1, 1), ] |>
  mutate(tr2010_id = tract_ids[1:2], wt_renthu = c(0.25, 0.75), wt_hu = c(0.8, 0.2))
split_before <- split
split_inventory <- inventory(split)
stopifnot(identical(split, split_before),
          identical(split_inventory$rhu_inventoryE, c(28.75, 86.25)),
          identical(split_inventory$inventory_vac_forrentE, c(2.5, 7.5)))
stopifnot(inventory(split[1, ])$rhu_inventoryE == 28.75)
multiple <- bind_rows(split, mutate(one, bg2020_id = source_ids[2],
                                   rhuE = 40.5, vac_forrentE = 2, vac_rentedE = 1,
                                   wt_renthu = 0.4))
multiple_inventory <- inventory(multiple)
stopifnot(isTRUE(all.equal(multiple_inventory$rhu_inventoryE, c(46.15, 86.25))),
          identical(multiple_inventory$n_contributing, c(2L, 1L)))
reconciled <- reconcile_rental_inventory(multiple, multiple_inventory, tr2010_id, "wt_renthu")
stopifnot(isTRUE(all.equal(reconciled$source_first, 132.4)))

# NA and NaN in any required estimate propagate, with component-specific counts.
for (column in components) {
  for (missing in c(NA_real_, NaN)) {
    source <- one
    source[[column]] <- missing
    for (result in list(calc_rental_inventory(source, tr2010_id), inventory(source))) {
      stopifnot(identical(result$rhu_inventoryE, NA_real_), result$inventory_incomplete,
                result[[paste0("n_missing_", column)]] == 1L,
                is.na(result[[paste0("inventory_", column)]]))
      other <- paste0("inventory_", setdiff(components, column))
      stopifnot(all(is.finite(as.matrix(result[other]))))
      quiet(assert_rental_inventory(select(result, tr2010_id, rhu_inventoryE), result, "Missing"))
    }
    mixed_sources <- bind_rows(one, mutate(source, bg2020_id = source_ids[2]))
    mixed_result <- inventory(mixed_sources)
    stopifnot(is.na(mixed_result$rhu_inventoryE), mixed_result$n_contributing == 2L,
              mixed_result[[paste0("n_missing_", column)]] == 1L)
    mixed_sources[[column]] <- missing
    all_missing_component <- inventory(mixed_sources)
    stopifnot(is.na(all_missing_component$rhu_inventoryE),
              all_missing_component[[paste0("n_missing_", column)]] == 2L)
  }
}
all_missing <- one |> mutate(across(all_of(components), ~ NA_real_))
stopifnot(is.na(inventory(all_missing)$rhu_inventoryE))
zero_link <- all_missing |> mutate(bg2020_id = source_ids[2], wt_renthu = 0)
zero_plus_observed <- inventory(bind_rows(one, zero_link))
stopifnot(zero_plus_observed$rhu_inventoryE == 115,
          zero_plus_observed$n_contributing == 1L, !zero_plus_observed$inventory_incomplete,
          all(as.matrix(select(zero_plus_observed, starts_with("n_missing_"))) == 0))
zero_only <- inventory(zero_link)
stopifnot(zero_only$rhu_inventoryE == 0, zero_only$n_contributing == 0L,
          !zero_only$inventory_incomplete,
          all(as.matrix(select(zero_only, all_of(paste0("inventory_", components)))) == 0))
quiet(assert_rental_inventory(select(zero_only, tr2010_id, rhu_inventoryE), zero_only, "Zero links"))
stopifnot(is.na(inventory(mutate(zero_link, wt_renthu = 1e-20))$rhu_inventoryE))

# Exclude incomplete targets from reconciliation without redistributing weights.
partly_incomplete <- bind_rows(split, mutate(all_missing, bg2020_id = source_ids[2]))
partial_inventory <- inventory(partly_incomplete)
partial_reconciliation <- reconcile_rental_inventory(
  partly_incomplete, partial_inventory, tr2010_id, "wt_renthu"
)
stopifnot(partial_reconciliation$source_first == 86.25,
          partial_reconciliation$target_first == 86.25,
          partial_reconciliation$incomplete_targets == 1L)
empty_reconciliation <- reconcile_rental_inventory(all_missing, inventory(all_missing), tr2010_id, "wt_renthu")
stopifnot(empty_reconciliation$complete_targets == 0L, empty_reconciliation$target_first == 0,
          empty_reconciliation$incomplete_targets == 1L)
quiet(assert_rental_inventory(select(partial_inventory, tr2010_id, rhu_inventoryE),
                              partial_inventory[2:1, ], "Reordered diagnostics"))
expect_error(assert_rental_inventory(mutate(partial_inventory, rhu_inventoryE = 0),
                                     partial_inventory, "Wrong missingness"), "missingness must match")
expect_error(assert_rental_inventory(mutate(split_inventory, rhu_inventoryE = rhu_inventoryE + 1),
                                     split_inventory, "Wrong total"), "sum of its three components")
expect_error(assert_rental_inventory(split_inventory[-1, ], split_inventory, "Wrong keys"), "key sets must agree")
expect_error(assert_rental_inventory(split_inventory,
                                     mutate(split_inventory, inventory_incomplete = TRUE), "Wrong flag"),
             "completeness must agree")

# Weights and observed contributing estimates must meet their input contracts.
for (bad_weight in c(NA_real_, NaN, Inf, -Inf, -0.1, 1.1)) {
  expect_error(inventory(mutate(one, wt_renthu = bad_weight)), "finite fractions")
}
expect_error(inventory(mutate(one, wt_renthu = "1")), "finite fractions")
for (column in components) {
  for (bad_value in c(-1, Inf, -Inf)) {
    source <- one
    source[[column]] <- bad_value
    expect_error(inventory(source), "finite and nonnegative")
  }
}
for (column in c(components, sub("E$", "M", components))) {
  expect_error(calc_rental_inventory(select(one, -all_of(column)), tr2010_id), "estimate/MOE columns")
  source <- one
  source[[column]] <- "100"
  expect_error(inventory(source), "must be numeric")
}
expect_error(inventory(mutate(one, tr2010_id = NA_character_)), "11-digit tract GEOIDs")
expect_error(inventory(mutate(one, tr2010_id = "0603700001")), "11-digit tract GEOIDs")
expect_error(inventory(mutate(one, tr2010_id = as.numeric(tr2010_id))), "11-digit tract GEOIDs")
expect_error(inventory(mutate(one, bg2020_id = "bad")), "12-digit source GEOIDs")
expect_error(inventory(bind_rows(one, one)), "unique allocation pairs")
expect_error(calc_rental_inventory(bind_rows(one, one), tr2010_id), "unique tract keys")
cat("Passed: component sums, split/fractional allocations, missingness, zero links, and input validation.\n")

# Run actual notebook joins and downstream measures with/without inventory.
notebook_lines <- readLines(here::here("02_assemble.Rmd"))
run_chunk <- function(label, env) {
  start <- match(paste0("```{r ", label, "}"), notebook_lines)
  stopifnot(!is.na(start))
  end <- which(seq_along(notebook_lines) > start & notebook_lines == "```")[1]
  quiet(eval(parse(text = notebook_lines[seq.int(start + 1L, end - 1L)]), env))
}
assembly_sources <- multiple |>
  mutate(rentE = c(3500, 3500, 1800), lqcrentE = 1400, med_hhincE = 80000,
         wt_pop = 0.5, wt_hh = 0.5, med_hvalE = 800000, vac_forsaleE = 5,
         ohuE = 100, vac_rentedE = c(5, 5, NA_real_))
count_columns <- c(
  "huE", "rhu_lrE", "rhu_lr2E", "rhu_baseE", "hhE", "popE", "tot_vacE", "tot_vac_baseE",
  "pop_blkE", "pop_hspE", "pop_aaE", "pop_raceE", "pop_ethnE", "sfd_detE", "sfd_baseE",
  "mf_5_9E", "mf_10_19E", "mf_20_49E", "mf_50E", "sfd_attE", "duplexE", "quadplexE", "rhucashE"
)
moe_columns <- c("rentM", "lqcrentM", "med_hhincM", "med_hvalM", "rhu_baseM", "tot_vacM",
                 "tot_vac_baseM", "pop_blkM", "pop_hspM", "pop_aaM", "pop_raceM", "sfd_detM",
                 "sfd_baseM", "huM", "popM")
for (column in count_columns) assembly_sources[[column]] <- 100
for (column in moe_columns) assembly_sources[[column]] <- 10
for (column in paste0("grentcat", 1:24, "E")) assembly_sources[[column]] <- 100 / 24

assemble_24 <- function(include_inventory) {
  env <- new.env(parent = environment())
  env$acs_bg <- assembly_sources
  env$weight_cols <- c("wt_pop", "wt_hh", "wt_hu", "wt_renthu")
  env$xwalk_target <- select(assembly_sources, bg2020_id, tr2010_id, all_of(env$weight_cols))
  env$target_tract_ids_24 <- unique(assembly_sources$tr2010_id)
  chunks <- c("relative-weights-and-tc", "censor-and-structure", "aggregate-to-tracts",
              "aggregate-supplemental-24", if (include_inventory) "rental-inventory-24",
              "derive-measures-24", "merge-flags-24")
  for (chunk in chunks) run_chunk(chunk, env)
  env
}
assemble_16 <- function(include_inventory) {
  env <- new.env(parent = environment())
  env$acs_16 <- assembly_sources[c(1, 3), ] |>
    mutate(tr2010_id = tract_ids[1:2]) |>
    select(-bg2020_id, -starts_with("wt_"))
  env$target_tract_ids_16 <- env$acs_16$tr2010_id
  chunks <- c("flag-censor-16", "structure-pct-cv-16", if (include_inventory) "rental-inventory-16")
  for (chunk in chunks) run_chunk(chunk, env)
  env
}
with_24 <- assemble_24(TRUE)
without_24 <- assemble_24(FALSE)
with_16 <- assemble_16(TRUE)
without_16 <- assemble_16(FALSE)
for (tables in list(list(with_24$acs_tr10_24_interp, without_24$acs_tr10_24_interp),
                    list(with_16$acs_16, without_16$acs_16))) {
  stopifnot(identical(setdiff(names(tables[[1]]), names(tables[[2]])), "rhu_inventoryE"),
            identical(select(tables[[1]], -rhu_inventoryE), tables[[2]]))
}
stopifnot(identical(with_24$acs_bg, without_24$acs_bg),
          !"vac_rentedE" %in% names(with_24$acs_tr10_24_interp),
          all(c("vac_rentedE", "vac_rentedM") %in% names(with_16$acs_16)),
          setequal(with_24$inventory_missing_sources_24$missing_component, "vac_rentedE"),
          setequal(with_24$inventory_missing_sources_24$bg2020_id, source_ids[2]))

round_trip <- function(df) {
  path <- tempfile(fileext = ".feather")
  on.exit(unlink(path))
  write_feather(df, path)
  reloaded <- read_feather(path)
  assert_same_schema(reloaded, df, "Synthetic Feather schema")
  reloaded
}
saved_env <- with_24
saved_env$acs_16 <- with_16$acs_16
saved_env$inventory_16 <- with_16$inventory_16
saved_env$inventory_missing_sources_16 <- with_16$inventory_missing_sources_16
saved_env$inventory_county_qa_16 <- with_16$inventory_county_qa_16
saved_env$acs16_out <- round_trip(with_16$acs_16)
saved_env$acs24_out <- round_trip(with_24$acs_tr10_24_interp)
run_chunk("validate-rental-inventory-step2", saved_env)
saved_env$acs24_out$pctrvacE[1] <- saved_env$acs24_out$pctrvacE[1] + 0.01
expect_error(run_chunk("validate-rental-inventory-step2", saved_env), "Saving must preserve every 2024 value")
cat("Passed: notebook joins, unchanged unrelated measures/allocations, and synthetic Feather validation.\n")

# Fixed vintage allowlists never authorize unrelated schema or value changes.
parity <- function(current, previous = current, migration = NULL, ...) {
  quiet(compare_socal_parity(current, previous, "037", schema_migration = migration, ...))
}
removed_measures <- c("rentmv1yr", "rentmv5yr", "rentyrblt", "rentyrblt_14_16",
                      "rentyrblt_10_13", "rentyrblt_00_09", "rentyrblt_90_99")
removed_columns <- as.vector(outer(removed_measures, c("E", "M"), paste0))
previous_16 <- without_16$acs_16 |> select(-vac_rentedE, -vac_rentedM)
for (column in removed_columns) previous_16[[column]] <- 1
current_16 <- with_16$acs_16
current_24 <- with_24$acs_tr10_24_interp
previous_24 <- without_24$acs_tr10_24_interp
expect_error(parity(current_16, previous_16), "output column names, order, or types differ")
expect_error(parity(current_24, previous_24), "output column names, order, or types differ")
audit_16 <- parity(current_16, previous_16, "2016")
audit_24 <- parity(current_24, previous_24, "2024")
stopifnot(nrow(audit_16$differences) == 0L, nrow(audit_24$differences) == 0L,
          setequal(filter(audit_16$schema_changes, change == "added")$variable,
                   c("vac_rentedE", "vac_rentedM", "rhu_inventoryE")),
          setequal(filter(audit_16$schema_changes, change == "removed")$variable, removed_columns),
          identical(audit_24$schema_changes$variable, "rhu_inventoryE"),
          nrow(parity(current_16, migration = "2016")$schema_changes) == 0L,
          nrow(parity(current_16)$schema_changes) == 0L)
expect_error(parity(current_16, previous_16, "2024"), "unapproved schema")
expect_error(parity(current_24, previous_24, "unknown"), "schema_migration must be")
expect_error(parity(mutate(current_24, rhu_inventoryE = "115"), previous_24, "2024"), "must be numeric")
expect_error(parity(select(current_16, -vac_rentedE), current_16, "2016"), "unapproved schema")
expect_error(parity(mutate(current_16, rentmv1yrE = 1), previous_16, "2016"), "estimate/MOE pairs")
for (vintage in c("2016", "2024")) {
  candidate <- if (vintage == "2016") current_16 else current_24
  reference <- if (vintage == "2016") previous_16 else previous_24
  expect_error(parity(mutate(candidate, unexpected = 1), reference, vintage), "unapproved schema")
  expect_error(parity(select(candidate, -rentM), reference, vintage), "unapproved schema")
  expect_error(parity(select(candidate, rhuE, everything()), reference, vintage), "order, or types differ")
  expect_error(parity(mutate(candidate, rhuE = as.integer(rhuE)), reference, vintage), "order, or types differ")
  expect_error(parity(mutate(candidate, rhuE = rhuE + 1), reference, vintage), "parity failed")
  expect_error(parity(bind_rows(candidate, candidate[1, ]), reference, vintage), "missing or duplicate key")
  expect_error(parity(candidate[-1, ], reference, vintage), "parity failed")
  expect_error(parity(mutate(candidate, rhu_inventoryE = 0), candidate, vintage), "parity failed")
}

# Approved income corrections and boundary classifications still work in migration mode.
income_reference <- previous_16 |> mutate(med_hhincE = NA_real_, med_hhincCV = NA_real_)
expected_income <- current_16 |>
  transmute(tr2010_id, legacy_med_hhincE = NA_real_, corrected_med_hhincE = med_hhincE,
            legacy_med_hhincCV = NA_real_, corrected_med_hhincCV = med_hhincCV)
income_audit <- parity(current_16, income_reference, "2016", expected_income = expected_income)
stopifnot(nrow(income_audit$differences) == 4L,
          all(income_audit$differences$classification == "verified_income_correction"),
          all(income_audit$differences$allocation == "unaffected"))
expect_error(parity(current_16, income_reference, "2016"), "parity failed")
expect_error(parity(mutate(current_16, med_hhincE = med_hhincE + 1), income_reference, "2016",
                    expected_income = expected_income), "parity failed")
expect_error(parity(mutate(current_16, med_hhincM = med_hhincM + 1), income_reference, "2016",
                    expected_income = expected_income), "parity failed")
boundary <- current_24
boundary$rhuE[1] <- boundary$rhuE[1] + 1
boundary_audit <- parity(boundary, previous_24, "2024", boundary_ids = boundary$tr2010_id[1])
stopifnot(nrow(boundary_audit$differences) == 1L,
          boundary_audit$differences$classification == "boundary_review")
for (vintage in c("2016", "2024")) {
  output <- capture.output(unchecked <- compare_socal_parity(
    current_16, NULL, "037", schema_migration = vintage
  ))
  stopifnot(is.null(unchecked), any(grepl("PARITY NOT CHECKED", output, fixed = TRUE)))
}
expect_error(assert_same_schema(current_24, previous_24, "Strict reload"), "order, or types differ")
cat("Passed: strict/default parity, narrow schema migration, income/boundary rules, and missing references.\n")
