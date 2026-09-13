# Run from the repository root: Rscript --vanilla tests/test_merge_diagnostics.R
# Synthetic inputs and temporary Feathers only; never reads canonical data.
suppressPackageStartupMessages({
  library(here)
  library(dplyr)
  library(tidyr)
  library(purrr)
  library(stringr)
  library(arrow)
  library(matrixStats)
})
source(here::here("R", "merge_helpers.R"))
source(here::here("R", "geography_qa.R"))
source(here::here("R", "merge_diagnostics.R"))

quiet <- function(expr) {
  invisible(capture.output(value <- force(expr)))
  invisible(value)
}
expect_error <- function(expr, message) {
  error <- tryCatch({ quiet(expr); NULL }, error = identity)
  stopifnot(inherits(error, "error"), grepl(message, conditionMessage(error), fixed = TRUE))
}
notebook_chunk <- function(label, file = "04_merge.Rmd") {
  lines <- readLines(here::here(file), warn = FALSE)
  start <- which(grepl(paste0("^```\\{r ", label, "([,}])"), lines))
  stopifnot(length(start) == 1L)
  end <- which(seq_along(lines) > start & lines == "```")[1]
  parse(text = lines[seq.int(start + 1L, end - 1L)])
}
tract_id <- function(number) sprintf("06037%06d", number)

# Consistent pairs may have different GEOIDs; equal IDs may be changed.
xwalk <- tibble(
  tr2020_id = tract_id(c(101, 2, 3, 103, 4, 5, 6)),
  tr2010_id = c(tract_id(c(1, 2, 3, 3)), NA_character_, NA_character_, tract_id(6)),
  geo_consistent = c(1, 0, 0, 0, 0, 0, 1),
  relationship_class = c("consistent", "one_to_one_changed", "split", "split",
                         "merge", "many_to_many", "consistent"),
  same_geoid = c(0, 1, 1, 0, NA_real_, NA_real_, 1),
  n_2010_partners = c(1L, 1L, 1L, 1L, 2L, 2L, 1L),
  n_2020_partners = c(1L, 1L, 2L, 2L, NA_integer_, NA_integer_, 1L)
)
xwalk_before <- xwalk
links <- quiet(prepare_merge_geography(xwalk))
stopifnot(identical(xwalk, xwalk_before), nrow(links$statuses) == 4L,
          identical(links$consistent$tr2020_id, tract_id(c(101, 6))))
panel <- tibble(tr2010_id = tract_id(1:7), canonical = as.double(1:7))
panel_before <- panel
joined <- quiet(merge_diagnostic_left_join(panel, links$statuses, "tr2010_id", "Statuses"))
joined <- quiet(merge_diagnostic_left_join(joined, links$consistent, "tr2010_id", "Links"))
native <- tibble(tr2020_id = xwalk$tr2020_id, rentE_24_tract = as.double(101:107))
joined <- quiet(merge_diagnostic_left_join(joined, native, "tr2020_id", "Census values"))
stopifnot(identical(panel, panel_before), identical(joined$tr2010_id, panel$tr2010_id),
          joined$rentE_24_tract[1] == 101, is.na(joined$rentE_24_tract[2]),
          all(is.na(joined$rentE_24_tract[c(3, 4, 5, 7)])),
          joined$geo_consistent[3] == 0, all(is.na(joined$geo_consistent[c(4, 5, 7)])))
geo_summary <- summarize_merge_geography(joined, "Synthetic 2010 panel")
stopifnot(sum(geo_summary$classes$n_tracts) == 7,
          geo_summary$status$n_tracts[geo_summary$status$geo_status == "status_missing"] == 3,
          sum(geo_summary$status$share) == 1)
