# Run from the repository root: Rscript --vanilla tests/test_acs_input_qa.R
# Synthetic inputs only; notebook API calls are stubbed and outputs are temporary.
suppressPackageStartupMessages({
  library(here)
  library(dplyr)
  library(readr)
  library(arrow)
  library(matrixStats)
})
source(here::here("R", "rent_metadata.R"))
download_rent_evidence <- function(df, year, geography = "tract") retain_rent_evidence(df)
source(here::here("R", "helpers.R"))
source(here::here("R", "acs_input_qa.R"))

quiet <- function(expr) {
  invisible(capture.output(value <- force(expr)))
  invisible(value)
}
expect_error <- function(expr, message) {
  error <- tryCatch({ quiet(expr); NULL }, error = identity)
  stopifnot(inherits(error, "error"), grepl(message, conditionMessage(error), fixed = TRUE))
}
notebook_lines <- readLines(here::here("01_import_acs.Rmd"), warn = FALSE)
chunk_starts <- grep("^```\\{r[ ,}]", notebook_lines)
chunks <- lapply(chunk_starts, function(start) {
  end <- which(seq_along(notebook_lines) > start & notebook_lines == "```")[1]
  stopifnot(!is.na(end), end > start + 1L)
  parse(text = notebook_lines[seq.int(start + 1L, end - 1L)])
})
names(chunks) <- sub("^```\\{r ([^,}]+).*", "\\1", notebook_lines[chunk_starts])
stopifnot(!anyDuplicated(names(chunks)))
cat("Passed: all", length(chunks), "Step 1 notebook chunks parse.\n")

# Use the production mapping, including its first-alias and exclusion rules.
mapping <- new.env(parent = globalenv())
quiet(eval(chunks[["configure-block-group-exclusions"]], mapping))
quiet(eval(chunks[["specify-variables"]], mapping))
variables <- mapping$block_group_vars
stopifnot(identical(acs_request_columns(c(first = "code1", alias = "code1", second = "code2")),
                    c("firstE", "secondE", "firstM", "secondM")))
ids <- c("060370001001", "060370002001", "060010003001")
acs <- tibble(bg2020_id = ids, NAME = c("First BG", "Second BG", "Third BG"))
for (column in acs_request_columns(variables)) acs[[column]] <- c(10, NA_real_, NaN)
acs$popE <- c(0L, NA_integer_, 20L)
acs$rent_id <- TRUE
acs_before <- acs
quiet(assert_acs_bg_input(acs, variables))
all_missing <- mutate(acs, across(all_of(acs_request_columns(variables)), ~ rep(NA_real_, n())))
quiet(assert_acs_bg_input(all_missing, variables))
stopifnot(identical(acs, acs_before))
expect_error(assert_acs_bg_input(bind_rows(acs, acs[1, ]), variables), "duplicate BG keys")
for (bad_id in c(NA_character_, "", " ", "60370001001", "06037000100x", "060370001001 ")) {
  bad <- acs
  bad$bg2020_id[1] <- bad_id
  expect_error(assert_acs_bg_input(bad, variables), "nonmissing 12-digit GEOIDs")
}
expect_error(assert_acs_bg_input(mutate(acs, bg2020_id = as.numeric(bg2020_id)), variables),
             "bg2020_id must be character")
expect_error(assert_acs_bg_input(mutate(acs, bg2020_id = factor(bg2020_id)), variables),
             "bg2020_id must be character")
