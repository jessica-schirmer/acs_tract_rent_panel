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
source(here::here("R", "rent_metadata.R"))
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
eval(notebook_chunk("set-paths", "02a_aggregate_2024_block_groups.Rmd"), county_env)
base_ids <- paste0("06", county_env$target_counties, "000100")
ids_16 <- c(base_ids, tract_id(c(901, 903, 904)))
ids_bg <- c(base_ids, tract_id(902))
native_ids <- c(paste0(substr(base_ids[1], 1, 5), "000200"), base_ids[-1], tract_id(c(902, 901, 905, 904)))
linked_ids <- c(ids_bg, tract_id(c(901, 905, 904)))

# Field lists follow schemas/acs_full.md; input flags/tags follow Step 2 schemas.
estimates <- c("rentE", "lqcrentE", "popE", "huE", "rhuE", "med_hvalE",
               "med_hhincE", "pctrhuE", "pctvacE", "pctblkE",
               "pcthspE", "pctaaE", "pctsfdE", "mf5E", "nsfaE", "smfE", "sfd_detE",
               "pctrvacE", "pctsvacE")
structure_level_columns <- c("smfE_16", "smfE_24", "sfd_detE_16", "sfd_detE_24")
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
  x$smfE <- as.double(seq_along(ids) * 3)
  x$sfd_detE <- as.double(seq_along(ids) * 7)
  x$sfd_detM <- rep(2, length(ids))
  if (bg) {
    x <- mutate(x, rhu_id = TRUE, left_id = TRUE, right_id = TRUE,
                 pct_miss_rent = 0,
                 tc_flag_rent_24 = 0, rent_status_24 = "observed", rent_censor_bound_24 = NA_real_, interp_rent = rentE * 1.05) |>
      select(-all_of(c("rentE", "rentM", "rentCV", "lqcrentE", "lqcrentM",
                       "med_hvalE", "med_hvalM", "med_hvalCV")))
  } else {
    x <- mutate(x, rent_id = TRUE, m_flag_lqcrent = 0,
                 m_flag_rhu = 0, m_flag_med_hval = 0, zero_flag_rhu = 0, zero_flag_med_hval = 0,
                 tc_flag_lqcrent = 0, tc_flag_med_hval = 0)
    year <- if (key == "tr2010_id") "16" else "24"
    x <- add_rent_metadata(x, rep("observed", nrow(x)), year)
  }
  x
}

# Both native key types accept zero, fractional, and missing structure counts,
# and reject absent fields, negative/infinite counts, or nonnumeric storage.
for (key in c("tr2010_id", "tr2020_id")) {
  input <- make_input(tract_id(1:5), key)
  for (column in c("smfE", "sfd_detE")) input[[column]] <- c(0, 2.5, NA, NaN, 4)
  assert_merge_measures(input, key, "Structure input")
  for (column in c("smfE", "sfd_detE")) {
    expect_error(assert_merge_measures(select(input, -all_of(column)), key, "Structure input"),
                 "missing documented input fields")
    for (bad_value in list(-1, Inf, -Inf, "1")) {
      bad_input <- input
      bad_input[[column]][1] <- bad_value
      expect_error(assert_merge_measures(bad_input, key, "Structure input"),
                   "must be numeric, finite and nonnegative")
    }
  }
}