expect_error(prepare_merge_geography(bind_rows(xwalk, xwalk[1, ])), "duplicate key")
expect_error(prepare_merge_geography(mutate(xwalk, geo_consistent = as.character(geo_consistent))), "encoding")
expect_error(prepare_merge_geography(mutate(xwalk, geo_consistent = replace(geo_consistent, 1, NA))), "encoding")
expect_error(prepare_merge_geography(mutate(xwalk, relationship_class = replace(relationship_class, 1, "near_match"))), "encoding")
expect_error(prepare_merge_geography(mutate(xwalk, tr2010_id = replace(tr2010_id, 2, tract_id(1)))), "same_geoid")
conflicting <- xwalk |>
  mutate(tr2010_id = replace(tr2010_id, 2, tract_id(1)), same_geoid = replace(same_geoid, 2, 0))
expect_error(prepare_merge_geography(conflicting), "duplicate key")
expect_error(merge_diagnostic_left_join(panel, bind_rows(links$statuses, links$statuses[1, ]),
                                      "tr2010_id", "Duplicate status"), "duplicate key")
expect_error(merge_diagnostic_left_join(panel, panel, "tr2010_id", "Overlap"), "explicitly name")

# Missing counts always include unpaired observations; zeros remain paired.
observations <- tibble(tr2010_id = tract_id(1:6),
                       x = c(20, NA, 0, 8, 5, NaN), y = c(10, 5, 0, NA, 10, NA_real_),
                       geo_status = c("consistent", "consistent", "consistent",
                                      "not_consistent", "not_consistent", NA_character_))
comparison <- compare_diagnostic_measures(observations, "x", "y", "geo_status",
                                           c("consistent", "not_consistent"))
overall <- filter(comparison$coverage, group == "overall")
stopifnot(overall$n_total == 6, overall$n_x_missing == 2, overall$n_y_missing == 2,
          overall$n_paired == 3, overall$n_ratio == 2, overall$n_x_below_y == 1,
          overall$share_x_below_y == 1/3, overall$n_paired_nonpositive_denominator == 1,
          isTRUE(all.equal(comparison$values$difference, c(10, NA_real_, 0, NA_real_, -5, NA_real_))),
          identical(comparison$values$ratio, c(2, NA_real_, NA_real_, NA_real_, 0.5, NA_real_)))
stopifnot(sum(comparison$coverage$n_total[-1]) == overall$n_total,
          isTRUE(all.equal(overall$correlation, cor(c(20, 0, 5), c(10, 0, 10)))))
constant <- compare_diagnostic_measures(tibble(x = c(1, 1), y = c(2, 3)), "x", "y")
stopifnot(is.na(constant$coverage$correlation))
empty <- compare_diagnostic_measures(observations[FALSE, ], "x", "y", "geo_status",
                                     c("consistent", "not_consistent"))
stopifnot(nrow(empty$coverage) == 4, all(empty$coverage$n_total == 0),
          all(is.na(empty$coverage$correlation)), all(is.na(empty$coverage$share_x_below_y)),
          all(is.na(select(empty$summaries, mean, sd, min, p25, median, p75, max))))
missing <- diagnostic_summary(c(NA_real_, NaN))
stopifnot(missing$n_missing == 2, is.na(missing$mean), is.na(missing$min), is.na(missing$max))
stopifnot(identical(diagnostic_ratio(c(2, 2, 2, NA, 0), c(1, 0, -1, 1, 1)),
                    c(2, NA_real_, NA_real_, NA_real_, 0)))
expect_error(diagnostic_summary(c(1, Inf)), "finite")

# Exercise actual notebook chunks using all configured counties and temporary
# inputs, including a baseline-only tract and a block-group-only tract.
county_env <- new.env(parent = globalenv())
eval(notebook_chunk("set-paths", "02_assemble.Rmd"), county_env)
base_ids <- paste0("06", county_env$target_counties, "000100")
ids_16 <- c(base_ids, tract_id(901))
ids_bg <- c(base_ids, tract_id(902))
native_ids <- c(paste0(substr(base_ids[1], 1, 5), "000200"), base_ids[-1], tract_id(902))