for (column in c("bg2020_id", "NAME", acs_request_columns(variables), "rent_id")) {
  expect_error(assert_acs_bg_input(select(acs, -all_of(column)), variables), "missing required columns")
}
for (column in acs_request_columns(variables)) {
  bad <- acs
  bad[[column]] <- as.character(bad[[column]])
  expect_error(assert_acs_bg_input(bad, variables), "must be numeric")
}
expect_error(assert_acs_bg_input(mutate(acs, rhuE = list(1, 2, 3)), variables), "must be numeric")
expect_error(assert_acs_bg_input(mutate(acs, NAME = 1), variables), "NAME must be character")
expect_error(assert_acs_bg_input(mutate(acs, rent_id = 1), variables), "rent_id must be logical")
expect_error(assert_acs_bg_input(acs[FALSE, ], variables), "nonempty")
duplicate_columns <- acs
names(duplicate_columns)[2] <- names(duplicate_columns)[1]
expect_error(assert_acs_bg_input(duplicate_columns, variables), "duplicate column names")
expect_error(assert_acs_bg_input(acs, c(variables, new_measure = "synthetic_code")), "new_measureE")
cat("Passed: request-derived schema, duplicate/missing/malformed BG keys, numeric types, and valid missing estimates.\n")

weights <- bg_allocation_weight_columns()
crosswalk <- tibble(
  bg2020_id = c(ids[1], ids[1], ids[1], ids[2], "320030057033"),
  tr2010_id = c("06037000100", "06037000200", "06037000300", "06037000200", "06071010300"),
  wt_pop = c(0.25, 0.75, 0, 1, 1),
  wt_hh = c(0.1, 0.9, 0, 1, 1),
  wt_hu = c(0, 1, 0, 1, 1),
  wt_renthu = c(0.125, 0.875, 0, 1, 1),
  x_id = TRUE
)
crosswalk_before <- crosswalk
weight_sums <- quiet(assert_bg_crosswalk(crosswalk))
stopifnot(all(weight_sums$weight_sum == 1), identical(crosswalk, crosswalk_before),
          nrow(weight_sums) == n_distinct(crosswalk$bg2020_id) * length(weights))
expect_error(assert_bg_crosswalk(bind_rows(crosswalk, crosswalk[3, ])), "duplicate allocation pairs")
for (column in c("bg2020_id", "tr2010_id")) {
  bad <- crosswalk
  bad[[column]] <- as.numeric(bad[[column]])
  expect_error(assert_bg_crosswalk(bad), paste(column, "must be character"))
  for (bad_id in c(NA_character_, "", " ", "123", "06037000100x")) {
    bad <- crosswalk
    bad[[column]][1] <- bad_id
    expect_error(assert_bg_crosswalk(bad), "GEOIDs")
  }
}
for (column in c("bg2020_id", "tr2010_id", weights, "x_id")) {
  expect_error(assert_bg_crosswalk(select(crosswalk, -all_of(column))), "missing required columns")
}
for (column in weights) {
  for (bad_weight in c(NA_real_, NaN, Inf, -Inf, -1e-12, 1 + 1e-12)) {
    bad <- crosswalk
    bad[[column]][1] <- bad_weight
    expect_error(assert_bg_crosswalk(bad), "must be finite and within [0, 1]")
  }
  for (bad_type in list(as.character(crosswalk[[column]]), rep(TRUE, nrow(crosswalk)))) {
    bad <- crosswalk
    bad[[column]] <- bad_type
    expect_error(assert_bg_crosswalk(bad), "must be numeric")
  }
  # Every weight family is reconciled separately, with the original tolerance.
  for (bad_sum in c(0, 0.99)) {
    bad <- crosswalk
    bad[[column]][4] <- bad_sum
    expect_error(assert_bg_crosswalk(bad), "full source weights must sum to one")
  }
  bad <- crosswalk
  bad[[column]][1] <- bad[[column]][1] + 2e-6
  expect_error(assert_bg_crosswalk(bad), "full source weights must sum to one")
  rounded <- crosswalk
  rounded[[column]][1] <- rounded[[column]][1] + 0.5e-6
  rounded_before <- rounded
  quiet(assert_bg_crosswalk(rounded))
  stopifnot(identical(rounded, rounded_before))
}
expect_error(assert_bg_crosswalk(mutate(crosswalk, x_id = NA)), "x_id must be logical")
cat("Passed: unique allocation pairs, character GEOIDs, all four weight ranges/types, source sums, and no renormalization.\n")