# Independent selector exercise supplies both alternatives even on changed rows.
# This tests no fallback in both directions without inventing geographic links.
small <- tibble(tr2010_id = tract_id(1:8), geo_consistent = c(1, 0, NA, 2, 1, 0, 1, 0))
a <- prepare_2024_source(make_input(tract_id(1:8), "tr2020_id"), "tract")
b <- prepare_2024_source(make_input(tract_id(1:8), "tr2010_id", bg = TRUE), "bg_agg")
a$rentE_24_tract <- c(30, 30, 30, 30, NA, 30, 30, 30)
a$med_hhincE_24_tract <- a$rentE_24_tract
b$med_hhincE_24_bg_agg <- c(20, 20, 20, 20, 20, NaN, 20, 20)
b$interp_rent_24_bg_agg <- c(25, 25, 25, 25, 25, NaN, 25, 25)
a$rhu_inventoryE_24_tract <- a$rentE_24_tract + 5
b$rhu_inventoryE_24_bg_agg <- b$med_hhincE_24_bg_agg + 5
a$med_hhincM_24_tract <- c(rep(40, 6), NA, 40)
b$med_hhincM_24_bg_agg <- c(rep(20, 7), NA)
a$tc_flag_rent_24_tract[7] <- NA_real_
b$tc_flag_rent_24_bg_agg[8] <- NA_real_
a$smfE_24_tract <- c(0, 30, 30, 30, NA, 30, 30, 30)
b$smfE_24_bg_agg <- c(20, 2.5, 3.5, 4.5, 20, NaN, 20, 0)
a$sfd_detE_24_tract <- c(70, 70, 70, 70, NA, 70, 0, 70)
b$sfd_detE_24_bg_agg <- c(40, 5.25, 6.25, 7.25, 40, NA, 40, 0)
small <- bind_cols(small, select(a, -tr2020_id), select(b, -tr2010_id))
selected <- select_canonical_2024(small)
stopifnot(identical(selected$med_hhincE_24, c(30, 20, 20, 20, NA, NaN, 30, 20)),
          identical(selected$smfE_24, c(0, 2.5, 3.5, 4.5, NA, NaN, 30, 0)),
          identical(selected$sfd_detE_24, c(70, 5.25, 6.25, 7.25, NA, NA, 0, 0)),
          identical(selected$interp_rent, c(30, 25, 25, 25, NA, NaN, 30, 25)),
          identical(selected$interp_rent_24_bg_agg, b$interp_rent_24_bg_agg),
          identical(selected$tr2010_id, small$tr2010_id),
          identical(select_canonical_2024(selected), selected),
          identical(selected$acs_source_24, c("tract", "bg_agg", "bg_agg", "bg_agg", "tract", "bg_agg", "tract", "bg_agg")),
          all(is.na(selected$med_hhincM_24[7:8])), all(is.na(selected$tc_flag_rent_24[7:8])))
equality <- assert_hierarchical_2024(selected)
stopifnot(all(equality$n_mismatch == 0),
          all(filter(equality, measure %in% c("med_hhincE_24", "interp_rent"))$
                n_alternative_available_when_selected_missing == 1))
# Detect wrong values, wrong missingness, and fallback for every status branch.
for (row in c(1, 2, 3, 4, 5, 6)) {
  bad_value <- if (row == 1) 25 else 30
  expect_error(assert_hierarchical_2024(
    mutate(selected, interp_rent = replace(interp_rent, row, bad_value))), "interp_rent violates")
}
expect_error(assert_hierarchical_2024(mutate(selected, interp_rent = med_hhincE_24)), "interp_rent violates")
expect_error(assert_hierarchical_2024(
  mutate(selected, interp_rent = replace(interp_rent, 1, NA_real_))), "interp_rent violates")
expect_error(assert_hierarchical_2024(mutate(selected, med_hhincE_24 = coalesce(med_hhincE_24, med_hhincE_24_bg_agg))),
             "violates")
expect_error(assert_hierarchical_2024(mutate(selected, med_hhincE_24 = replace(med_hhincE_24, 5, 20))), "violates")
expect_error(assert_hierarchical_2024(mutate(selected, med_hhincE_24 = replace(med_hhincE_24, 6, 30))), "violates")
expect_error(assert_hierarchical_2024(mutate(selected, med_hhincM_24 = med_hhincM_24_bg_agg)), "violates")
expect_error(assert_hierarchical_2024(mutate(selected, acs_source_24 = "tract")), "selected source")
for (row in c(3, 4)) {
  expect_error(assert_hierarchical_2024(
    mutate(selected, acs_source_24 = replace(acs_source_24, row, NA_character_))), "selected source")
}
stopifnot(nrow(assert_hierarchical_2024(select_canonical_2024(small[FALSE, ]))) == 2 * nrow(merge_2024_field_map()))
expect_error(prepare_2024_source(select(make_input(tract_id(1), "tr2020_id"), -med_hhincM)), "missing bundle")
expect_error(prepare_2024_source(select(make_input(tract_id(1), "tr2010_id", bg = TRUE),
                                       -interp_rent), "bg_agg"), "missing bundle")
expect_error(prepare_2024_source(mutate(make_input(tract_id(1), "tr2010_id", bg = TRUE),
                                       interp_rent = "25"), "bg_agg"), "must be numeric")

# Exercise observed and genuinely missing values for every mapped field, including
# status-missing/unexpected rows with observed alternatives and source quality flags.
fields <- merge_2024_field_map()
all_fields <- mutate(small, geo_consistent = c(1, 0, NA, 2, 1, 0, NA, 2),
                     rentE_16 = as.double(51:58), pct_miss_rent = 0.25)