# Field lists follow schemas/acs_full.md; input flags/tags follow Step 2 schemas.
estimates <- c("rentE", "lqcrentE", "popE", "huE", "rhuE", "med_hvalE",
               "rhu_lrE", "rhu_lr2E", "med_hhincE", "pctrhuE", "pctvacE", "pctblkE",
               "pcthspE", "pctaaE", "pctsfdE", "mf5E", "nsfaE", "pctrvacE", "pctsvacE")
moes <- c("rentM", "lqcrentM", "popM", "huM", "rhuM", "med_hvalM", "med_hhincM",
           "pctrhuM", "pctblkM", "pcthspM")
cvs <- c("rentCV", "popCV", "huCV", "rhuCV", "med_hvalCV", "med_hhincCV",
          "pctrhuCV", "pctblkCV", "pcthspCV")
make_input <- function(ids, key, bg = FALSE) {
  x <- tibble(!!key := ids)
  for (column in estimates) x[[column]] <- as.double(seq_along(ids) * 10)
  for (column in moes) x[[column]] <- rep(2, length(ids))
  for (column in cvs) x[[column]] <- rep(0.1, length(ids))
  for (column in estimates[startsWith(estimates, "pct")]) x[[column]] <- rep(0.2, length(ids))
  x$rhu_inventoryE <- x$rhuE + 5
  if (bg) {
    x <- mutate(x, rhu_id = TRUE, left_id = TRUE, right_id = TRUE,
                 pct_miss_rent = 0, pct_tc_rent = 0, pct_miss_hval = 0,
                 tc_flag_rent_24 = 0, interp_rent = rentE * 1.05)
  } else {
    x <- mutate(x, rent_id = TRUE, m_flag_rent = 0, m_flag_lqcrent = 0,
                 m_flag_rhu = 0, m_flag_med_hval = 0, zero_flag_rhu = 0,
                 tc_flag_rent = 0, tc_flag_lqcrent = 0, tc_flag_med_hval = 0)
  }
  x
}
source_16 <- make_input(ids_16, "tr2010_id")
source_bg <- make_input(ids_bg, "tr2010_id", bg = TRUE)
source_tract <- make_input(native_ids, "tr2020_id")
source_16$rentE[c(2, 3)] <- c(0, NA_real_)
source_16$rhuE[4] <- 0
source_16$rhu_inventoryE[5] <- 0
source_tract$rentE[6] <- NA_real_
source_tract$rentE[7] <- NA_real_
# Retain county coverage while leaving one consistent crosswalk key absent.
source_tract$tr2020_id[6] <- paste0(substr(native_ids[6], 1, 5), "000300")
source_bg$rhu_inventoryE[7] <- NA_real_
source_tract$rhu_inventoryE[8] <- NA_real_
source_bg$rhu_inventoryE[9] <- source_bg$rhuE[9] - 1
notebook_xwalk <- tibble(tr2020_id = native_ids, tr2010_id = ids_bg,
                         geo_consistent = 1, relationship_class = "consistent",
                         same_geoid = as.double(native_ids == ids_bg),
                         n_2010_partners = 1L, n_2020_partners = 1L)
notebook_xwalk$geo_consistent[2] <- 0
notebook_xwalk$relationship_class[2] <- "one_to_one_changed"
tmp_dir <- tempfile("acs-merge-diagnostics-")
dir.create(tmp_dir)
write_feather(source_16, file.path(tmp_dir, "acs_step2_2016_tract.feather"))
write_feather(source_bg, file.path(tmp_dir, "acs_step2_2024_block_group_aggregated.feather"))
write_feather(source_tract, file.path(tmp_dir, "acs_step2_2024_tract.feather"))
write_feather(notebook_xwalk, file.path(tmp_dir, "xwalk_tr20_tr10.feather"))
env <- new.env(parent = globalenv())
env$data_dir <- tmp_dir
env$write_panel <- FALSE
env$prior_panel <- NULL
run_chunk <- function(label) quiet(eval(notebook_chunk(label), env))
for (label in c("prep-24-bg-agg", "prep-24-tract", "prep-16", "merge-surveys", "change-vars")) run_chunk(label)
canonical_before <- env$acs_full
canonical_names <- names(canonical_before)
stopifnot(nrow(canonical_before) == length(union(ids_16, ids_bg)),
          isTRUE(all.equal(env$acs_16_diagnostic$rentE_16, source_16$rentE * 1.307)),
          isTRUE(all.equal(canonical_before$rentPOST[1], 1/1.307)),
          canonical_before$rhuPOST[1] == 1,
          is.na(canonical_before$rentPOST[2]), is.na(canonical_before$rentPOST[3]),
          is.na(canonical_before$rhuPOST[4]))
