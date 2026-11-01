# Shared external-data configuration. See README.md#setup.
# Relative settings are anchored to this repository's tracked .here file.

acs_resolve_path <- function(path) {
  if (length(path) != 1L || is.na(path) || !nzchar(trimws(path))) {
    stop("Expected one nonempty path. See README.md#setup.", call. = FALSE)
  }
  path <- path.expand(path)
  if (!grepl("^(/|[A-Za-z]:[/\\\\]|\\\\\\\\)", path)) {
    path <- file.path(here::here(), path)
  }
  normalizePath(path, winslash = "/", mustWork = FALSE)
}

acs_ensure_output_dir <- function(path) {
  if (!dir.exists(path)) dir.create(path, recursive = TRUE, showWarnings = FALSE)
  if (!dir.exists(path)) {
    stop("Cannot create output directory: ", path,
         ". Check permissions and ACS_DATA_DIR; see README.md#setup.", call. = FALSE)
  }
  invisible(path)
}

acs_data_dir <- function(kind = c("processed", "raw"), create = FALSE) {
  kind <- match.arg(kind)
  variable <- if (kind == "raw") "ACS_RAW_DATA_DIR" else "ACS_DATA_DIR"
  value <- Sys.getenv(variable, unset = "")
  if (!nzchar(trimws(value))) {
    stop("Set ", variable, " in your environment or repository-local .Renviron. ",
         "Copy .Renviron.example, fill in the paths, and restart R. ",
         "See README.md#setup.", call. = FALSE)
  }
  path <- acs_resolve_path(value)
  if (file.exists(path) && !dir.exists(path)) {
    stop(variable, " must name a directory: ", path, ". See README.md#setup.", call. = FALSE)
  }
  if (isTRUE(create)) {
    if (kind == "raw") stop("Raw input directories must not be created by the pipeline.", call. = FALSE)
    acs_ensure_output_dir(path)
  }
  path
}

acs_require_input <- function(path, raw = FALSE) {
  if (!file.exists(path) || dir.exists(path)) {
    stop("Missing required ", if (raw) "raw " else "", "input: ", path, ". ",
         if (raw) "Obtain the source file and preserve its subdirectory layout. " else
           "Run the producing notebook and check ACS_DATA_DIR. ",
         "See README.md#setup.", call. = FALSE)
  }
  path
}

acs_prepare_output <- function(path) {
  acs_ensure_output_dir(dirname(path))
  cat(if (file.exists(path)) "Replacing generated file:" else "Writing generated file:", path, "\n")
  path
}