for (i in seq_along(unique(fields$tract))) {
  column <- unique(fields$tract)[i]
  value <- if (grepl("rent_status", column)) "observed" else if (grepl("_flag_", column)) 0 else as.double(100 + i)
  all_fields[[column]] <- replace(rep(value, 8), c(3, 5), NA_real_)
}
for (i in seq_along(fields$bg_agg)) {
  column <- fields$bg_agg[i]
  value <- if (grepl("rent_status", column)) "top_coded" else if (grepl("_flag_", column)) 1 else as.double(200 + i)
  all_fields[[column]] <- if (is.character(value)) c(rep(value, 5), rep(NA_character_, 3)) else c(rep(value, 5), NA_real_, NA_real_, NaN)
  all_fields[[fields$canonical[i]]] <- rep(-999, 8)
}
all_selected <- select_canonical_2024(all_fields)
untouched <- setdiff(names(all_fields), fields$canonical)
stopifnot(identical(all_selected[untouched], all_fields[untouched]),
          identical(all_selected$acs_source_24,
                    c("tract", "bg_agg", "bg_agg", "bg_agg", "tract", "bg_agg", "bg_agg", "bg_agg")),
          identical(select_canonical_2024(all_selected), all_selected),
          all(assert_hierarchical_2024(all_selected)$n_mismatch == 0))
for (i in seq_len(nrow(fields))) {
  column <- fields$canonical[i]
  expected_tract <- all_fields[[fields$tract[i]]]
  expected_bg <- all_fields[[fields$bg_agg[i]]]
  if (column == "rent_status_24") {
    expected_tract <- coalesce(expected_tract, "unresolved")
    expected_bg <- coalesce(expected_bg, "unresolved")
  }
  stopifnot(identical(all_selected[[column]][c(1, 5)], expected_tract[c(1, 5)]),
            identical(all_selected[[column]][c(2, 3, 4, 6, 7, 8)], expected_bg[c(2, 3, 4, 6, 7, 8)]))
  bad_missing <- all_selected
  bad_missing[[column]][3] <- NA_real_
  expect_error(assert_hierarchical_2024(bad_missing), paste(column, "violates"))
  bad_fallback <- all_selected
  bad_fallback[[column]][7] <- all_fields[[fields$tract[i]]][7]
  expect_error(assert_hierarchical_2024(bad_fallback), paste(column, "violates"))
}
correction <- summarize_hierarchy_correction(all_selected)
stopifnot(identical(correction$measure, fields$canonical),
          all(correction$n_not_consistent == 6), all(correction$n_bg_observed == 3),
          all(correction$n_canonical_missing_before == 5),
          all(correction$n_canonical_missing_after == ifelse(correction$measure == "rent_status_24", 0, 3)),
          all(correction$n_bg_observed_canonical_missing_before == 2),
          all(correction$n_bg_observed_canonical_missing_after == 0))
legacy_selected <- all_selected
legacy_selected$acs_source_24[c(3, 4, 7, 8)] <- NA_character_
for (column in fields$canonical) legacy_selected[[column]][c(3, 4, 7, 8)] <- NA_real_
legacy_correction <- summarize_hierarchy_correction(legacy_selected)
stopifnot(all(legacy_correction$n_bg_observed_canonical_missing_after == 2))
expect_error(assert_hierarchical_2024(legacy_selected), "selected source")
for (input in list(all_selected[FALSE, ], all_selected[c(1, 5), ])) {
  empty_correction <- summarize_hierarchy_correction(input)
  stopifnot(nrow(empty_correction) == nrow(fields),
            all(as.matrix(select(empty_correction, -measure)) == 0))
}

# Positive, zero, negative, and missing 2016 baselines; all numerators are
# selected first, with native rent and block-group interpolation kept distinct.
baseline <- make_input(tract_id(1:8), "tr2010_id") |>
  mutate(rentE = c(10, 10, 10, 10, 10, 10, 0, -1)) |>
  rename_vars("16") |>
  select(ends_with("_16"))
changed_small <- calc_change_vars(bind_cols(selected, baseline))
stopifnot(isTRUE(all.equal(changed_small$interp_rentPOST,
                          c(3, 2.5, 2.5, 2.5, NA, NA, NA, NA), tolerance = 0)),
          !any(c("rentPOST", "lqcrentPOST") %in% names(changed_small)))
baseline$rentE_16[2] <- NA_real_
stopifnot(is.na(calc_change_vars(bind_cols(selected, baseline))$interp_rentPOST[2]))

source_16 <- make_input(ids_16, "tr2010_id")
bg_estimates <- setdiff(estimates, c("rentE", "lqcrentE", "med_hvalE"))
bg_moes <- setdiff(moes, c("rentM", "lqcrentM", "med_hvalM"))
bg_cvs <- setdiff(cvs, c("rentCV", "med_hvalCV"))
source_bg <- make_input(ids_bg, "tr2010_id", bg = TRUE) |>
  mutate(across(all_of(c(bg_estimates, "rhu_inventoryE")), ~ .x * 2),
         across(all_of(bg_moes), ~ .x * 10), across(all_of(bg_cvs), ~ .x * 2),
         pct_miss_rent = 0.2)