for (label in c("summarize-cv", "load-geography", "build-diagnostic-panel", "geography-coverage",
                "compare-source-levels", "diagnostic-change-vars", "compare-inventory-levels",
                "compare-inventory-changes", "validation-panel", "validate-keys-panel",
                "validate-missingness-panel", "validate-flags-panel", "validate-numeric-panel")) run_chunk(label)
stopifnot(identical(env$acs_full, canonical_before),
          identical(select(env$acs_diagnostics, all_of(canonical_names)), canonical_before),
          !any(grepl("\\.[xy]$|^diag_|rhu_inventory|geo_consistent|tr2020_id", canonical_names)),
          nrow(env$acs_diagnostics) == 16,
          env$source_level_diagnostics$rent$coverage$n_total[1] == 16,
          env$inventory_level_diagnostics$tract_2024$coverage$n_total == 15,
          env$inventory_level_diagnostics$bg_agg_2024$coverage$n_x_below_y == 1,
          env$alignment_coverage$n_consistent_link_without_census[1] == 1,
          env$alignment_coverage$n_census_rent_missing_in_record[1] == 1,
          nrow(env$geography_unmatched$census_without_crosswalk) == 1,
          is.na(env$acs_diagnostics$diag_rentPOST_24_tract[2]),
          is.na(env$acs_diagnostics$diag_rhu_inventoryPOST_24_bg_agg[5]))

# Run the actual disabled-save/reload chunks with no prior file, then with an
# unreadable stale file. Neither case may read, create, or overwrite the panel.
run_chunk("save-panel")
run_chunk("reload-panel")
saved_path <- file.path(tmp_dir, "acs_full.feather")
stopifnot(!file.exists(saved_path), !env$panel_written,
          !exists("acs_saved", envir = env, inherits = FALSE), identical(env$acs_out, canonical_before))
writeLines("stale reference sentinel", saved_path)
sentinel_md5 <- tools::md5sum(saved_path)
run_chunk("save-panel")
run_chunk("reload-panel")
stopifnot(identical(tools::md5sum(saved_path), sentinel_md5),
          !exists("acs_saved", envir = env, inherits = FALSE))

# The explicitly enabled branch keeps schema protection and round-trips only
# canonical columns in the temporary test directory.
env$write_panel <- TRUE
env$prior_panel <- mutate(canonical_before, unexpected = 1)
expect_error(eval(notebook_chunk("save-panel"), env), "schema")
stopifnot(identical(tools::md5sum(saved_path), sentinel_md5), !env$panel_written)
env$prior_panel <- canonical_before
run_chunk("save-panel")
run_chunk("reload-panel")
stopifnot(env$panel_written, isTRUE(all.equal(env$acs_saved, canonical_before)))

# Parse every executable chunk; verify the checked-in default and heading order.
lines <- readLines(here::here("04_merge.Rmd"), warn = FALSE)
starts <- which(grepl("^```\\{r", lines))
for (start in starts) {
  end <- which(seq_along(lines) > start & lines == "```")[1]
  parse(text = lines[seq.int(start + 1L, end - 1L)])
}
stopifnot(any(lines == "write_panel <- FALSE"),
          identical(sub("^# ([0-9]+)\\..*", "\\1", lines[grepl("^# [0-9]+\\.", lines)]), as.character(1:7)))
cat("Merge diagnostics tests passed: geography, coverage, ratios, canonical preservation, and guarded save/reload.\n")
