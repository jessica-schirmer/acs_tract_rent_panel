# Run from the repository root: Rscript --vanilla tests/test_tract_change.R
# Synthetic relationships, the notebook diagnostic chunk, and a temporary Feather round trip.
suppressPackageStartupMessages({
  library(here)
  library(dplyr)
  library(arrow)
  library(matrixStats)
})
source(here::here("R", "helpers.R"))
source(here::here("R", "geography_qa.R"))
source(here::here("R", "tract_change_helpers.R"))

quiet <- function(expr) {
  invisible(capture.output(value <- force(expr)))
  invisible(value)
}
expect_error <- function(expr, message) {
  error <- tryCatch({ quiet(expr); NULL }, error = identity)
  stopifnot(inherits(error, "error"), grepl(message, conditionMessage(error), fixed = TRUE))
}
notebook_chunk <- function(label, file = "03_identify_tract_boundary_changes.Rmd") {
  lines <- readLines(here::here(file), warn = FALSE)
  start <- which(lines == paste0("```{r ", label, "}"))
  stopifnot(length(start) == 1L)
  end <- which(seq_along(lines) > start & lines == "```")[1]
  stopifnot(!is.na(end), end > start + 1L)
  parse(text = lines[seq.int(start + 1L, end - 1L)])
}
tract_id <- function(number) sprintf("06037%06d", number)
pair <- function(id20, id10, land20 = 100, land10 = land20, part = land20) {
  tibble(tr2020_id = tract_id(id20), tr2010_id = tract_id(id10),
         arealand_2020 = as.double(land20), arealand_2010 = as.double(land10),
         arealand_part = as.double(part))
}
source_pairs <- bind_rows(
  pair(1, 1), pair(2, 102), pair(3, 3, 1e10, 1e10 + 1, 1e10),
  pair(10, 110, 40, 100, 40), pair(11, 110, 60, 100, 60),
  pair(20, 120, 100, 40, 40), pair(20, 121, 100, 60, 60),
  pair(30, 130, 100, 100, 50), pair(30, 131, 100, 100, 50),
  pair(31, 130, 100, 100, 50), pair(31, 131, 100, 100, 50),
  pair(40, 140, 100, 75, 75), pair(40, 141, 100, 50, 25),
  pair(41, 141, 25, 50, 25),
  pair(50, 50, 0), pair(51, 151, 0, 60, 0), pair(52, 152, 60, 0, 0),
  pair(60, 160), pair(60, 161, 100, 50, 0), pair(61, 161, 50),
  pair(70, 170, 100, 80, 80),
  mutate(pair(70, 171, 100, 20, 20), tr2010_id = "41035000100"),
  pair(80, 80, 2^31 + 1),
  pair(90, 190), pair(90, 191, 100, 0, 0), pair(91, 191, 0)
)
source_before <- source_pairs
relationships <- quiet(characterize_tract_relationships(source_pairs))
crosswalk <- quiet(build_tract_crosswalk(relationships))
quiet(assert_tract_crosswalk(crosswalk, relationships))
stopifnot(identical(source_pairs, source_before),
          identical(select(relationships, all_of(names(source_pairs))), source_pairs),
          nrow(crosswalk) == n_distinct(source_pairs$tr2020_id))