source_tract <- make_input(native_ids, "tr2020_id") |>
  mutate(across(all_of(c(estimates, "rhu_inventoryE")), ~ .x * 3),
         across(all_of(moes), ~ .x * 20), across(all_of(cvs), ~ .x * 3))
source_16$rentE[c(2, 3)] <- c(0, NA_real_)
source_16$rent_status_16[3] <- "unresolved"
source_16$tc_flag_rent_16[3] <- NA_real_
source_16$rhuE[4] <- 0
source_16$rhu_inventoryE[5] <- 0
source_tract$tr2020_id[6] <- paste0(substr(native_ids[6], 1, 5), "000300")
source_tract$rentE[c(7, 14)] <- NA_real_
source_tract$rent_status_24[c(7, 14)] <- c("unresolved", "top_coded")
source_tract$tc_flag_rent_24[7] <- NA_real_
source_tract$rent_censor_bound_24[14] <- 3500
source_tract$rentCV[c(7, 14)] <- NA_real_
source_tract$tc_flag_rent_24[14] <- 1
source_tract$med_hhincM[12] <- NA_real_
source_tract$med_hhincCV[12] <- NA_real_
source_tract$rhu_inventoryE[9] <- NA_real_
source_bg$rhu_inventoryE[c(7, 8)] <- NA_real_
source_bg$rhu_inventoryE[9] <- source_bg$rhuE[9] - 1
source_bg$med_hhincE[13] <- NA_real_
source_bg$med_hhincCV[13] <- NA_real_
source_bg$interp_rent[8] <- NA_real_
source_bg$rent_status_24[8] <- "unavailable_other"
source_bg$tc_flag_rent_24[8] <- NA_real_
source_16$smfE[c(2, 3)] <- c(0, NA_real_)
source_16$sfd_detE[c(4, 5)] <- c(0, NA_real_)
source_tract$smfE[c(1, 7)] <- c(0, NA_real_)
source_tract$sfd_detE[7] <- NA_real_
source_bg$smfE[c(2, 8, 10, 11)] <- c(4.5, NA, 31.25, 41.75)
source_bg$sfd_detE[c(2, 8, 10, 11)] <- c(6.25, NA, 51.5, 61.5)
notebook_xwalk <- tibble(tr2020_id = native_ids, tr2010_id = linked_ids,
                         geo_consistent = 1, relationship_class = "consistent",
                         same_geoid = as.double(native_ids == linked_ids),
                         n_2010_partners = 1L, n_2020_partners = 1L)
changed <- c(2, 4, 8, 11, 13, 15, 18)
notebook_xwalk$geo_consistent[changed] <- 0
notebook_xwalk$relationship_class[changed] <- "one_to_one_changed"
notebook_xwalk$geo_consistent[11] <- 2
notebook_xwalk$relationship_class[12] <- "unexpected_class"
# An absent crosswalk link leaves status/Census fields missing despite an observed aggregate.
notebook_xwalk <- filter(notebook_xwalk, tr2010_id != linked_ids[10])
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
                "merge-surveys", "build-diagnostic-panel")) run_chunk(label)
panel_before_selection <- env$acs_full
geography_before_selection <- select(env$acs_diagnostics, tr2010_id, tr2020_id,
                                      geo_consistent, relationship_class)
for (label in c("select-canonical-24", "change-vars")) run_chunk(label)
canonical_before <- env$acs_full
canonical_names <- names(canonical_before)
stopifnot(setequal(grep("smf|sfd_det", canonical_names, value = TRUE), structure_level_columns),
          all(vapply(canonical_before[structure_level_columns], is.double, logical(1))))
# Check values against native keyed inputs, including a different-GEOID link,
# absent records, selected missing estimates, and fractional aggregate levels.
rows_16 <- match(canonical_before$tr2010_id, source_16$tr2010_id)
rows_bg <- match(canonical_before$tr2010_id, source_bg$tr2010_id)
rows_tract <- match(canonical_before$tr2020_id, source_tract$tr2020_id)
use_tract <- canonical_before$geo_consistent %in% 1
for (column in c("smfE", "sfd_detE")) {
  stopifnot(identical(canonical_before[[paste0(column, "_16")]], source_16[[column]][rows_16]),
            identical(canonical_before[[paste0(column, "_24")]][use_tract],
                      source_tract[[column]][rows_tract[use_tract]]),
            identical(canonical_before[[paste0(column, "_24")]][!use_tract],
                      source_bg[[column]][rows_bg[!use_tract]]))
}
unchanged_columns <- setdiff(names(panel_before_selection), fields$canonical)
stopifnot(identical(select(canonical_before, all_of(unchanged_columns)),
                    select(panel_before_selection, all_of(unchanged_columns))),
          identical(select(canonical_before, all_of(names(geography_before_selection))),
                    geography_before_selection))