coverage <- bg_coverage_diagnostics(acs, crosswalk)
stopifnot(identical(coverage$summary$n_bg, c(1L, 1L)),
          identical(coverage$acs_only$bg2020_id, ids[3]),
          identical(coverage$crosswalk_only$bg2020_id, "320030057033"),
          identical(coverage$by_county$source_county_fips, c("06001", "32003")),
          identical(coverage$by_county$source_state_fips, c("06", "32")),
          identical(coverage$crosswalk_only_links, crosswalk[5, ]),
          identical(acs, acs_before), identical(crosswalk, crosswalk_before))
matched_acs <- acs[1:2, ]
matched_crosswalk <- crosswalk[1:4, ]
stopifnot(all(bg_coverage_diagnostics(matched_acs, matched_crosswalk)$summary$n_bg == 0L),
          nrow(bg_coverage_diagnostics(matched_acs, matched_crosswalk)$by_county) == 0L,
          identical(bg_coverage_diagnostics(acs, matched_crosswalk)$summary$n_bg, c(1L, 0L)),
          identical(bg_coverage_diagnostics(matched_acs, crosswalk)$summary$n_bg, c(0L, 1L)))
disjoint <- bg_coverage_diagnostics(acs[3, ], crosswalk)
stopifnot(identical(disjoint$summary$n_bg, c(1L, 3L)),
          nrow(disjoint$crosswalk_only_links) == nrow(crosswalk),
          sum(disjoint$by_county$n_bg) == 4L)
cat("Passed: ACS-only, crosswalk-only, matching, disjoint, split-source, and county coverage diagnostics.\n")