expected <- tibble(
  tr2020_id = tract_id(c(1, 2, 3, 10, 11, 20, 30, 31, 40, 41, 50, 51, 52,
                         60, 61, 70, 80, 90, 91)),
  relationship_class = c("consistent", "consistent", "one_to_one_changed",
    "split", "split", "merge", "many_to_many", "many_to_many", "many_to_many",
    "split", "one_to_one_changed", "one_to_one_changed", "one_to_one_changed",
    "many_to_many", "split", "merge", "consistent", "many_to_many", "split")
)
stopifnot(identical(select(crosswalk, tr2020_id, relationship_class), expected))
row_for <- function(number) crosswalk[match(tract_id(number), crosswalk$tr2020_id), ]
stopifnot(row_for(1)$same_geoid == 1, row_for(2)$same_geoid == 0,
          row_for(2)$geo_consistent == 1, row_for(2)$tr2010_id == tract_id(102),
          row_for(3)$same_geoid == 1, row_for(3)$geo_consistent == 0,
          row_for(3)$share_2020_land == 1, row_for(3)$share_2010_land < 1,
          row_for(10)$tr2010_id == tract_id(110), row_for(10)$n_2020_partners == 2L,
          row_for(40)$max_n_2020_partners == 2L, is.na(row_for(40)$tr2010_id),
          is.na(row_for(40)$n_2020_partners), is.na(row_for(40)$same_geoid),
          row_for(50)$zero_land_area == 1, is.na(row_for(50)$share_2020_land),
          is.na(row_for(50)$share_2010_land), row_for(50)$geo_consistent == 0,
          is.na(row_for(51)$share_2020_land), row_for(51)$share_2010_land == 0,
          row_for(52)$share_2020_land == 0, is.na(row_for(52)$share_2010_land),
          row_for(60)$n_2010_partners == 2L, row_for(60)$zero_land_area == 0,
          row_for(60)$geo_consistent == 0, row_for(70)$n_2010_partners == 2L,
          row_for(80)$arealand_2020 == 2^31 + 1,
          row_for(90)$zero_land_area == 1, row_for(90)$geo_consistent == 0)
mixed_pairs <- relationships |> filter(tr2020_id == tract_id(40))
stopifnot(setequal(mixed_pairs$relationship_class, c("merge", "many_to_many")))
reordered <- quiet(build_tract_crosswalk(quiet(characterize_tract_relationships(
  source_pairs[rev(seq_len(nrow(source_pairs))), ]
))))
stopifnot(identical(reordered, crosswalk))
cat("Passed: classifications, mixed multiplicity, explicit changed-GEOID keys, exact overlap, zero land, cross-state links, large areas, and order independence.\n")

# Exercise the actual diagnostic chunk with the package order used by other notebooks.
local({
  notebook_lines <- readLines(here::here("03_identify_tract_boundary_changes.Rmd"), warn = FALSE)
  start <- which(notebook_lines == "```{r summarize-classification}")
  stopifnot(length(start) == 1L)
  end <- which(seq_along(notebook_lines) > start & notebook_lines == "```")[1]
  stopifnot(!is.na(end), end > start + 1L)
  diagnostic_code <- parse(text = notebook_lines[seq.int(start + 1L, end - 1L)])
  diagnostic_env <- new.env(parent = environment())
  diagnostic_env$tract_crosswalk <- crosswalk
  diagnostic_env$tract_relationships <- relationships
  stopifnot(identical(get("count", envir = diagnostic_env), matrixStats::count))
  expect_error(eval(quote(count(tract_crosswalk, relationship_class,
                                name = "n_2020_tracts")), envir = diagnostic_env),
               "Argument 'x' is not a vector: list")
  quiet(eval(diagnostic_code, envir = diagnostic_env))
  expected_counts <- table(expected$relationship_class)
  stopifnot(
    identical(diagnostic_env$classification_counts, tibble(
      relationship_class = names(expected_counts),
      n_2020_tracts = as.integer(expected_counts)
    )),
    identical(diagnostic_env$consistent_geoid_counts, tibble(
      same_geoid = c(0, 1), n_consistent_tracts = c(1L, 2L)
    )),
    identical(diagnostic_env$tract_crosswalk, crosswalk),
    identical(diagnostic_env$tract_relationships, relationships)
  )
})
cat("Passed: actual notebook diagnostic counts with matrixStats masking count.\n")