row_901 <- match(tract_id(901), canonical_before$tr2010_id)
row_903 <- match(tract_id(903), canonical_before$tr2010_id)
row_904 <- match(tract_id(904), canonical_before$tr2010_id)
row_902 <- match(tract_id(902), canonical_before$tr2010_id)
stopifnot(nrow(canonical_before) == length(union(ids_16, ids_bg)),
          isTRUE(all.equal(env$acs_16_diagnostic$rentE_16, source_16$rentE * 1.307)),
          canonical_before$rhuPOST[1] == 3, canonical_before$rhuPOST[2] == 2,
          canonical_before$rhu_inventoryPOST[1] == 3,
          is.na(canonical_before$rhuPOST[4]), is.na(canonical_before$rhu_inventoryPOST[5]),
          is.na(canonical_before$interp_rent[6]), is.na(canonical_before$interp_rent[7]),
          is.na(canonical_before$rhu_inventoryE_24[8]), is.na(canonical_before$rhu_inventoryE_24[9]),
          is.na(canonical_before$geo_consistent[10]), all(is.na(canonical_before$tr2020_id[10:11])),
          identical(canonical_before$med_hhincE_24[10:11], source_bg$med_hhincE[10:11]),
          canonical_before$acs_source_24[12] == "tract", is.na(canonical_before$med_hhincM_24[12]),
          is.na(canonical_before$med_hhincPOSTCV[12]), is.na(canonical_before$med_hhincE_24[13]),
          canonical_before$tc_flag_rent_24[1] == 0, canonical_before$tc_flag_rent_24[2] == 0,
          canonical_before$tc_flag_rent_24[14] == 1, is.na(canonical_before$interp_rent[14]),
          is.na(canonical_before$post_id[row_901]), !is.na(canonical_before$interp_rentPOST[row_901]),
          canonical_before$acs_source_24[row_903] == "bg_agg", is.na(canonical_before$interp_rent[row_903]),
          canonical_before$acs_source_24[row_904] == "bg_agg", is.na(canonical_before$interp_rent[row_904]),
          is.na(canonical_before$rhu_inventoryPOST[row_902]),
          !tract_id(905) %in% canonical_before$tr2010_id,
          !any(grepl("inventory.*(M_|CV|POSTCV)", canonical_names)))
# Shares use raw differences (not ratios or a multiplier of 100).
for (measure in c("pctrhu", "pctvac", "pctrvac", "pctsvac")) {
  stopifnot(isTRUE(all.equal(canonical_before[[paste0(measure, "PPC")]][1:2], c(0.4, 0.2))))
}
for (measure in c("rhu", "med_hhinc")) {
  e16 <- canonical_before[[paste0(measure, "E_16")]][1]
  m16 <- canonical_before[[paste0(measure, "M_16")]][1]
  ratio <- canonical_before[[paste0(measure, "POST")]][1]
  expected_moe <- sqrt(max(0, 40^2 - ratio^2 * m16^2)) / e16
  stopifnot(isTRUE(all.equal(canonical_before[[paste0("moe_", measure, "POST")]][1], expected_moe)),
            isTRUE(all.equal(canonical_before[[paste0(measure, "POSTCV")]][1], expected_moe/1.645/ratio)))
}
bg_rows <- match(canonical_before$tr2010_id, source_bg$tr2010_id)
for (column in c("pct_miss_rent")) {
  stopifnot(identical(canonical_before[[column]], source_bg[[column]][bg_rows]))
}
stopifnot(canonical_before$interp_rent[1] == 30,
          isTRUE(all.equal(canonical_before$interp_rentPOST[1], 3/1.307)),
          canonical_before$interp_rent[4] == source_bg$interp_rent[4],
          isTRUE(all.equal(canonical_before$interp_rentPOST[4], 1.05/1.307)),
          all(is.na(canonical_before$interp_rent[c(6, 7, 8, 14, row_903, row_904)])),
          all(is.na(canonical_before$interp_rentPOST[c(2, 3, 6, 7, 8, 14, row_903, row_904)])),
          identical(canonical_before$interp_rent[10:11], source_bg$interp_rent[10:11]),
          identical(canonical_before$rhu_inventoryE_24[10:11], source_bg$rhu_inventoryE[10:11]),
          isTRUE(all.equal(canonical_before$interp_rentPOST[10:11],
                           source_bg$interp_rent[10:11] / canonical_before$rentE_16[10:11], tolerance = 0)),
          canonical_before$interp_rent[13] == source_bg$interp_rent[13],
          !is.na(canonical_before$interp_rentPOST[13]),
          canonical_before$interp_rent[row_901] == source_tract$rentE[match(tract_id(901), native_ids)],
          !is.na(canonical_before$interp_rentPOST[row_901]),
          !any(grepl("^interp_rent(M|CV|POSTCV)$|^moe_interp_rentPOST$", canonical_names)))
