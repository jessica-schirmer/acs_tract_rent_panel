# Offline path and writer checks; every generated file is under tempdir().
# Run with Rscript tests/test_data_paths.R from the repository root.
library(here)
library(arrow)
source(here::here("R", "data_paths.R"))

expect_error <- function(expr, fragments) {
  error <- tryCatch({ force(expr); NULL }, error = identity)
  stopifnot(inherits(error, "error"),
            all(vapply(fragments, grepl, logical(1), x = conditionMessage(error), fixed = TRUE)))
}

local({
  variables <- c("ACS_RAW_DATA_DIR", "ACS_DATA_DIR")
  previous <- Sys.getenv(variables, unset = NA_character_)
  temporary <- tempfile("acs-paths-")
  dir.create(temporary)
  temporary <- normalizePath(temporary)
  on.exit({
    Sys.unsetenv(variables)
    if (any(!is.na(previous))) do.call(Sys.setenv, as.list(previous[!is.na(previous)]))
    unlink(temporary, recursive = TRUE)
  })
  Sys.unsetenv(variables)
  expect_error(acs_data_dir(), c("ACS_DATA_DIR", ".Renviron.example", "restart R", "README.md#setup"))
  expect_error(acs_data_dir("raw"), c("ACS_RAW_DATA_DIR", "README.md#setup"))
  Sys.setenv(ACS_DATA_DIR = " ")
  expect_error(acs_data_dir(), "ACS_DATA_DIR")

  # Processed-only consumers do not require raw configuration (and vice versa).
  output_dir <- file.path(temporary, "new", "processed data")
  Sys.setenv(ACS_DATA_DIR = output_dir)
  stopifnot(identical(acs_data_dir(), output_dir), !dir.exists(output_dir))
  stopifnot(identical(acs_data_dir(create = TRUE), output_dir), dir.exists(output_dir))
  Sys.unsetenv("ACS_DATA_DIR")
  Sys.setenv(ACS_RAW_DATA_DIR = "schemas")
  stopifnot(identical(acs_data_dir("raw"), normalizePath(here::here("schemas"))))
  Sys.setenv(ACS_DATA_DIR = "tests")
  stopifnot(identical(acs_data_dir(), normalizePath(here::here("tests"))))

  raw_dir <- file.path(temporary, "missing raw")
  Sys.setenv(ACS_RAW_DATA_DIR = raw_dir)
  expected <- file.path(acs_data_dir("raw"), "census", "tab20_tract20_tract10_st06.txt")
  expect_error(acs_require_input(expected, raw = TRUE),
               c("Missing required raw input", expected, "README.md#setup"))
  expect_error(acs_data_dir("raw", create = TRUE), "must not be created")
  stopifnot(!dir.exists(raw_dir), !file.exists(expected))

  blocker <- file.path(temporary, "file-instead-of-directory")
  writeLines("synthetic", blocker)
  Sys.setenv(ACS_DATA_DIR = blocker)
  expect_error(acs_data_dir(), c("must name a directory", blocker))
  expect_error(acs_ensure_output_dir(file.path(blocker, "child")), "Cannot create output directory")

  fixture <- data.frame(tr2010_id = "06001000100", estimate = 12.5)
  # Each stage's existing writer accepts paths with or without a trailing slash.
  for (helper in c("helpers.R", "assemble_helpers.R", "merge_helpers.R")) {
    env <- new.env(parent = environment())
    sys.source(here::here("R", helper), env)
    destination <- file.path(temporary, helper, "nested")
    path <- file.path(destination, "synthetic.feather")
    env$save_data(fixture, destination, basename(path))
    stopifnot(isTRUE(all.equal(as.data.frame(read_feather(path)), fixture)))
    replacement <- capture.output(env$save_data(fixture, paste0(destination, "/"), basename(path)))
    stopifnot(any(grepl("Replacing generated file", replacement, fixed = TRUE)))
  }
  source(here::here("R", "tract_change_helpers.R"), local = TRUE)
  path <- file.path(temporary, "crosswalk", "nested", "synthetic.feather")
  save_tract_crosswalk(fixture, path)
  checksum <- tools::md5sum(path)
  expect_error(save_tract_crosswalk(fixture, path), "Refusing to overwrite")
  stopifnot(identical(tools::md5sum(path), checksum))
})
cat("Passed: explicit/relative/absolute paths, independent settings, missing-input errors, directory creation, and writer safeguards.\n")
