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
unknown <- mutate(xwalk, geo_consistent = replace(geo_consistent, c(1, 2), c(NA_real_, 2)))
unknown_links <- quiet(prepare_merge_geography(unknown))
stopifnot(nrow(unknown_links$statuses) == nrow(links$statuses),
          nrow(unknown_links$consistent) == 1,
          is.na(unknown_links$statuses$geo_consistent[1]),
          unknown_links$statuses$geo_consistent[2] == 2)
unknown_class <- mutate(xwalk, relationship_class = replace(relationship_class, 1, "near_match"))
stopifnot(nrow(quiet(prepare_merge_geography(unknown_class))$consistent) == 2,
          summarize_merge_geography(unknown_class, "Unexpected")$classes$n_tracts[7] == 1)
expect_error(prepare_merge_geography(mutate(xwalk, geo_consistent = replace(geo_consistent, 1, 0))),
             "contradictory")
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
ids_16 <- c(base_ids, tract_id(c(901, 903, 904)))
ids_bg <- c(base_ids, tract_id(902))
native_ids <- c(paste0(substr(base_ids[1], 1, 5), "000200"), base_ids[-1], tract_id(c(902, 901, 905, 904)))
linked_ids <- c(ids_bg, tract_id(c(901, 905, 904)))

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
                 m_flag_rhu = 0, m_flag_med_hval = 0, zero_flag_rhu = 0, zero_flag_med_hval = 0,
                 tc_flag_rent = 0, tc_flag_lqcrent = 0, tc_flag_med_hval = 0)
  }
  x
}

# Independent selector exercise supplies both alternatives even on changed rows.
# This tests no fallback in both directions without inventing geographic links.
small <- tibble(tr2010_id = tract_id(1:8), geo_consistent = c(1, 0, NA, 2, 1, 0, 1, 0))
a <- prepare_2024_source(make_input(tract_id(1:8), "tr2020_id"), "tract")
b <- prepare_2024_source(make_input(tract_id(1:8), "tr2010_id", bg = TRUE), "bg_agg")
a$rentE_24_tract <- c(30, 30, 30, 30, NA, 30, 30, 30)
b$rentE_24_bg_agg <- c(20, 20, 20, 20, 20, NaN, 20, 20)
a$rhu_inventoryE_24_tract <- a$rentE_24_tract + 5
b$rhu_inventoryE_24_bg_agg <- b$rentE_24_bg_agg + 5
a$rentM_24_tract <- c(rep(40, 6), NA, 40)
b$rentM_24_bg_agg <- c(rep(20, 7), NA)
a$tc_flag_rent_24_tract[7] <- NA_real_
b$tc_flag_rent_24_bg_agg[8] <- NA_real_
small <- bind_cols(small, select(a, -tr2020_id), select(b, -tr2010_id))
selected <- select_canonical_2024(small)
stopifnot(identical(selected$rentE_24, c(30, 20, NA, NA, NA, NaN, 30, 20)),
          identical(selected$acs_source_24, c("tract", "bg_agg", NA, NA, "tract", "bg_agg", "tract", "bg_agg")),
          all(is.na(selected$rentM_24[7:8])), all(is.na(selected$tc_flag_rent_24[7:8])))
equality <- assert_hierarchical_2024(selected)
stopifnot(all(equality$n_mismatch == 0),
          all(filter(equality, measure == "rentE_24")$n_alternative_available_when_selected_missing == 1))
expect_error(assert_hierarchical_2024(mutate(selected, rentE_24 = coalesce(rentE_24, rentE_24_bg_agg))),
             "violates")
expect_error(assert_hierarchical_2024(mutate(selected, rentE_24 = replace(rentE_24, 5, 20))), "violates")
expect_error(assert_hierarchical_2024(mutate(selected, rentE_24 = replace(rentE_24, 6, 30))), "violates")
expect_error(assert_hierarchical_2024(mutate(selected, rentM_24 = rentM_24_bg_agg)), "violates")
expect_error(assert_hierarchical_2024(mutate(selected, acs_source_24 = "tract")), "selected source")
stopifnot(nrow(assert_hierarchical_2024(select_canonical_2024(small[FALSE, ]))) == 2 * nrow(merge_2024_field_map()))
expect_error(prepare_2024_source(select(make_input(tract_id(1), "tr2020_id"), -rentM)), "missing bundle")

source_16 <- make_input(ids_16, "tr2010_id")
source_bg <- make_input(ids_bg, "tr2010_id", bg = TRUE) |>
  mutate(across(all_of(c(estimates, "rhu_inventoryE")), ~ .x * 2),
         across(all_of(moes), ~ .x * 10), across(all_of(cvs), ~ .x * 2),
         pct_miss_rent = 0.2, pct_tc_rent = 0.1, pct_miss_hval = 0.3, tc_flag_rent_24 = 1)
source_tract <- make_input(native_ids, "tr2020_id") |>
  mutate(across(all_of(c(estimates, "rhu_inventoryE")), ~ .x * 3),
         across(all_of(moes), ~ .x * 20), across(all_of(cvs), ~ .x * 3))
