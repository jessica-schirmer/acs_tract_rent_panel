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
source(here::here("R", "bg_aggregation_qa.R"))
source(here::here("R", "acs_input_qa.R"))

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
bg_notebook <- "02a_aggregate_2024_block_groups.Rmd"
tract_notebook <- "02b_prepare_tract_sources.Rmd"
run_chunk <- function(label, env, notebook) {
  notebook_lines <- readLines(here::here(notebook))
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
  "huE", "rhu_baseE", "hhE", "popE", "tot_vacE", "tot_vac_baseE",
  "pop_blkE", "pop_hspE", "pop_aaE", "pop_raceE", "pop_ethnE", "sfd_detE", "sfd_baseE",
  "mf_5_9E", "mf_10_19E", "mf_20_49E", "mf_50E", "sfd_attE", "duplexE", "quadplexE", "rhucashE"
)
moe_columns <- c("rentM", "lqcrentM", "med_hhincM", "med_hvalM", "rhu_baseM", "tot_vacM",
                 "tot_vac_baseM", "pop_blkM", "pop_hspM", "pop_aaM", "pop_raceM", "sfd_detM",
                 "sfd_baseM", "huM", "popM")
for (column in count_columns) assembly_sources[[column]] <- 100
for (column in moe_columns) assembly_sources[[column]] <- 10
for (column in paste0("grentcat", 1:24, "E")) assembly_sources[[column]] <- 100 / 24

# Actual import chunks discard retired low-rent columns from older caches only.
legacy_bg_input <- mutate(assembly_sources, rhu_lrE = 70, rhu_lr2E = 90)
legacy_16_input <- legacy_bg_input[c(1, 3), ] |>
  mutate(tr2010_id = tract_ids[1:2]) |>
  select(-bg2020_id, -starts_with("wt_"))
legacy_import <- new.env(parent = environment())
legacy_import$data_dir <- tempdir()
legacy_import$target_counties <- "037"
legacy_import$load_data <- function(path, folder = NULL, name) {
  switch(name,
    acs_step1_2024_block_group.feather = legacy_bg_input,
    acs_step1_2016_tract.feather = legacy_16_input,
    xwalk_bg24_tr10.feather = select(legacy_bg_input, bg2020_id, tr2010_id, starts_with("wt_")))
}
run_chunk("import-bg-and-xwalk-2024-bg-aggregated", legacy_import, bg_notebook)
if (!isTRUE(get0("bg_only", ifnotfound = FALSE))) {
  run_chunk("load-restrict-16", legacy_import, tract_notebook)
} else {
  legacy_import$acs_16 <- select(legacy_16_input, -rhu_lrE, -rhu_lr2E)
}
stopifnot(identical(legacy_import$acs_2024_bg_source, select(legacy_bg_input, -rhu_lrE, -rhu_lr2E)),
          identical(legacy_import$acs_16, select(legacy_16_input, -rhu_lrE, -rhu_lr2E)))

