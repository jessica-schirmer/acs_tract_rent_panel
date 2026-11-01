# Read-only checks of the lockfile closure and active package availability.
library(here)
library(renv)

lock <- renv::lockfile_read(here::here("renv.lock"))
packages <- lock$Packages
installed <- installed.packages()
base_packages <- rownames(installed)[installed[, "Priority"] %in% c("base", "recommended")]
dependencies <- renv::dependencies(
  c(list.files(here::here(), pattern = "[.]Rmd$", full.names = TRUE),
    here::here("R"), here::here("tests")), progress = FALSE, errors = "fatal"
)
direct <- setdiff(unique(dependencies$Package), base_packages)
missing_direct <- setdiff(direct, names(packages))
stopifnot("Active packages must be locked" = length(missing_direct) == 0L)

# Support both standard Requirements records and DESCRIPTION-enriched records.
required <- unique(unlist(lapply(packages, function(record) {
  fields <- unlist(record[c("Requirements", "Depends", "Imports", "LinkingTo")])
  sub("[[:space:]]*[(].*", "", fields)
})))
missing_required <- setdiff(required, c(names(packages), base_packages, "R"))
if (length(missing_required)) stop("Missing dependency closure: ", paste(missing_required, collapse = ", "))
for (package in direct) {
  if (!requireNamespace(package, quietly = TRUE)) stop("Cannot load required package: ", package)
  if (packageVersion(package) != package_version(packages[[package]]$Version)) {
    stop("Required package version differs from lockfile: ", package)
  }
}
stopifnot(!"Hmisc" %in% direct, !"Hmisc" %in% names(packages))
cat("Passed:", length(direct), "direct packages load at locked versions;",
    length(packages), "lock entries have a complete required dependency closure.\n")
cat("Pandoc available:", rmarkdown::pandoc_available(), "\n")
