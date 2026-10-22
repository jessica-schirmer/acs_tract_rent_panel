# Bounded, read-only comparison for the previously reported rent corrections.
# Rscript --vanilla tests/report_rent_expected_changes.R docs [preserved-panel-path]
# Writes new diagnostic CSVs only; refuses to replace existing reports.
suppressPackageStartupMessages({ library(here); library(dplyr); library(arrow) })
source(here::here("R", "rent_metadata.R"))
source(here::here("R", "assemble_helpers.R"))

args <- commandArgs(trailingOnly = TRUE)
report_dir <- if (length(args)) args[1] else tempfile("expected-rent-changes-")
output_names <- c("acs_rent_expected_tract_changes.csv", "acs_rent_expected_change_input_manifest.csv")
stopifnot("Preserve existing reports; choose another output directory" =
            !any(file.exists(file.path(report_dir, output_names))))
data_dir <- here::here("..", "..", "..", "data")
panel_path <- if (length(args) > 1L) normalizePath(args[2], mustWork = TRUE) else file.path(data_dir, "acs_full.feather")
audit_dir <- here::here("..", "..", "analysis", "tract_rent_acs", "outputs", "tables", "acs_rent_flags")
paths <- c(
  panel = panel_path,
  native = file.path(data_dir, "acs_step1_2024_tract.feather"),
  bg = file.path(data_dir, "acs_step1_2024_block_group.feather"),
  allocation = file.path(data_dir, "xwalk_bg24_tr10.feather"),
  common = file.path(data_dir, "tract_ADU_ACS_combined.feather"),
  evidence = here::here("docs", "acs_rent_native_2024_evidence.csv"),
  coverage = here::here("docs", "acs_rent_coverage_tract_changes.csv"),
  coverage_sources = here::here("docs", "acs_rent_coverage_source_changes.csv"),
  coverage_manifest = here::here("docs", "acs_rent_metadata_input_manifest.csv"),
  audit = file.path(audit_dir, "tract_status.csv"),
  audit_manifest = file.path(audit_dir, "input_manifest.csv"),
  classifier = here::here("R", "rent_metadata.R"),
  aggregation_helpers = here::here("R", "assemble_helpers.R"),
  quality_rule = here::here("..", "..", "analysis", "tract_rent_acs", "01_fe_rent.Rmd"),
  diagnostic_script = here::here("tests", "report_rent_expected_changes.R"))
before <- tools::md5sum(paths)
stopifnot(!anyNA(before))
same_numeric <- function(x, y) {
  all((is.na(x) & is.na(y)) |
        (!is.na(x) & !is.na(y) & abs(x - y) <= 1e-10 * pmax(1, abs(x), abs(y))))
}
csv <- function(path, key = "tr2010_id") {
  read.csv(path, colClasses = setNames("character", key), na.strings = c("", "NA"),
           stringsAsFactors = FALSE, check.names = FALSE)
}
coverage <- csv(paths[["coverage"]])
coverage_sources <- csv(paths[["coverage_sources"]], "bg2020_id")
evidence <- read.csv(paths[["evidence"]], stringsAsFactors = FALSE,
  colClasses = c(GEOID = "character", rent_source_e = "character", rent_source_ea = "character",
                 rent_source_m = "character", rent_source_ma = "character"))
audit <- read.csv(paths[["audit"]], stringsAsFactors = FALSE, na.strings = c("", "NA"),
                  colClasses = c(tr2010_id = "character", tr2020_id = "character"))
# Both saved checks must describe the same canonical artifact versions.
for (manifest_path in paths[c("coverage_manifest", "audit_manifest")]) {
  manifest <- read.csv(manifest_path, stringsAsFactors = FALSE)
  index <- match(c("acs_full.feather", basename(paths[2:5])), basename(manifest$path))
  stopifnot("Saved comparison inputs have changed; review versions first" =
              !anyNA(index) && identical(unname(before[1:5]), manifest$md5[index]))
}

panel <- read_feather(paths[["panel"]], col_select = all_of(c(
  "tr2010_id", "tr2020_id", "acs_source_24", "geo_consistent", "interp_rent",
  "tc_flag_rent_24", "pct_miss_rent", "rentE_16", "rentCV_16", "tc_flag_rent")))