# County lookup parity, both directions of land mismatch, and complete county summaries.
local({
  env <- new.env(parent = environment())
  quiet(eval(notebook_chunk("target-county-config"), env))
  assembly_config <- new.env()
  quiet(eval(notebook_chunk("set-paths", "02b_build_measures_from_tracts.Rmd"), assembly_config))
  stopifnot(identical(env$southern_california_counties, assembly_config$southern_california_counties),
            identical(env$bay_area_counties, assembly_config$bay_area_counties))
  in_county <- function(x, county) mutate(x, tr2020_id = paste0("06", county, substr(tr2020_id, 6, 11)))
  regional_pairs <- bind_rows(
    source_pairs,
    in_county(pair(200, 200, 100, 80, 80), "001"),
    in_county(pair(201, 201, 100, 120, 100), "001"),
    in_county(pair(202, 202, 100, 100, 99), "073"),
    in_county(pair(203, 203, 0), "001"),
    in_county(pair(204, 204), "073"),
    in_county(pair(205, 205), "001"),
    in_county(pair(210, 210, 50, 100, 50), "001"),
    in_county(pair(211, 210, 50, 100, 50), "073")
  )
  env$tract_relationships <- quiet(characterize_tract_relationships(regional_pairs))
  regional_crosswalk <- quiet(build_tract_crosswalk(env$tract_relationships))
  quiet(assert_tract_crosswalk(regional_crosswalk, env$tract_relationships))
  env$tract_crosswalk <- regional_crosswalk
  stopifnot(identical(get("count", env), matrixStats::count))
  quiet(eval(notebook_chunk("summarize-classification"), env))
  quiet(eval(notebook_chunk("summarize-target-counties"), env))
  stopifnot(
    identical(env$tract_crosswalk, regional_crosswalk),
    identical(select(env$target_region_summary, region, n_2020_tracts, n_consistent,
                      n_one_to_one_candidates, n_one_to_one_rejected,
                      n_positive_land_mismatch, n_zero_land_excluded), tibble(
      region = c("Bay Area", "Southern California"), n_2020_tracts = c(5L, 19L),
      n_consistent = c(1L, 3L), n_one_to_one_candidates = c(4L, 7L),
      n_one_to_one_rejected = c(3L, 4L), n_positive_land_mismatch = c(2L, 1L),
      n_zero_land_excluded = c(1L, 3L)
    )),
    env$one_to_one_land_summary$n_2020_tracts == 27L,
    env$one_to_one_land_summary$n_positive_land_mismatch == 4L,
    env$one_to_one_land_summary$n_zero_land_excluded == 4L,
    nrow(env$one_to_one_rejected_pairs) == 8L,
    nrow(env$target_county_summary) == nrow(env$target_county_lookup),
    env$target_region_summary$n_merge[1] == 0L,
    env$target_region_summary$n_many_to_many[1] == 0L,
    env$target_region_summary$n_split[1] == 1L,
    all(env$target_region_summary$pct_consistent == 100 * c(1 / 5, 3 / 19)),
    all(env$one_to_one_rejected_pairs$rejection_reason[
      env$one_to_one_rejected_pairs$tr2010_id %in% tract_id(c(200, 201, 202))
    ] == "positive_land_mismatch"),
    any(env$one_to_one_rejected_pairs$county == "FIPS 06073")
  )
  absent_counties <- filter(env$target_county_summary, !county_fips %in% c("001", "037"))
  stopifnot(all(as.matrix(select(absent_counties, starts_with("n_"))) == 0L),
            all(is.na(absent_counties$pct_consistent)))
  env$tract_crosswalk <- filter(regional_crosswalk, substr(tr2020_id, 3, 5) == "073")
  quiet(eval(notebook_chunk("summarize-target-counties"), env))
  stopifnot(nrow(env$target_county_summary) == nrow(env$target_county_lookup),
            all(env$target_region_summary$n_2020_tracts == 0L),
            all(is.na(env$target_region_summary$pct_consistent)))
})
cat("Passed: county configuration parity, regional membership, empty counties/classes, exclusion reasons, and full-source partner counts.\n")

