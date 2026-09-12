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
  notebook_lines <- readLines(here::here("03_tract_change.Rmd"), warn = FALSE)
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