for (label in c("summarize-cv", "geography-coverage", "source-selection-qa",
                "compare-source-levels", "diagnostic-change-vars", "compare-inventory-levels",
                "compare-inventory-changes", "validation-panel", "validate-keys-panel",
                "validate-missingness-panel", "validate-flags-panel", "validate-numeric-panel")) run_chunk(label)
consistent_keys <- canonical_before$tr2010_id[canonical_before$geo_consistent %in% 1]
stopifnot(identical(env$acs_full, canonical_before),
          identical(select(env$acs_diagnostics, all_of(canonical_names)), canonical_before),
          !any(grepl("\\.[xy]$|^diag_|_24_tract$|_24_bg_agg$|^in_|^same_geoid$", canonical_names)),
          env$source_level_diagnostics$interp_rent$coverage$n_total == length(consistent_keys),
          env$inventory_level_diagnostics$tract_2024$coverage$n_total == nrow(source_tract),
          env$inventory_level_diagnostics$bg_agg_2024$coverage$n_x_below_y == 1,
          identical(env$inventory_change_diagnostics$bg_agg_full_panel$values$tr2010_id,
                    canonical_before$tr2010_id),
          identical(env$inventory_change_diagnostics$tract_consistent$values$tr2010_id,
                    consistent_keys),
          env$alignment_coverage$n_consistent_link_without_census[1] == 1,
          sum(env$source_selection_qa$counts$n_tracts) == nrow(canonical_before),
          isTRUE(all.equal(sum(env$source_selection_qa$counts$share), 1)),
          env$source_selection_qa$counts$n_tracts[env$source_selection_qa$counts$source == "unassigned"] == 0,
          env$source_selection_qa$geography$status$n_tracts[4] == 1,
          all(c("interp_rent", "interp_rentPOST") %in% env$source_selection_qa$missingness$measure),
          all(env$hierarchy_equality$n_mismatch == 0),
          identical(env$hierarchy_correction_qa$measure, fields$canonical),
          all(env$hierarchy_correction_qa$n_bg_observed_canonical_missing_after == 0),
          all(filter(env$hierarchy_correction_qa, measure %in% c("interp_rent", "rhu_inventoryE_24"))$
                n_bg_observed_canonical_missing_before == 2),
          all(with(filter(env$hierarchy_correction_qa, measure != "rent_status_24"),
                   n_canonical_missing_after == n_not_consistent - n_bg_observed)))

# Section 5 retains every consistent key, including different-GEOID pairs and
# missing source records, while Sections 6 and 7 retain their original universes.
for (results in list(env$source_level_diagnostics, env$source_change_diagnostics)) {
  stopifnot(identical(names(results), c("interp_rent", "inventory")))
  for (result in results) {
    stopifnot(identical(result$values$tr2010_id, consistent_keys),
              all(result$values$geo_consistent == 1),
              identical(result$coverage$group, "overall"),
              identical(unique(result$summaries$group), "overall"),
              result$coverage$n_total == length(consistent_keys))
  }
}
interpolated_levels <- env$source_level_diagnostics$interp_rent$values
interpolated_changes <- env$source_change_diagnostics$interp_rent$values
stopifnot(identical(interpolated_levels$x_value,
                    source_tract$rentE[match(interpolated_levels$tr2020_id, source_tract$tr2020_id)]),
          identical(interpolated_levels$y_value,
                    source_bg$interp_rent[match(consistent_keys, source_bg$tr2010_id)]),
          interpolated_levels$x_value[1] == 30, interpolated_levels$y_value[1] == 10.5,
          interpolated_levels$difference[1] == 19.5,
          interpolated_levels$absolute_difference[1] == 19.5,
          isTRUE(all.equal(interpolated_levels$ratio[1], 30/10.5)),
          isTRUE(all.equal(interpolated_changes$x_value[1], 3/1.307)),
          isTRUE(all.equal(interpolated_changes$y_value[1], 1.05/1.307)),
          isTRUE(all.equal(interpolated_changes$difference[1], 1.95/1.307)),
          isTRUE(all.equal(interpolated_changes$ratio[1], 30/10.5)),
          all(env$baseline_coverage$group == "overall"),
          all(env$baseline_coverage$n_total == length(consistent_keys)),
          !"diag_interp_rentPOST_24_bg_agg" %in% names(env$acs_diagnostics))