resolved_ids <- panel |>
  filter(acs_source_24 == "tract", tr2020_id %in% evidence$GEOID) |> pull(tr2010_id)
boundary_id <- "06081601501" # Named audit case requested by the analyst.
target_ids <- union(union(coverage$tr2010_id, resolved_ids), boundary_id)
panel <- panel |> filter(tr2010_id %in% target_ids) |> arrange(tr2010_id)
stopifnot(!anyDuplicated(panel$tr2010_id), setequal(panel$tr2010_id, target_ids),
  setequal(panel$tr2020_id[panel$tr2010_id %in% resolved_ids], evidence$GEOID),
  identical(panel$acs_source_24, if_else(panel$geo_consistent %in% 1, "tract", "bg_agg")))
common_ids <- read_feather(paths[["common"]], col_select = "tr2010_id")$tr2010_id

# Reclassify only selected native sources; reuse the saved targeted raw request.
native <- read_feather(paths[["native"]], col_select = all_of(c(
  "tr2020_id", "rentE", "rentM", rent_count_columns()))) |>
  filter(tr2020_id %in% panel$tr2020_id[panel$acs_source_24 == "tract"])
resolved <- native |> filter(tr2020_id %in% evidence$GEOID) |>
  retain_rent_evidence(evidence, "tr2020_id") |> prepare_native_rent("24", "tr2020_id")
native_new <- bind_rows(resolved,
  native |> filter(!tr2020_id %in% evidence$GEOID) |> prepare_native_rent("24", "tr2020_id"))
stopifnot(all(resolved$rent_status_24 == "unavailable_other"),
  all(is.na(resolved$rentE)), all(is.na(resolved$tc_flag_rent_24)))
boundary <- native_new |> filter(tr2020_id == boundary_id)
stopifnot(nrow(boundary) == 1L, boundary$rentE == 3500,
  boundary$rent_status_24 == "observed", boundary$tc_flag_rent_24 == 0,
  is.na(boundary$rent_censor_bound_24))

# Allocate only the requested destination tracts, retaining all their contributors.
links <- read_feather(paths[["allocation"]], col_select = all_of(c("tr2010_id", "bg2020_id", "wt_renthu"))) |>
  filter(tr2010_id %in% target_ids)
bg <- read_feather(paths[["bg"]], col_select = all_of(c(
  "bg2020_id", "rhuE", "rentE", "rentM", rent_count_columns()))) |>
  semi_join(distinct(links, bg2020_id), by = "bg2020_id")
bg_new <- prepare_native_rent(bg, "24", "bg2020_id")
allocations <- links |>
  left_join(mutate(bg, source_present = TRUE, old_missing = is.na(rentE) | rentE >= 3500),
            by = "bg2020_id", relationship = "many-to-one") |>
  left_join(transmute(bg_new, bg2020_id, expected_missing = is.na(rentE)),
            by = "bg2020_id", relationship = "many-to-one")
stopifnot(all(allocations$source_present[allocations$wt_renthu > 0] %in% TRUE))
counts <- allocations |> group_by(tr2010_id) |>
  summarise(n_contributing = sum(wt_renthu > 0),
    across(all_of(rent_count_columns()), ~ strict_weighted_sum(.x, wt_renthu)),
    denominator = strict_weighted_sum(rhuE, wt_renthu),
    old_missing_units = strict_weighted_sum(if_else(old_missing, rhuE, 0), wt_renthu),
    expected_missing_units = strict_weighted_sum(if_else(expected_missing, rhuE, 0), wt_renthu),
    .groups = "drop") |>
  mutate(old_pct_miss_rent = if_else(denominator > 0, old_missing_units / denominator, NA_real_),
    expected_pct_miss_rent = if_else(denominator > 0, expected_missing_units / denominator, NA_real_))
bg_rent <- calc_interp_rent(counts, counts$n_contributing)
native_selected <- panel |> filter(acs_source_24 == "tract") |>
  select(tr2010_id, tr2020_id) |>
  left_join(native_new, by = "tr2020_id", relationship = "one-to-one") |>
  transmute(tr2010_id, expected_interp_rent = rentE, expected_tc_flag_rent_24 = tc_flag_rent_24,
    expected_rent_status_24 = coalesce(rent_status_24, "unresolved"))