source_16$rentE[c(2, 3)] <- c(0, NA_real_)
source_16$rhuE[4] <- 0
source_16$rhu_inventoryE[5] <- 0
source_tract$tr2020_id[6] <- paste0(substr(native_ids[6], 1, 5), "000300")
source_tract$rentE[c(7, 14)] <- NA_real_
source_tract$m_flag_rent[c(7, 14)] <- 1
source_tract$rentCV[c(7, 14)] <- NA_real_
source_tract$tc_flag_rent[14] <- 1
source_tract$rentM[12] <- NA_real_
source_tract$rentCV[12] <- NA_real_
source_tract$rhu_inventoryE[9] <- NA_real_
source_bg$rhu_inventoryE[c(7, 8)] <- NA_real_
source_bg$rhu_inventoryE[9] <- source_bg$rhuE[9] - 1
source_bg$rentE[13] <- NA_real_
source_bg$rentCV[13] <- NA_real_
notebook_xwalk <- tibble(tr2020_id = native_ids, tr2010_id = linked_ids,
                         geo_consistent = 1, relationship_class = "consistent",
                         same_geoid = as.double(native_ids == linked_ids),
                         n_2010_partners = 1L, n_2020_partners = 1L)
changed <- c(2, 4, 8, 11, 13, 15, 18)
notebook_xwalk$geo_consistent[changed] <- 0
notebook_xwalk$relationship_class[changed] <- "one_to_one_changed"
notebook_xwalk$geo_consistent[10] <- NA_real_
notebook_xwalk$geo_consistent[11] <- 2
notebook_xwalk$relationship_class[12] <- "unexpected_class"
tmp_dir <- tempfile("acs-merge-hierarchy-")
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
for (label in c("prep-24-bg-agg", "prep-24-tract", "prep-16", "load-geography",
                "merge-surveys", "build-diagnostic-panel", "select-canonical-24", "change-vars")) run_chunk(label)
canonical_before <- env$acs_full
canonical_names <- names(canonical_before)
row_901 <- match(tract_id(901), canonical_before$tr2010_id)
row_903 <- match(tract_id(903), canonical_before$tr2010_id)
row_904 <- match(tract_id(904), canonical_before$tr2010_id)
row_902 <- match(tract_id(902), canonical_before$tr2010_id)
stopifnot(nrow(canonical_before) == length(union(ids_16, ids_bg)),
          isTRUE(all.equal(env$acs_16_diagnostic$rentE_16, source_16$rentE * 1.307)),
          isTRUE(all.equal(canonical_before$rentPOST[1], 3/1.307)),
          canonical_before$rhuPOST[1] == 3, canonical_before$rhuPOST[2] == 2,
          canonical_before$rhu_inventoryPOST[1] == 3,
          is.na(canonical_before$rentPOST[2]), is.na(canonical_before$rentPOST[3]),
          is.na(canonical_before$rhuPOST[4]), is.na(canonical_before$rhu_inventoryPOST[5]),
          is.na(canonical_before$rentE_24[6]), is.na(canonical_before$rentE_24[7]),
          is.na(canonical_before$rhu_inventoryE_24[8]), is.na(canonical_before$rhu_inventoryE_24[9]),
          all(is.na(canonical_before$rentE_24[10:11])),
          canonical_before$acs_source_24[12] == "tract", is.na(canonical_before$rentM_24[12]),
          is.na(canonical_before$rentPOSTCV[12]), is.na(canonical_before$rentE_24[13]),
          canonical_before$m_flag_rent_24[13] == 1,
          canonical_before$tc_flag_rent_24[1] == 0, canonical_before$tc_flag_rent_24[2] == 1,
          canonical_before$tc_flag_rent_24[14] == 1, is.na(canonical_before$rentE_24[14]),
          is.na(canonical_before$tc_flag_lqcrent_24[2]),
          is.na(canonical_before$post_id[row_901]), !is.na(canonical_before$rentPOST[row_901]),
          is.na(canonical_before$acs_source_24[row_903]),
          canonical_before$acs_source_24[row_904] == "bg_agg", is.na(canonical_before$rentE_24[row_904]),
          is.na(canonical_before$rhu_inventoryPOST[row_902]),
          !tract_id(905) %in% canonical_before$tr2010_id,
          !any(grepl("inventory.*(M_|CV|POSTCV)", canonical_names)))