# Run only Section 5 chunks on small inputs to check denominator and empty cases.
section5_input <- tibble(
  tr2010_id = tract_id(1:9), tr2020_id = tract_id(101:109),
  geo_consistent = c(rep(1, 6), 0, NA, 2),
  rentE_24_tract = c(120, 140, 160, NA, 200, 220, 9000, 8000, 7000),
  interp_rent_24_bg_agg = c(100, 0, NA, 180, 190, 200, 4000, 3000, 2000),
  rentE_16 = c(100, 0, -1, 100, NA, 100, 100, 100, 100),
  rhuE_16 = 10, rhuE_24_tract = 20, rhuE_24_bg_agg = 30,
  rhu_inventoryE_16 = 12, rhu_inventoryE_24_tract = 25, rhu_inventoryE_24_bg_agg = 35
) |>
  mutate(interp_rent = rentE_24_tract)
run_section5 <- function(input) {
  section_env <- new.env(parent = globalenv())
  section_env$acs_diagnostics <- input
  for (label in c("compare-source-levels", "diagnostic-change-vars")) {
    quiet(eval(notebook_chunk(label), section_env))
  }
  stopifnot(identical(select(section_env$acs_diagnostics, all_of(names(input))), input))
  section_env
}
section5 <- run_section5(section5_input)
stopifnot(identical(section5$source_comparison_diagnostics$tr2010_id, tract_id(1:6)),
          identical(section5$source_level_diagnostics$interp_rent$values$y_value,
                    c(100, 0, NA, 180, 190, 200)),
          identical(section5$source_change_diagnostics$interp_rent$values$x_value,
                    c(1.2, NA, NA, NA, NA, 2.2)),
          identical(section5$source_change_diagnostics$interp_rent$values$y_value,
                    c(1, NA, NA, 1.8, NA, 2)),
          section5$source_level_diagnostics$interp_rent$coverage$n_total == 6,
          section5$source_level_diagnostics$interp_rent$coverage$n_paired == 4,
          section5$source_level_diagnostics$interp_rent$coverage$n_ratio == 3,
          section5$source_change_diagnostics$interp_rent$coverage$n_paired == 2,
          filter(section5$baseline_coverage, measure == "rentE_16")$n_base_nonpositive == 2,
          filter(section5$baseline_coverage, measure == "rentE_16")$n_base_missing == 1,
          all(section5$baseline_coverage$n_total == 6))
for (input in list(filter(section5_input, !geo_consistent %in% 1),
                   mutate(section5_input, across(-ends_with("id"),
                     ~ if (cur_column() == "geo_consistent") .x else NA_real_)))) {
  edge <- run_section5(input)
  n_consistent <- sum(input$geo_consistent %in% 1)
  for (results in list(edge$source_level_diagnostics, edge$source_change_diagnostics)) {
    for (result in results) {
      stopifnot(result$coverage$n_total == n_consistent,
                identical(result$coverage$group, "overall"), result$coverage$n_paired == 0,
                result$coverage$n_x_missing == n_consistent,
                result$coverage$n_y_missing == n_consistent,
                is.na(result$coverage$correlation),
                all(is.na(select(result$summaries, mean, sd, min, p25, median, p75, max))))
    }
  }
  stopifnot(all(edge$baseline_coverage$n_total == n_consistent),
            all(edge$baseline_coverage$group == "overall"))
}
cat("Section 5 synthetic checks passed: consistent population, source interpolation, changes, and missing/empty cases.\n")

# The actual notebook validation rejects using the preserved block-group source
# for changes, even when the diagnostic copy has the same incorrect values.
bad_change_env <- new.env(parent = env)
bad_change_env$acs_full <- mutate(canonical_before,
  interp_rentPOST = if_else(tc_flag_rent_16 %in% 1 | tc_flag_rent_24 %in% 1,
    NA_real_, diagnostic_ratio(env$acs_diagnostics$interp_rent_24_bg_agg, rentE_16)))
bad_change_env$acs_diagnostics <- mutate(env$acs_diagnostics,
  interp_rentPOST = bad_change_env$acs_full$interp_rentPOST)
expect_error(eval(notebook_chunk("validation-panel"), bad_change_env),
             "Interpolated rent change must use the canonical selected value")

bad_change_env$acs_full <- mutate(canonical_before,
  interp_rentPOST = if_else(tc_flag_rent_24 %in% 1, 1, interp_rentPOST))