bg_selected <- panel |> filter(acs_source_24 == "bg_agg") |> select(tr2010_id) |>
  left_join(bg_rent, by = "tr2010_id", relationship = "one-to-one") |>
  transmute(tr2010_id, expected_interp_rent = interp_rent, expected_tc_flag_rent_24 = tc_flag_rent_24,
    expected_rent_status_24 = coalesce(rent_status_24, "unresolved"))
coverage_reasons <- links |> filter(wt_renthu > 0) |>
  inner_join(coverage_sources, by = "bg2020_id", relationship = "many-to-one") |>
  group_by(tr2010_id) |>
  summarise(coverage_reason = paste(paste0(bg2020_id, ": ", reason), collapse = "; "), .groups = "drop")
comparison <- panel |>
  rename(old_interp_rent = interp_rent, old_tc_flag_rent_24 = tc_flag_rent_24,
         saved_pct_miss_rent = pct_miss_rent) |>
  left_join(bind_rows(native_selected, bg_selected), by = "tr2010_id", relationship = "one-to-one") |>
  left_join(select(counts, tr2010_id, old_pct_miss_rent, expected_pct_miss_rent),
            by = "tr2010_id", relationship = "one-to-one") |>
  left_join(transmute(audit, tr2010_id, old_rent_status_24 = status_2024,
    prior_audit_full_complete_case = full_complete_case,
    prior_audit_quality_complete_case = quality_complete_case,
    prior_audit_rent_qual_flag = rent_qual_flag), by = "tr2010_id", relationship = "one-to-one") |>
  left_join(coverage_reasons, by = "tr2010_id", relationship = "one-to-one") |>
  mutate(in_common_input = tr2010_id %in% common_ids,
    old_status_basis = if_else(is.na(old_rent_status_24), "not_persisted_or_audited", "prior_independent_audit"),
    comparison_group = case_when(tr2010_id %in% resolved_ids ~ "native_evidence_resolution",
      tr2010_id == boundary_id ~ "native_3500_recovery", TRUE ~ "bg_component_coverage"),
    old_miss_rent_flag = case_when(is.na(rentE_16) ~ NA_real_, old_pct_miss_rent > .05 ~ 1, TRUE ~ 0),
    expected_miss_rent_flag = case_when(is.na(rentE_16) ~ NA_real_, expected_pct_miss_rent > .05 ~ 1, TRUE ~ 0),
    missingness_component_changed = old_miss_rent_flag != expected_miss_rent_flag,
    high_cv_flag = case_when(is.na(rentE_16) ~ NA_real_, rentCV_16 > .12 ~ 1, TRUE ~ 0),
    old_rent_qual_flag = case_when(is.na(rentE_16) ~ NA_real_,
      tc_flag_rent == 1 | old_miss_rent_flag == 1 | high_cv_flag == 1 ~ 1, TRUE ~ 0),
    expected_rent_qual_flag = case_when(is.na(rentE_16) ~ NA_real_,
      tc_flag_rent == 1 | expected_miss_rent_flag == 1 | high_cv_flag == 1 ~ 1, TRUE ~ 0),
    expected_common_quality_screen_improvement = in_common_input &
      old_rent_qual_flag %in% 1 & expected_rent_qual_flag %in% 0,
    overall_quality_membership_change = "not_verified_pending_regeneration",
    change_reason = case_when(
      tr2010_id %in% resolved_ids ~ "Original E=-666666666, EA=-, M=-222222222, MA=** establish native source unavailability; numeric rent and top-code flag remain NA",
      tr2010_id == boundary_id ~ "Genuine native 3500; finite MOE and complete below-top median corroborate observed rent; reverse legacy >=3500 censoring",
      TRUE ~ paste0("Correct BG source coverage: ", coverage_reason))) |>
  mutate(change_reason = if_else(comparison_group == "bg_component_coverage" &
    old_tc_flag_rent_24 != expected_tc_flag_rent_24,
    paste0(change_reason, "; selected BG flag now describes final median bin instead of component exposure"), change_reason))