# Reject structural input errors instead of repairing the relationship universe.
expect_error(characterize_tract_relationships(source_pairs[0, ]), "nonempty table")
expect_error(characterize_tract_relationships(select(source_pairs, -arealand_part)), "three land areas")
expect_error(characterize_tract_relationships(bind_rows(source_pairs, source_pairs[1, ])), "duplicate key")
expect_error(characterize_tract_relationships(mutate(pair(1, 1), tr2010_id = NA_character_)), "11-digit")
expect_error(characterize_tract_relationships(mutate(pair(1, 1), tr2010_id = "6037000001")), "11-digit")
expect_error(characterize_tract_relationships(mutate(pair(1, 1), tr2020_id = 6037000001)), "11-digit")
expect_error(characterize_tract_relationships(mutate(pair(1, 1), tr2020_id = "41035000100")), "California")
for (invalid in c(NA_real_, NaN, Inf, -1, 0.5, 2^53)) {
  expect_error(characterize_tract_relationships(mutate(pair(1, 1), arealand_part = invalid)),
               "Invalid land area")
}
expect_error(characterize_tract_relationships(mutate(pair(1, 1), arealand_part = 101)), "exceeds")
expect_error(characterize_tract_relationships(bind_rows(pair(1, 1), pair(1, 2, 101))), "repeated land total: 2020")
expect_error(characterize_tract_relationships(bind_rows(pair(1, 1), pair(2, 1, 100, 101))), "repeated land total: 2010")

# Output validation must detect damaged keys, apparent dominant links, and flags.
expect_error(assert_tract_crosswalk(bind_rows(crosswalk, crosswalk[1, ]), relationships), "duplicate key")
expect_error(assert_tract_crosswalk(crosswalk[-1, ], relationships), "membership changed")
expect_error(assert_tract_crosswalk(mutate(crosswalk,
  tr2010_id = if_else(tr2020_id == tract_id(40), tract_id(140), tr2010_id)), relationships),
  "Multiple partners")
expect_error(assert_tract_crosswalk(mutate(crosswalk,
  geo_consistent = if_else(tr2020_id == tract_id(50), 1, geo_consistent)), relationships), "six conditions")
expect_error(assert_tract_crosswalk(mutate(crosswalk,
  geo_consistent = if_else(tr2020_id == tract_id(60), 1, geo_consistent)), relationships), "six conditions")
expect_error(assert_tract_crosswalk(mutate(crosswalk,
  relationship_class = if_else(tr2020_id == tract_id(40), "merge", relationship_class)), relationships),
  "relationship classification")
cat("Passed: source and output failure cases.\n")

local({
  path <- tempfile(fileext = ".feather")
  on.exit(unlink(path))
  save_tract_crosswalk(crosswalk, path)
  saved <- arrow::read_feather(path)
  assert_same_schema(saved, crosswalk, "Synthetic crosswalk round trip")
  stopifnot(identical(saved, crosswalk))
  quiet(assert_tract_crosswalk(saved, relationships))
  checksum <- tools::md5sum(path)
  expect_error(save_tract_crosswalk(crosswalk[0, ], path), "Refusing to overwrite")
  stopifnot(identical(tools::md5sum(path), checksum))
  replacement_message <- capture.output(
    save_tract_crosswalk(crosswalk, path, overwrite = TRUE), type = "message"
  )
  stopifnot(any(grepl("Replacing tract crosswalk", replacement_message)),
            identical(arrow::read_feather(path), crosswalk))
})
cat("Passed: Feather types/values, overwrite protection, and explicit replacement.\n")

# The actual notebook configuration and save/reload chunks must replace existing data.
local({
  env <- new.env(parent = environment())
  eval(notebook_chunk("set-paths"), env)
  stopifnot(isTRUE(env$overwrite_output))
  path <- tempfile(fileext = ".feather")
  fingerprint_source <- tempfile(fileext = ".txt")
  on.exit(unlink(c(path, fingerprint_source)))
  writeLines("Synthetic source fingerprint for notebook save validation", fingerprint_source)
  env$output_path <- path
  env$source_path <- fingerprint_source
  env$source_md5 <- unname(tools::md5sum(fingerprint_source))
  env$source_relationships <- source_pairs
  env$tract_relationships <- relationships
  env$tract_crosswalk <- crosswalk
  arrow::write_feather(crosswalk[1, ], path)
  replacement_message <- capture.output(
    quiet(eval(notebook_chunk("save-crosswalk"), env)), type = "message"
  )
  quiet(eval(notebook_chunk("validate-saved-crosswalk"), env))
  stopifnot(any(grepl("Replacing tract crosswalk", replacement_message)),
            identical(env$saved_crosswalk, crosswalk))
})
cat("Passed: notebook rerun overwrites a different existing Feather and validates the replacement.\n")
