# Read-only source checks and the analyst-requested BG coverage impact report.
# Rscript --vanilla tests/check_rent_metadata_inputs.R /private/tmp/rent-metadata-qa
# Reads only rent evidence/counts/keys; never executes notebooks or writes data/.
# Run against the pre-regeneration panel: saved coverage must match the old rule.
suppressPackageStartupMessages({ library(here); library(dplyr); library(tidyr); library(arrow) })
source(here::here("R", "rent_metadata.R"))
source(here::here("R", "assemble_helpers.R"))
source(here::here("R", "geography_qa.R"))
args <- commandArgs(trailingOnly = TRUE)
report_dir <- if (length(args)) args[1] else tempfile("rent-metadata-qa-")
dir.create(report_dir, recursive = TRUE, showWarnings = FALSE)
data_dir <- here::here("..", "..", "..", "data")
paths <- file.path(data_dir, c("acs_step1_2016_tract.feather", "acs_step1_2024_tract.feather",
  "acs_step1_2024_block_group.feather", "xwalk_bg24_tr10.feather", "acs_full.feather",
  "tract_ADU_ACS_combined.feather"))
before <- tools::md5sum(paths)
source_columns <- c("rentE", "rentM", rent_count_columns())
native24 <- read_feather(paths[2], col_select = all_of(c("tr2020_id", source_columns)))
evidence <- read.csv(here::here("docs", "acs_rent_native_2024_evidence.csv"),
                     colClasses = c(GEOID = "character", rent_source_e = "character",
                       rent_source_ea = "character", rent_source_m = "character", rent_source_ma = "character"))
five <- native24 |> filter(tr2020_id %in% evidence$GEOID)
five <- retain_rent_evidence(five, evidence, "tr2020_id") |> prepare_native_rent("24", "tr2020_id")
stopifnot(nrow(five) == nrow(evidence), all(five$rent_status_24 == "unavailable_other"),
          all(is.na(five$rentE)), all(is.na(five$tc_flag_rent_24)))
boundary <- native24 |> filter(rentE == 3500) |> prepare_native_rent("24", "tr2020_id")
stopifnot(all(boundary$rentE[boundary$rent_status_24 == "observed"] == 3500))
native16 <- read_feather(paths[1], col_select = all_of(c("tr2010_id", source_columns))) |>
  filter(rentE %in% c(3500, 3501)) |> prepare_native_rent("16", "tr2010_id")
stopifnot(all(native16$rent_censor_bound_16[native16$rent_status_16 == "top_coded"] == 3500))

links <- read_feather(paths[4], col_select = all_of(c("bg2020_id", "tr2010_id", "wt_renthu"))) |>
  select_target_counties(tr2010_id, step2_target_counties()$target_counties)
bg <- read_feather(paths[3], col_select = all_of(c("bg2020_id", "rhuE", source_columns))) |>
  semi_join(distinct(links, bg2020_id), by = "bg2020_id")
corrected <- prepare_native_rent(bg, "24", "bg2020_id")
source_changes <- tibble(bg2020_id = bg$bg2020_id, raw_rent = bg$rentE,
  old_missing = is.na(bg$rentE) | bg$rentE >= 3500,
  new_missing = is.na(corrected$rentE), rent_status_24 = corrected$rent_status_24,
  reason = corrected$rent_status_reason) |>
  filter(old_missing != new_missing)
affected_ids <- links |> filter(wt_renthu > 0) |>
  semi_join(source_changes, by = "bg2020_id") |> distinct(tr2010_id)
allocations <- links |> semi_join(affected_ids, by = "tr2010_id") |>
  left_join(transmute(bg, bg2020_id, rhuE, old_missing = is.na(rentE) | rentE >= 3500),
            by = "bg2020_id", relationship = "many-to-one") |>
  left_join(transmute(corrected, bg2020_id, new_missing = is.na(rentE)),
            by = "bg2020_id", relationship = "many-to-one")
report <- allocations |> group_by(tr2010_id) |>
  summarise(denominator = strict_weighted_sum(rhuE, wt_renthu),
    old_units = strict_weighted_sum(if_else(old_missing, rhuE, 0), wt_renthu),
    new_units = strict_weighted_sum(if_else(new_missing, rhuE, 0), wt_renthu), .groups = "drop") |>
  mutate(old_pct_miss_rent = if_else(denominator > 0, old_units / denominator, NA_real_),
         new_pct_miss_rent = if_else(denominator > 0, new_units / denominator, NA_real_),
         delta = new_pct_miss_rent - old_pct_miss_rent,
         old_above_005 = old_pct_miss_rent > .05, new_above_005 = new_pct_miss_rent > .05,
         crosses_005 = old_above_005 != new_above_005,
         crosses_zero = (old_pct_miss_rent > 0) != (new_pct_miss_rent > 0))
panel <- read_feather(paths[5], col_select = all_of(c("tr2010_id", "pct_miss_rent", "rentE_16", "rentCV_16")))
common <- read_feather(paths[6], col_select = "tr2010_id")
report <- report |>
  left_join(rename(panel, saved_pct_miss_rent = pct_miss_rent), by = "tr2010_id", relationship = "one-to-one") |>
  mutate(in_common_input = tr2010_id %in% common$tr2010_id,
    baseline_available = is.finite(rentE_16),
    baseline_cv_above_012 = rentCV_16 > .12,
    potential_quality_screen_change = in_common_input & crosses_005 & baseline_available &
      !(baseline_cv_above_012 %in% TRUE))
stopifnot(all(is.na(report$saved_pct_miss_rent) | abs(report$saved_pct_miss_rent - report$old_pct_miss_rent) < 1e-10))
write.csv(source_changes, file.path(report_dir, "acs_rent_coverage_source_changes.csv"), row.names = FALSE, na = "")
write.csv(report, file.path(report_dir, "acs_rent_coverage_tract_changes.csv"), row.names = FALSE, na = "")
manifest <- data.frame(path = names(before), md5 = unname(before),
                       modified = as.character(file.info(paths)$mtime))
write.csv(manifest, file.path(report_dir, "acs_rent_metadata_input_manifest.csv"), row.names = FALSE)
stopifnot(identical(before, tools::md5sum(paths)))
cat("Five original native E/M pairs match their saved vintage and establish unavailable_other.\n")
cat("Native 2024 boundary rows:", nrow(boundary), "| observed:", sum(boundary$rent_status_24 == "observed"), "\n")
cat("Changed BG coverage sources:", nrow(source_changes), "| affected destination tracts:", nrow(report), "\n")
cat("Tracts crossing .05:", sum(report$crosses_005, na.rm = TRUE),
    "| crossing zero:", sum(report$crosses_zero, na.rm = TRUE),
    "| potential common-input quality-screen changes:", sum(report$potential_quality_screen_change, na.rm = TRUE), "\n")
print(source_changes, n = Inf)
print(report, n = Inf, width = Inf)
cat("All canonical input hashes unchanged. Reports:", report_dir, "\n")