# Reconcile preserved comparisons rather than turning dated counts into targets.
stopifnot(same_numeric(comparison$saved_pct_miss_rent, comparison$old_pct_miss_rent),
  setequal(comparison$tr2010_id[comparison$old_pct_miss_rent != comparison$expected_pct_miss_rent], coverage$tr2010_id))
coverage_index <- match(coverage$tr2010_id, comparison$tr2010_id)
stopifnot(same_numeric(comparison$old_pct_miss_rent[coverage_index], coverage$old_pct_miss_rent),
  same_numeric(comparison$expected_pct_miss_rent[coverage_index], coverage$new_pct_miss_rent),
  identical(comparison$expected_common_quality_screen_improvement[coverage_index], coverage$potential_quality_screen_change))
audited <- comparison$in_common_input
stopifnot(!anyNA(comparison$old_rent_status_24[audited]),
  same_numeric(comparison$old_rent_qual_flag[audited], comparison$prior_audit_rent_qual_flag[audited]))
audit_index <- match(comparison$tr2010_id[audited], audit$tr2010_id)
stopifnot(identical(comparison$acs_source_24[audited], audit$acs_source_24[audit_index]),
  same_numeric(comparison$old_interp_rent[audited], audit$interp_rent[audit_index]),
  same_numeric(comparison$old_tc_flag_rent_24[audited], audit$tc_flag_rent_24[audit_index]))
unchanged_numeric <- comparison$tr2010_id != boundary_id
stopifnot(same_numeric(comparison$old_interp_rent[unchanged_numeric], comparison$expected_interp_rent[unchanged_numeric]),
  is.na(comparison$old_interp_rent[!unchanged_numeric]),
  comparison$expected_interp_rent[!unchanged_numeric] == 3500)
comparison <- comparison |> select(tr2010_id, acs_source_24, tr2020_id, comparison_group,
  old_rent_status_24, old_status_basis, expected_rent_status_24,
  old_tc_flag_rent_24, expected_tc_flag_rent_24, old_interp_rent, expected_interp_rent,
  old_pct_miss_rent, expected_pct_miss_rent, old_miss_rent_flag, expected_miss_rent_flag,
  missingness_component_changed, high_cv_flag, old_rent_qual_flag, expected_rent_qual_flag,
  in_common_input, prior_audit_full_complete_case, prior_audit_quality_complete_case,
  expected_common_quality_screen_improvement, overall_quality_membership_change, change_reason)
stopifnot(nrow(comparison) == length(target_ids), !anyDuplicated(comparison$tr2010_id),
  !anyNA(comparison$expected_rent_status_24), !anyNA(comparison$change_reason))

manifest <- data.frame(input = names(paths), path = unname(paths), md5 = unname(before),
  modified_utc = format(file.info(paths)$mtime, tz = "UTC", usetz = TRUE),
  checked_utc = format(Sys.time(), tz = "UTC", usetz = TRUE))
stopifnot(identical(before, tools::md5sum(paths)))
dir.create(report_dir, recursive = TRUE, showWarnings = FALSE)
write.csv(comparison, file.path(report_dir, output_names[1]), row.names = FALSE, na = "NA")
write.csv(manifest, file.path(report_dir, output_names[2]), row.names = FALSE)
saved <- read.csv(file.path(report_dir, output_names[1]), na.strings = "NA",
  colClasses = c(tr2010_id = "character", tr2020_id = "character"), stringsAsFactors = FALSE)
stopifnot(isTRUE(all.equal(saved, as.data.frame(comparison), tolerance = 1e-12)),
  identical(before, tools::md5sum(paths)))
cat("Expected changes pending regeneration; saved", nrow(comparison), "tract comparisons.\n")
cat("Missingness-screen components changing:", sum(comparison$missingness_component_changed, na.rm = TRUE),
    "| combined quality-screen improvements in current common input:",
    sum(comparison$expected_common_quality_screen_improvement), "\n")
cat("Overall quality-sample membership changes have NOT been verified.\n")
print(filter(comparison, tr2010_id == boundary_id), width = Inf)
cat("All input hashes unchanged. Reports:", normalizePath(report_dir), "\n")