expect_error(eval(notebook_chunk("validation-panel"), bad_change_env),
             "Confirmed top-codes must not enter numeric rent changes")

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
# This independent list is the agreed removal contract, including sole-use flags.
retired_panel <- c("tc_flag_rent", "m_flag_rent", "pct_tc_rent", "rhu_lrE_16", "rhu_lrE_24", "rhu_lr2E_16", "rhu_lr2E_24",
  "rhu_lrPOST", "rhu_lr2POST", "rentE_24", "rentM_24", "rentCV_24",
  "lqcrentE_24", "lqcrentM_24", "med_hvalE_24", "med_hvalM_24", "med_hvalCV_24",
  "rentPOST", "lqcrentPOST", "moe_rentPOST", "rentPOSTCV", "m_flag_rentPOST",
  "pct_miss_hval", "m_flag_rent_24", "m_flag_lqcrent_24", "m_flag_med_hval_24",
  "zero_flag_med_hval_24", "tc_flag_lqcrent_24", "tc_flag_med_hval_24")
stopifnot(!any(retired_panel %in% canonical_names),
          setequal(panel_schema_removals(), retired_panel),
          all(c("rentE_16", "rentM_16", "rentCV_16", "lqcrentE_16", "lqcrentM_16",
                "med_hvalE_16", "med_hvalM_16", "med_hvalCV_16",
                "med_hhincE_24", "med_hhincM_24", "med_hhincCV_24",
                "med_hhincPOST", "moe_med_hhincPOST", "med_hhincPOSTCV") %in% canonical_names))
legacy <- select(canonical_before, -all_of(panel_schema_additions()))
for (column in retired_panel) legacy[[column]] <- 1
for (column in retired_panel) {
  bad_panel <- canonical_before
  bad_panel[[column]] <- 1
  expect_error(assert_panel_schema(bad_panel), "retired fields")
  expect_error(assert_panel_schema(bad_panel, legacy), "retired fields")
}
prior_structure_levels <- select(canonical_before, -all_of(structure_level_columns))
quiet(assert_panel_schema(canonical_before, legacy))
quiet(assert_panel_schema(canonical_before, prior_structure_levels))
quiet(assert_panel_schema(canonical_before, canonical_before))
for (column in structure_level_columns) {
  expect_error(assert_panel_schema(select(canonical_before, -all_of(column))), "missing required fields")
  wrong_type <- canonical_before
  wrong_type[[column]] <- as.integer(wrong_type[[column]])
  expect_error(assert_panel_schema(wrong_type), "storage types")
}
expect_error(assert_panel_schema(mutate(canonical_before, unexpected = 1), legacy), "unapproved")
for (column in c("rentE_16", "med_hhincE_24", "med_hhincM_24", "med_hhincCV_24", "interp_rent")) {
  expect_error(assert_panel_schema(select(canonical_before, -all_of(column)), legacy), "unapproved")
}
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
env$prior_panel <- prior_structure_levels
run_chunk("save-panel")
run_chunk("reload-panel")
stopifnot(setequal(setdiff(names(env$acs_saved), names(prior_structure_levels)), structure_level_columns),
          identical(select(env$acs_saved, -all_of(structure_level_columns)), prior_structure_levels))
env$prior_panel <- env$acs_saved
run_chunk("save-panel")
run_chunk("reload-panel")
env$prior_panel <- NULL
run_chunk("save-panel")
run_chunk("reload-panel")

# Parse actual chunks and check all section numbering and overview titles.
for (file in c("R/merge_helpers.R", "R/merge_diagnostics.R")) invisible(parse(file = here::here(file)))
lines <- readLines(here::here("04_merge.Rmd"), warn = FALSE)
starts <- which(startsWith(lines, "```{r"))
for (start in starts) {
  end <- which(seq_along(lines) > start & lines == "```")[1]
  parse(text = lines[seq.int(start + 1L, end - 1L)])
}
headings <- lines[grepl("^# [0-9]+\\.", lines)]
stopifnot(identical(sub("^# ([0-9]+)\\..*", "\\1", headings), as.character(1:7)),
          all(sub("^# ", "", headings) %in% lines))
for (section in 1:7) {
  subsections <- lines[grepl(paste0("^## ", section, "\\."), lines)]
  numbers <- sub(paste0("^## ", section, "\\.([0-9]+).*"), "\\1", subsections)
  stopifnot(identical(numbers, as.character(seq_along(subsections))))
}
cat("Merge tests passed: hierarchical bundles, structure-count levels, source-aware changes, inventory, geography, diagnostics, and guarded migration/save/reload.\n")