assemble_24 <- function(include_inventory) {
  env <- new.env(parent = environment())
  env$acs_2024_bg_allocations <- mutate(assembly_sources, .acs_present = TRUE)
  env$weight_cols <- c("wt_pop", "wt_hh", "wt_hu", "wt_renthu")
  env$xwalk_target <- select(assembly_sources, bg2020_id, tr2010_id, all_of(env$weight_cols))
  env$bg_reference_2024 <- new_bg_aggregation_reference(env$xwalk_target)
  env$target_tract_ids_2024_bg_aggregated <- env$bg_reference_2024$targets
  chunks <- c("relative-weights-and-tc-2024-bg-aggregated", "censor-and-structure-2024-bg-aggregated", "aggregate-to-tracts-2024-bg-aggregated",
              "aggregate-supplemental-2024-bg-aggregated", if (include_inventory) "rental-inventory-2024-bg-aggregated",
              "derive-measures-2024-bg-aggregated", "merge-flags-2024-bg-aggregated")
  for (chunk in chunks) run_chunk(chunk, env, bg_notebook)
  env
}
assemble_16 <- function(include_inventory) {
  env <- new.env(parent = environment())
  env$acs_16 <- assembly_sources[c(1, 3), ] |>
    mutate(tr2010_id = tract_ids[1:2]) |>
    select(-bg2020_id, -starts_with("wt_"))
  env$target_tract_ids_16 <- env$acs_16$tr2010_id
  chunks <- c("flag-censor-16", "structure-pct-cv-16", if (include_inventory) "rental-inventory-16")
  for (chunk in chunks) run_chunk(chunk, env, tract_notebook)
  env
}
with_24 <- assemble_24(TRUE)
without_24 <- assemble_24(FALSE)
if (isTRUE(get0("bg_only", ifnotfound = FALSE))) {
  stopifnot(identical(select(with_24$acs_2024_bg_aggregated_interp, -rhu_inventoryE),
                      without_24$acs_2024_bg_aggregated_interp),
            identical(with_24$acs_2024_bg_allocations, without_24$acs_2024_bg_allocations))
  bg_saved <- with_24
  bg_saved$target_counties <- "037"
  bg_saved$data_dir <- paste0(tempfile("bg-inventory-"), "/")
  dir.create(bg_saved$data_dir)
  tryCatch({
    for (chunk in c("save-2024-bg-aggregated", "reload-step2", "validate-keys-step2",
                    "validate-missingness-step2", "validate-flags-step2", "validate-numeric-step2",
                    "validate-county-rent-step2", "validate-rental-inventory-step2")) {
      run_chunk(chunk, bg_saved, bg_notebook)
    }
    stopifnot(identical(bg_saved$acs_2024_bg_aggregated_out, bg_saved$acs_2024_bg_aggregated_interp))
    bg_saved$acs_2024_bg_aggregated_out$pctrvacE[1] <- 0.99
    expect_error(run_chunk("validate-rental-inventory-step2", bg_saved, bg_notebook),
                 "Saving must preserve every 2024 block-group-aggregated value")
  }, finally = unlink(bg_saved$data_dir, recursive = TRUE))
  cat("Passed: BG-only inventory chunks and temporary Feather round trip; no native notebook execution.\n")
} else {
with_16 <- assemble_16(TRUE)
without_16 <- assemble_16(FALSE)
for (tables in list(list(with_24$acs_2024_bg_aggregated_interp, without_24$acs_2024_bg_aggregated_interp),
                    list(with_16$acs_16, without_16$acs_16))) {
  stopifnot(identical(setdiff(names(tables[[1]]), names(tables[[2]])), "rhu_inventoryE"),
            identical(select(tables[[1]], -rhu_inventoryE), tables[[2]]))
}
stopifnot(identical(with_24$acs_2024_bg_allocations, without_24$acs_2024_bg_allocations),
          !"vac_rentedE" %in% names(with_24$acs_2024_bg_aggregated_interp),
          all(c("vac_rentedE", "vac_rentedM") %in% names(with_16$acs_16)),
          setequal(with_24$inventory_missing_sources_2024_bg_aggregated$missing_component, "vac_rentedE"),
          setequal(with_24$inventory_missing_sources_2024_bg_aggregated$bg2020_id, source_ids[2]))

# Exercise the new native-2020 tract path using documented source columns.
configured_env <- new.env(parent = environment())
run_chunk("set-paths", configured_env, tract_notebook)
native_ids <- c(sprintf("06037%06d", 1:8),
                paste0("06", configured_env$target_counties, "000009"), "06073000001")
native_source <- assembly_sources[rep(1L, length(native_ids)), ] |>
  select(-tr2010_id, -bg2020_id, -starts_with("wt_")) |>
  mutate(tr2020_id = native_ids, NAME = "Synthetic 2020 tract", rent_id = TRUE,
         rentE = 1800, lqcrentE = 1400, med_hhincE = 80000,
         vac_forrentE = 10, vac_rentedE = 5,
         rhu_lrE = 70, rhu_lr2E = 90)
for (bedroom in 1:3) {
  native_source[[paste0("rent", bedroom, "bdrE")]] <- 3600 + bedroom
  native_source[[paste0("rent", bedroom, "bdrM")]] <- 100
}
native_source$rentE[1:4] <- c(3499, 3500, 3501, NA_real_)
native_source$lqcrentE[1:4] <- c(3500, 3499, NA_real_, 3501)
native_source$med_hvalE[1:3] <- c(1999999, 2000000, 2000001)
native_source$rhuE[3:5] <- c(0, NA_real_, 0)
native_source$vac_forrentE[5:6] <- c(0, NA_real_)
native_source$vac_rentedE[c(5, 7)] <- c(0, NaN)
native_source$med_hhincE[6] <- NA_real_
native_source$rentE[8] <- NA_real_
native_source$ohuE[5] <- 0
native_source$vac_forsaleE[5] <- 0

assemble_2024_tract <- function(source = native_source, counties = "037", reference = NULL) {
  env <- new.env(parent = environment())
  run_chunk("set-paths", env, tract_notebook)
  if (!is.null(counties)) env$target_counties <- counties
  env$prior_outputs <- list(`2024_tract` = reference)
  env$load_data <- function(path, folder = NULL, name) {
    stopifnot(name == "acs_step1_2024_tract.feather")
    source
  }
  for (chunk in c("load-restrict-2024-tract", "income-source-2024-tract",
                  "flag-censor-2024-tract", "structure-pct-cv-2024-tract",
                  "rental-inventory-2024-tract", "acceptance-2024-tract")) {
    run_chunk(chunk, env, tract_notebook)
  }
  env
}
native <- assemble_2024_tract()
native_out <- native$acs_2024_tract
native_before <- filter(native_source, substr(tr2020_id, 3, 5) == "037")
stopifnot(
  identical(native_out$tr2020_id, native_before$tr2020_id),
  !any(c("tr2010_id", "interp_rent", "pct_miss_rent", "inventory_incomplete") %in% names(native_out)),
  identical(native_out$rentE[1:4], c(3499, NA_real_, NA_real_, NA_real_)),
  identical(native_out$lqcrentE[1:4], c(NA_real_, 3499, NA_real_, NA_real_)),
  identical(native_out$tc_flag_rent[1:4], c(0, 1, 1, NA_real_)),
  identical(native_out$m_flag_rent[1:4], c(0, 1, 1, 1)),
  identical(native_out$zero_flag_rhu[3:5], c(1, NA_real_, 1)),
  identical(native_out$tc_flag_med_hval[1:3], c(0, 1, 1)),
  identical(native_out$med_hhincE, native_before$med_hhincE),
  identical(native_out$med_hvalE, native_before$med_hvalE),
  identical(native_out$med_hhincCV, (native_before$med_hhincM / 1.645) / native_before$med_hhincE),
  native_out$rhu_inventoryE[3] == 15, native_out$rhu_inventoryE[5] == 0,
  all(is.na(native_out$rhu_inventoryE[c(4, 6, 7)])),
  native_out$rhu_inventoryE[8] == 115,
  is.na(native_out$pctrvacE[5]), is.na(native_out$pctsvacE[5]),
  all(native_out$mf5E == 400), all(native_out$smfE == 300), all(native_out$nsfaE == 700),
  native_out$pctrhuE[3] == 0, native_out$rentCV[1] == (10 / 1.645) / 3499,
  is.null(native$socal_parity_2024_tract)
)
# Older Step 1 low-rent columns are deliberately present in native_source.
stopifnot(!any(c("rhu_lrE", "rhu_lr2E") %in% names(native_out)))
pass_through <- setdiff(names(native_before), c("rentE", "lqcrentE", "rhu_lrE", "rhu_lr2E"))
stopifnot(identical(native_out[pass_through], native_before[pass_through]))
all_counties_native <- assemble_2024_tract(counties = NULL)
stopifnot(setequal(substr(all_counties_native$acs_2024_tract$tr2020_id, 3, 5),
                   configured_env$target_counties),
          !"06073000001" %in% all_counties_native$acs_2024_tract$tr2020_id)
expect_error(assemble_2024_tract(bind_rows(native_source, native_source[1, ])), "missing or duplicate key")
expect_error(assemble_2024_tract(mutate(native_source, tr2020_id = NA_character_)), "missing or duplicate key")
expect_error(assemble_2024_tract(mutate(native_source, tr2020_id = as.numeric(tr2020_id))), "character California tract GEOIDs")
expect_error(assemble_2024_tract(rename(native_source, tr2010_id = tr2020_id)), "tr2020_id")
expect_error(assemble_2024_tract(select(native_source, -rent2bdrM)), "documented tract fields")
expect_error(report_tract_counties(native_out, c("037", "001"), "Missing county", key = "tr2020_id"),
             "missing target counties")
expect_error(assert_tract_keys(native_out[-1, ], native_out$tr2020_id, "Membership", key = "tr2020_id"),
             "tract membership changed")
quiet(assert_rental_inventory(native_out, native$inventory_2024_tract[nrow(native_out):1, ],
                               "Reordered native diagnostics", key = "tr2020_id"))
native_parity <- assemble_2024_tract(reference = native_out)$socal_parity_2024_tract
stopifnot(nrow(native_parity$differences) == 0L,
          "tr2020_id" %in% names(native_parity$tracts),
          !"tr2010_id" %in% names(native_parity$tracts))
expect_error(assemble_2024_tract(reference = mutate(native_out, med_hhincE = med_hhincE + 1)), "parity failed")
expect_error(assemble_2024_tract(reference = select(native_out, -rhu_inventoryE)), "unapproved schema")
expect_error(assemble_2024_tract(reference = with_24$acs_2024_bg_aggregated_interp), "unapproved schema")
cat("Passed: native tract filtering, retained source fields/income, flags, derived measures, inventory, and strict source-specific parity.\n")

# Each product environment has no access to the other notebook's bindings.
bg_saved <- with_24
tract_saved <- with_16
for (name in ls(native, pattern = "2024_tract$")) assign(name, get(name, native), tract_saved)
tract_saved$rent_raw_qa_16 <- tibble(county = "037", tracts = nrow(with_16$acs_16))
validate_saved_products <- function(env, notebook, saves, products, filenames, references) {
  directory <- tempfile("step2-synthetic-")
  dir.create(directory)
  on.exit(unlink(directory, recursive = TRUE))
  # Load notebook helpers into an isolated parent; fixture globals cannot leak in.
  helper_env <- new.env(parent = parent.env(globalenv()))
  for (file in c("assemble_helpers.R", "geography_qa.R", "bg_aggregation_qa.R")) {
    sys.source(here::here("R", file), helper_env)
  }
  parent.env(env) <- helper_env
  env$target_counties <- "037"
  env$data_dir <- paste0(directory, "/")
  for (chunk in saves) run_chunk(chunk, env, notebook)
  stopifnot(setequal(list.files(directory), filenames))
  for (chunk in c("reload-step2", "validate-keys-step2", "validate-missingness-step2",
                  "validate-flags-step2", "validate-numeric-step2",
                  "validate-county-rent-step2", "validate-rental-inventory-step2")) {
    run_chunk(chunk, env, notebook)
  }
  env$parity_reference_dir <- file.path(directory, "references")
  dir.create(env$parity_reference_dir)
  # A corrupt unrelated product must never be opened by this notebook.
  unrelated <- if (notebook == bg_notebook) "acs_step2_16.feather" else "acs_step2_24.feather"
  writeLines("unrelated product", file.path(env$parity_reference_dir, unrelated))
  run_chunk("load-parity-references", env, notebook)
  stopifnot(identical(names(env$prior_outputs), names(references)),
            all(vapply(env$prior_outputs, is.null, logical(1))))
  for (i in seq_along(references)) {
    write_feather(get(products[i], env), file.path(env$parity_reference_dir, references[i]))
    # Exercise partially present maps as well as all-missing/all-present maps.
    run_chunk("load-parity-references", env, notebook)
    stopifnot(identical(names(env$prior_outputs), names(references)))
    for (j in seq_along(references)) {
      stopifnot(if (j <= i) identical(env$prior_outputs[[j]], get(products[j], env))
                else is.null(env$prior_outputs[[j]]))
    }
  }
  reference_hashes <- tools::md5sum(list.files(env$parity_reference_dir, full.names = TRUE))
  run_chunk("load-parity-references", env, notebook)
  stopifnot(identical(reference_hashes, tools::md5sum(names(reference_hashes))))
}
validate_saved_products(bg_saved, bg_notebook, "save-2024-bg-aggregated",
  "acs_2024_bg_aggregated_interp", "acs_step2_2024_block_group_aggregated.feather",
  c(`2024_bg_aggregated` = "acs_step2_24.feather"))
validate_saved_products(tract_saved, tract_notebook, c("save-16", "save-2024-tract"),
  c("acs_16", "acs_2024_tract"), c("acs_step2_2016_tract.feather", "acs_step2_2024_tract.feather"),
  c(`16` = "acs_step2_16.feather", `2024_tract` = "acs_step2_2024_tract.feather"))
bg_saved$acs_2024_bg_aggregated_out$pctrvacE[1] <- bg_saved$acs_2024_bg_aggregated_out$pctrvacE[1] + 0.01
expect_error(run_chunk("validate-rental-inventory-step2", bg_saved, bg_notebook), "Saving must preserve every 2024 block-group-aggregated value")
bg_saved$acs_2024_bg_aggregated_out <- bg_saved$acs_2024_bg_aggregated_interp
tract_saved$acs_2024_tract_out$rent1bdrE[1] <- tract_saved$acs_2024_tract_out$rent1bdrE[1] + 1
expect_error(run_chunk("validate-rental-inventory-step2", tract_saved, tract_notebook), "Saving must preserve every 2024 tract-source value")
tract_saved$acs_2024_tract_out <- tract_saved$acs_2024_tract
tract_saved$acs16_out$rentE[1] <- 1
expect_error(run_chunk("validate-rental-inventory-step2", tract_saved, tract_notebook), "Saving must preserve every 2016 value")
tract_saved$acs16_out <- tract_saved$acs_16

# Optional post-cleanup baseline captured before this structural refactor.
baseline_path <- Sys.getenv("STEP2_SPLIT_BASELINE")
if (nzchar(baseline_path)) {
  stopifnot(identical(readRDS(baseline_path), list(
    bg = with_24$acs_2024_bg_aggregated_interp, tract16 = with_16$acs_16, tract24 = native_out)))
  cat("Passed: exact pre-split fixture parity for all three product tables.\n")
}

# Execute each notebook's complete operational chunk sequence on small fixtures,
# with only its declared input files and no access to the test's global objects.
run_isolated_notebook <- function(notebook, inputs, outputs, helper_dir = here::here("R")) {
  directory <- tempfile("step2-isolated-")
  dir.create(directory)
  on.exit(unlink(directory, recursive = TRUE))
  for (name in names(inputs)) write_feather(inputs[[name]], file.path(directory, name))
  env <- new.env(parent = parent.env(globalenv()))
  for (file in c("assemble_helpers.R", "geography_qa.R", "bg_aggregation_qa.R")) {
    # Historical split baselines predate the BG-only QA file.
    if (file != "bg_aggregation_qa.R" || file.exists(file.path(helper_dir, file))) {
      sys.source(file.path(helper_dir, file), env)
    }
  }
  lines <- readLines(notebook, warn = FALSE)
  starts <- which(startsWith(lines, "```{r"))
  for (start in starts) {
    label <- sub("^```\\{r ([^,}]+).*", "\\1", lines[start])
    if (label %in% c("setup", "load-packages", "load-helpers") ||
        grepl("eval=FALSE", lines[start], fixed = TRUE)) next
    end <- which(seq_along(lines) > start & lines == "```")[1]
    quiet(eval(parse(text = lines[seq.int(start + 1L, end - 1L)]), env))
    if (label == "set-paths") {
      env$data_dir <- paste0(directory, "/")
      env$parity_reference_dir <- file.path(directory, "absent-references")
      env$target_counties <- "037"
    }
  }
  stopifnot(setequal(list.files(directory), c(names(inputs), outputs)))
  setNames(lapply(file.path(directory, outputs), read_feather), outputs)
}
fixture_bg <- assembly_sources |> select(-tr2010_id, -starts_with("wt_")) |> distinct()
fixture_xwalk <- assembly_sources |> select(bg2020_id, tr2010_id, starts_with("wt_"))
# Complete the second source's original fractions with an outside destination.
fixture_outside <- fixture_xwalk[3, ] |>
  mutate(tr2010_id = "06073000001", across(starts_with("wt_"), ~ 1 - .x))
fixture_xwalk <- bind_rows(fixture_xwalk, fixture_outside)
bg_inputs <- list(acs_step1_2024_block_group.feather = fixture_bg,
                  xwalk_bg24_tr10.feather = fixture_xwalk)
tract_inputs <- list(acs_step1_2016_tract.feather = legacy_16_input,
                     acs_step1_2024_tract.feather = native_source)
bg_files <- "acs_step2_2024_block_group_aggregated.feather"
tract_files <- c("acs_step2_2016_tract.feather", "acs_step2_2024_tract.feather")
isolated_bg <- run_isolated_notebook(here::here(bg_notebook), bg_inputs, bg_files)
isolated_tract <- run_isolated_notebook(here::here(tract_notebook), tract_inputs, tract_files)
if (nzchar(baseline_path)) {
  frozen_dir <- dirname(baseline_path)
  frozen_products <- run_isolated_notebook(file.path(frozen_dir, "02_assemble.Rmd"),
    c(bg_inputs, tract_inputs), c(bg_files, tract_files), helper_dir = frozen_dir)
  stopifnot(identical(c(isolated_bg, isolated_tract), frozen_products))
  cat("Passed: full operational chunk sequences exactly match the frozen notebook and helpers.\n")
}
cat("Passed: both notebooks execute independently using only their declared synthetic inputs.\n")

# Parse all chunks, preserve unique labels, and check overview/section agreement.
for (file in c("R/assemble_helpers.R", "R/geography_qa.R")) invisible(parse(file = here::here(file)))
for (notebook in c(bg_notebook, tract_notebook)) {
  lines <- readLines(here::here(notebook), warn = FALSE)
  starts <- which(startsWith(lines, "```{r"))
  labels <- sub("^```\\{r ([^,}]+).*", "\\1", lines[starts])
  stopifnot(!anyDuplicated(labels))
  prose <- lines
  for (start in starts) {
    end <- which(seq_along(lines) > start & lines == "```")[1]
    parse(text = lines[seq.int(start + 1L, end - 1L)])
    prose[start:end] <- ""
  }
  headings <- prose[grepl("^# [0-9]+\\.", prose)]
  stopifnot(identical(sub("^# ([0-9]+)\\..*", "\\1", headings),
                      as.character(seq_along(headings))),
            all(sub("^# ", "", headings) %in% prose))
  for (section in seq_along(headings)) {
    subsections <- prose[grepl(paste0("^## ", section, "\\."), prose)]
    stopifnot(identical(sub(paste0("^## ", section, "\\.([0-9]+).*"), "\\1", subsections),
                        as.character(seq_along(subsections))))
  }
}
cat("Passed: notebook joins, unchanged unrelated measures/allocations, and synthetic Feather validation.\n")

# Fixed vintage allowlists never authorize unrelated schema or value changes.
parity <- function(current, previous = current, migration = NULL, ...) {
  quiet(compare_socal_parity(current, previous, "037", schema_migration = migration, ...))
}
removed_measures <- c("rentmv1yr", "rentmv5yr", "rentyrblt", "rentyrblt_14_16",
                      "rentyrblt_10_13", "rentyrblt_00_09", "rentyrblt_90_99")
removed_columns <- as.vector(outer(removed_measures, c("E", "M"), paste0))
previous_16 <- without_16$acs_16 |> select(-vac_rentedE, -vac_rentedM)
for (column in c(removed_columns, "rhu_lrE", "rhu_lr2E")) previous_16[[column]] <- 1
current_16 <- with_16$acs_16
current_24 <- with_24$acs_2024_bg_aggregated_interp
previous_24 <- without_24$acs_2024_bg_aggregated_interp
cleanup_bg <- c("rhu_lrE", "rhu_lr2E", "rentE", "rentM", "rentCV", "lqcrentE", "lqcrentM",
                "med_hvalE", "med_hvalM", "med_hvalCV", "hu_miss_hval", "pct_miss_hval")
for (column in cleanup_bg) previous_24[[column]] <- 1
stopifnot(!any(cleanup_bg %in% names(current_24)),
          all(c("med_hhincE", "med_hhincM", "med_hhincCV", "interp_rent") %in% names(current_24)))
expect_error(parity(current_16, previous_16), "output column names, order, or types differ")
expect_error(parity(current_24, previous_24), "output column names, order, or types differ")
audit_16 <- parity(current_16, previous_16, "2016")
audit_24 <- parity(current_24, previous_24, "2024")
stopifnot(nrow(audit_16$differences) == 0L, nrow(audit_24$differences) == 0L,
          setequal(filter(audit_16$schema_changes, change == "added")$variable,
                   c("vac_rentedE", "vac_rentedM", "rhu_inventoryE")),
          setequal(filter(audit_16$schema_changes, change == "removed")$variable,
                   c(removed_columns, "rhu_lrE", "rhu_lr2E")),
          identical(filter(audit_24$schema_changes, change == "added")$variable, "rhu_inventoryE"),
          setequal(filter(audit_24$schema_changes, change == "removed")$variable, cleanup_bg),
          nrow(parity(current_16, migration = "2016")$schema_changes) == 0L,
          nrow(parity(current_16)$schema_changes) == 0L)
expect_error(parity(current_16, previous_16, "2024"), "retired fields")
expect_error(parity(current_24, previous_24, "unknown"), "schema_migration must be")
expect_error(parity(mutate(current_24, rhu_inventoryE = "115"), previous_24, "2024"), "must be numeric")
expect_error(parity(select(current_16, -vac_rentedE), current_16, "2016"), "unapproved schema")
expect_error(parity(mutate(current_16, rentmv1yrE = 1), previous_16, "2016"), "estimate/MOE pairs")
for (vintage in c("2016", "2024")) {
  candidate <- if (vintage == "2016") current_16 else current_24
  reference <- if (vintage == "2016") previous_16 else previous_24
  expect_error(parity(mutate(candidate, unexpected = 1), reference, vintage), "unapproved schema")
  expect_error(parity(select(candidate, -med_hhincM), reference, vintage), "unapproved schema")
  expect_error(parity(select(candidate, rhuE, everything()), reference, vintage), "order, or types differ")
  expect_error(parity(mutate(candidate, rhuE = as.integer(rhuE)), reference, vintage), "order, or types differ")
  expect_error(parity(mutate(candidate, rhuE = rhuE + 1), reference, vintage), "parity failed")
  expect_error(parity(bind_rows(candidate, candidate[1, ]), reference, vintage), "missing or duplicate key")
  expect_error(parity(candidate[-1, ], reference, vintage), "parity failed")
  expect_error(parity(mutate(candidate, rhu_inventoryE = 0), candidate, vintage), "parity failed")
}

# Native 2024 permits only low-rent removals, never removal of native dollar estimates.
old_native <- mutate(native_out, rhu_lrE = 70, rhu_lr2E = 90)
native_cleanup <- parity(native_out, old_native, "2024_tract", key = "tr2020_id")
stopifnot(setequal(native_cleanup$schema_changes$variable, c("rhu_lrE", "rhu_lr2E")),
          nrow(native_cleanup$differences) == 0L)
for (column in c("rentE", "rentM", "rentCV", "lqcrentE", "lqcrentM",
                 "med_hvalE", "med_hvalM", "med_hvalCV", "med_hhincE")) {
  expect_error(parity(select(native_out, -all_of(column)), old_native, "2024_tract",
                      key = "tr2020_id"), "unapproved schema")
}
for (column in cleanup_bg) {
  retired <- current_24
  retired[[column]] <- 1
  expect_error(parity(retired, previous_24, "2024"), "retired fields")
  expect_error(parity(retired, NULL, "2024"), "retired fields")
}
expect_error(parity(select(current_24, -med_hhincE), previous_24, "2024"), "unapproved schema")
expect_error(parity(select(current_24, -interp_rent), previous_24, "2024"), "unapproved schema")

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
for (vintage in c("2016", "2024", "2024_tract")) {
  candidate <- switch(vintage, `2016` = current_16, `2024` = current_24, `2024_tract` = native_out)
  output <- capture.output(unchecked <- compare_socal_parity(
    candidate, NULL, "037", schema_migration = vintage
  ))
  stopifnot(is.null(unchecked), any(grepl("PARITY NOT CHECKED", output, fixed = TRUE)))
}
expect_error(assert_same_schema(current_24, previous_24, "Strict reload"), "order, or types differ")
cat("Passed: strict/default parity, narrow schema migration, income/boundary rules, and missing references.\n")

# Exercise Step 1's actual source mapping and reduced schema without an API call.
step1_lines <- readLines(here::here("01_acs.Rmd"))
step1_chunk <- function(label, env) {
  start <- match(paste0("```{r ", label, "}"), step1_lines)
  stopifnot(!is.na(start))
  end <- which(seq_along(step1_lines) > start & step1_lines == "```")[1]
  quiet(eval(parse(text = step1_lines[seq.int(start + 1L, end - 1L)]), env))
}
step1 <- new.env(parent = environment())
step1_chunk("configure-block-group-exclusions", step1)
step1_chunk("specify-variables", step1)
source_schema <- function(variables, key, id) {
  x <- tibble(!!key := id, NAME = "Synthetic ACS geography", rent_id = TRUE)
  aliases <- names(variables)[!duplicated(variables)]
  for (column in as.vector(outer(aliases, c("E", "M"), paste0))) x[[column]] <- 10
  list(data = x, keys = key, variables = variables, flag = "rent_id")
}
step1$output_checks <- list(
  tract_2016 = source_schema(step1$tract_vars, "tr2010_id", "06037000100"),
  bg_2024 = source_schema(step1$block_group_vars, "bg2020_id", "060370001001"),
  tract_2024 = source_schema(step1$tract_vars, "tr2020_id", "06037000100")
)
step1_chunk("validate-columns", step1)
for (product in names(step1$output_checks)) {
  original <- step1$output_checks[[product]]$data
  stopifnot(all(paste0("grentcat", 1:24, "E") %in% names(original)),
            all(c("rentE", "lqcrentE", "med_hvalE", "med_hhincE") %in% names(original)))
  for (column in c("rhu_lrE", "rhu_lr2E")) {
    step1$output_checks[[product]]$data[[column]] <- 1
    expect_error(step1_chunk("validate-columns", step1), "Excluded columns present")
    step1$output_checks[[product]]$data <- original
  }
  step1$output_checks[[product]]$data <- select(original, -grentcat1E)
  expect_error(step1_chunk("validate-columns", step1), "Required columns missing")
  step1$output_checks[[product]]$data <- original
}
cat("Passed: Step 1 mapping/bin contract and retired-field rejection; older Step 2 inputs lose only low-rent columns.\n")

}