# Shares use raw differences (not ratios or a multiplier of 100).
for (measure in c("pctrhu", "pctvac", "pctrvac", "pctsvac")) {
  stopifnot(isTRUE(all.equal(canonical_before[[paste0(measure, "PPC")]][1:2], c(0.4, 0.2))))
}
for (measure in c("rent", "rhu", "med_hhinc")) {
  e16 <- canonical_before[[paste0(measure, "E_16")]][1]
  m16 <- canonical_before[[paste0(measure, "M_16")]][1]
  ratio <- canonical_before[[paste0(measure, "POST")]][1]
  expected_moe <- sqrt(max(0, 40^2 - ratio^2 * m16^2)) / e16
  stopifnot(isTRUE(all.equal(canonical_before[[paste0("moe_", measure, "POST")]][1], expected_moe)),
            isTRUE(all.equal(canonical_before[[paste0(measure, "POSTCV")]][1], expected_moe/1.645/ratio)))
}
bg_rows <- match(canonical_before$tr2010_id, source_bg$tr2010_id)
for (column in c("pct_miss_rent", "pct_tc_rent", "pct_miss_hval", "interp_rent")) {
  stopifnot(identical(canonical_before[[column]], source_bg[[column]][bg_rows]))
}
for (label in c("summarize-cv", "geography-coverage", "source-selection-qa",
                "compare-source-levels", "diagnostic-change-vars", "compare-inventory-levels",
                "compare-inventory-changes", "validation-panel", "validate-keys-panel",
                "validate-missingness-panel", "validate-flags-panel", "validate-numeric-panel")) run_chunk(label)
stopifnot(identical(env$acs_full, canonical_before),
          identical(select(env$acs_diagnostics, all_of(canonical_names)), canonical_before),
          !any(grepl("\\.[xy]$|^diag_|_24_tract$|_24_bg_agg$|^in_|^same_geoid$", canonical_names)),
          env$source_level_diagnostics$rent$coverage$n_total[1] == nrow(canonical_before),
          env$inventory_level_diagnostics$tract_2024$coverage$n_total == nrow(source_tract),
          env$inventory_level_diagnostics$bg_agg_2024$coverage$n_x_below_y == 1,
          env$alignment_coverage$n_consistent_link_without_census[1] == 1,
          sum(env$source_selection_qa$counts$n_tracts) == nrow(canonical_before),
          isTRUE(all.equal(sum(env$source_selection_qa$counts$share), 1)),
          env$source_selection_qa$geography$status$n_tracts[4] == 1,
          all(env$hierarchy_equality$n_mismatch == 0))

# Disabled writes must not read/create/replace the canonical destination.
run_chunk("save-panel")
run_chunk("reload-panel")
saved_path <- file.path(tmp_dir, "acs_full.feather")
stopifnot(!file.exists(saved_path), !env$panel_written,
          !exists("acs_saved", envir = env, inherits = FALSE), identical(env$acs_out, canonical_before))
writeLines("stale reference sentinel", saved_path)
sentinel_md5 <- tools::md5sum(saved_path)
run_chunk("save-panel")
run_chunk("reload-panel")
stopifnot(identical(tools::md5sum(saved_path), sentinel_md5))

# Fixed migration allowlist, strict shared order/types, and temporary round trips.
legacy <- select(canonical_before, -all_of(panel_schema_additions()))
quiet(assert_panel_schema(canonical_before, legacy))
quiet(assert_panel_schema(canonical_before, canonical_before))
expect_error(assert_panel_schema(mutate(canonical_before, unexpected = 1), legacy), "unapproved")
expect_error(assert_panel_schema(select(canonical_before, -rentE_16), legacy), "unapproved")
expect_error(assert_panel_schema(mutate(canonical_before, rentE_16 = as.integer(rentE_16)), legacy), "types")
expect_error(assert_panel_schema(select(canonical_before, rentE_16, everything()), legacy), "order")
expect_error(assert_panel_schema(mutate(canonical_before, m_flag_rhu_inventoryPOST = TRUE)), "storage")
env$write_panel <- TRUE
env$prior_panel <- mutate(legacy, unexpected = 1)
expect_error(eval(notebook_chunk("save-panel"), env), "schema")
stopifnot(identical(tools::md5sum(saved_path), sentinel_md5), !env$panel_written)
env$prior_panel <- legacy
run_chunk("save-panel")
run_chunk("reload-panel")
stopifnot(env$panel_written, isTRUE(all.equal(env$acs_saved, canonical_before)))
env$prior_panel <- env$acs_saved
run_chunk("save-panel")
run_chunk("reload-panel")
env$prior_panel <- NULL
run_chunk("save-panel")
run_chunk("reload-panel")

# Parse actual chunks and check all section numbering and overview titles.
lines <- readLines(here::here("04_merge.Rmd"), warn = FALSE)
starts <- which(startsWith(lines, "```{r"))
for (start in starts) {
  end <- which(seq_along(lines) > start & lines == "```")[1]
  parse(text = lines[seq.int(start + 1L, end - 1L)])
}
headings <- lines[grepl("^# [0-9]+\\.", lines)]
stopifnot(any(lines == "write_panel <- FALSE"),
          identical(sub("^# ([0-9]+)\\..*", "\\1", headings), as.character(1:7)),
          all(sub("^# ", "", headings) %in% lines))
for (section in 1:7) {
  subsections <- lines[grepl(paste0("^## ", section, "\\."), lines)]
  numbers <- sub(paste0("^## ", section, "\\.([0-9]+).*"), "\\1", subsections)
  stopifnot(identical(numbers, as.character(seq_along(subsections))))
}
cat("Merge tests passed: hierarchical bundles, source-aware changes, inventory, geography, diagnostics, and guarded migration/save/reload.\n")