local({
  tmp_dir <- tempfile("step1_input_qa_")
  dir.create(tmp_dir)
  on.exit(unlink(tmp_dir, recursive = TRUE), add = TRUE)
  for (name in c("acs", "crosswalk")) {
    original <- if (name == "acs") acs else crosswalk
    keys <- if (name == "acs") "bg2020_id" else c("bg2020_id", "tr2010_id")
    path <- file.path(tmp_dir, paste0(name, ".feather"))
    write_feather(original, path)
    reloaded <- read_feather(path)
    quiet(assert_step1_readback(reloaded, original, keys, name))
    stopifnot(identical(reloaded, original, num.eq = FALSE))
    expect_error(assert_step1_readback(reloaded[-1, ], original, keys, name), "row count changed")
    expect_error(assert_step1_readback(reloaded[nrow(reloaded):1, ], original, keys, name),
                 "keys or row order changed")
    expect_error(assert_step1_readback(reloaded[rev(names(reloaded))], original, keys, name),
                 "column names or order changed")
    bad <- reloaded
    bad$bg2020_id[1] <- "060370099001"
    expect_error(assert_step1_readback(bad, original, keys, name), "keys or row order changed")
    bad <- reloaded
    flag <- if (name == "acs") "rent_id" else "x_id"
    bad[[flag]][1] <- FALSE
    expect_error(assert_step1_readback(bad, original, keys, name), "values changed")
    numeric_column <- if (name == "acs") "popE" else "wt_hu"
    bad <- reloaded
    bad[[numeric_column]] <- if (name == "acs") as.double(bad[[numeric_column]]) else as.integer(bad[[numeric_column]])
    expect_error(assert_step1_readback(bad, original, keys, name), "column types changed")
  }
  bad <- acs
  bad$rhuE[2] <- NaN
  expect_error(assert_step1_readback(bad, acs, "bg2020_id", "ACS"), "values changed")
  bad <- acs
  bad$rhuE[2] <- 0
  expect_error(assert_step1_readback(bad, acs, "bg2020_id", "ACS"), "values changed")
  for (column in weights) {
    bad <- crosswalk
    bad[[column]][1] <- bad[[column]][1] + 1e-12
    bad[[column]][2] <- bad[[column]][2] - 1e-12
    quiet(assert_bg_crosswalk(bad))
    path <- file.path(tmp_dir, "changed_weight.feather")
    write_feather(bad, path)
    expect_error(assert_step1_readback(read_feather(path), crosswalk,
                                      c("bg2020_id", "tr2010_id"), "Crosswalk"), "values changed")
  }
  cat("Passed: exact Feather preservation and detection of altered rows, keys, schemas, missingness, flags, and tiny weight changes.\n")

  # Execute the actual import/save/readback chunks with a local API stub and CSV.
  env <- new.env(parent = globalenv())
  env$block_group_vars <- variables
  env$data_dir <- paste0(tmp_dir, "/")
  env$raw_dir <- file.path(tmp_dir, "fixtures")
  env$get_acs <- function(geography, state, variables, year, output, survey) {
    stopifnot(geography == "block group", state == "CA", year == 2024,
              output == "wide", survey == "acs5", identical(variables, mapping$block_group_vars))
    rename(select(acs, -rent_id), GEOID = bg2020_id)
  }
  quiet(eval(chunks[["download-acs-bg-24"]], env))
  quiet(eval(chunks[["save-acs-bg-24"]], env))
  csv_dir <- file.path(env$raw_dir, "nhgis", "nhgis_bg2020_tr2010_06")
  dir.create(csv_dir, recursive = TRUE)
  csv_path <- file.path(csv_dir, "nhgis_bg2020_tr2010_06.csv")
  raw_crosswalk <- crosswalk |>
    select(-x_id) |>
    rename(bg2020ge = bg2020_id, tr2010ge = tr2010_id)
  write_csv(raw_crosswalk, csv_path)
  quiet(eval(chunks[["import-xwalk-bg-tr"]], env))
  stopifnot(identical(env$xwalk_bg_24, crosswalk),
            identical(env$bg_coverage_24$summary$n_bg, c(1L, 1L)),
            env$xbg_n == nrow(crosswalk), env$acs_bg_24_n == nrow(acs))
  env$acs24_bg_out <- read_feather(file.path(tmp_dir, "acs_step1_2024_block_group.feather"))
  env$xbg_out <- read_feather(file.path(tmp_dir, "xwalk_bg24_tr10.feather"))
  quiet(eval(chunks[["validate-bg-readback"]], env))
  stopifnot(identical(env$acs24_bg_out[names(acs)], acs),
            all(rent_evidence_columns() %in% names(env$acs24_bg_out)),
            all(!env$acs24_bg_out$rent_evidence_available),
            identical(env$xbg_reloaded_weight_sums, env$xbg_weight_sums))

  # A failed pre-save check must leave an existing file unchanged.
  bg_path <- file.path(tmp_dir, "acs_step1_2024_block_group.feather")
  xwalk_path <- file.path(tmp_dir, "xwalk_bg24_tr10.feather")
  bg_fingerprint <- tools::md5sum(bg_path)
  xwalk_fingerprint <- tools::md5sum(xwalk_path)
  env$get_acs <- function(...) rename(select(bind_rows(acs, acs[1, ]), -rent_id), GEOID = bg2020_id)
  expect_error(eval(chunks[["download-acs-bg-24"]], env), "duplicate BG keys")
  expect_error(eval(chunks[["save-acs-bg-24"]], env), "duplicate BG keys")
  for (bad_csv in list(
    bind_rows(raw_crosswalk, raw_crosswalk[3, ]),
    mutate(raw_crosswalk, bg2020ge = replace(bg2020ge, 1, "60370001001")),
    mutate(raw_crosswalk, wt_hu = replace(wt_hu, 1, Inf)),
    mutate(raw_crosswalk, wt_hu = replace(wt_hu, 4, 0.9))
  )) {
    write_csv(bad_csv, csv_path)
    expect_error(eval(chunks[["import-xwalk-bg-tr"]], env), "crosswalk:")
    stopifnot(identical(tools::md5sum(xwalk_path), xwalk_fingerprint))
  }
  stopifnot(identical(tools::md5sum(bg_path), bg_fingerprint))
  cat("Passed: notebook checks run before saving, CSV leading zeros survive, coverage gaps remain diagnostic, and readback passes.\n")
})

cat("All Step 1 input QA tests passed. No ACS API calls or canonical output writes.\n")
