# Run: Rscript --vanilla tests/test_tract_rent_maps.R --preview-dir /tmp/acs_tract_map_preview_r
# Offline synthetic inputs only; no canonical reads, downloads, or empirical exports.
suppressPackageStartupMessages({
  library(here)
  library(arrow)
  library(dplyr)
  library(tibble)
  library(sf)
  library(ggplot2)
  library(patchwork)
  library(digest)
  library(RColorBrewer)
  library(knitr)
  library(ggiraph)
  library(htmlwidgets)
  library(htmltools)
  library(rmarkdown)
  library(xml2)
})
source(here::here("R", "tract_rent_maps.R"))

quiet <- function(expr) {
  invisible(capture.output(value <- force(expr)))
  invisible(value)
}
expect_error <- function(expr, message) {
  error <- tryCatch({ quiet(expr); NULL }, error = identity)
  stopifnot(inherits(error, "error"), grepl(message, conditionMessage(error), fixed = TRUE))
}
notebook_chunk <- function(label) {
  lines <- readLines(here::here("05_map_tract_rents.Rmd"), warn = FALSE)
  start <- which(grepl(paste0("^```\\{r ", label, "([,}])"), lines))
  stopifnot(length(start) == 1L)
  end <- which(seq_along(lines) > start & lines == "```")[1]
  parse(text = lines[seq.int(start + 1L, end - 1L)])
}
tract_id <- function(number) sprintf("06001%06d", number)

# These keyed cases and expected values are preserved from the Python test fixture.
panel <- tibble(
  tr2010_id = tract_id(1:11),
  rentE_16 = c(1000, 2000, 1500, NA, 1800, NA, 1700, 0, 1800, 3000, NA),
  interp_rent = c(1500, 1400, 1500, 2000, NA, 1600, NA, 1500, 0, 3500, NA),
  rent_status_16 = c("observed", "observed", "observed", "top_coded", "observed",
                     "unavailable_other", "observed", "observed", "observed", "observed", "unresolved"),
  rent_status_24 = c("observed", "observed", "observed", "observed", "top_coded",
                     "observed", "unresolved", "observed", "observed", "observed", "top_coded"),
  geo_consistent = as.double((1:11) %% 2)
) |>
  mutate(interp_rentPOST = interp_rent / if_else(rentE_16 > 0, rentE_16, NA_real_),
         acs_source_24 = if_else(geo_consistent == 1, "tract", "bg_agg"))
for (year in c("16", "24")) {
  status <- panel[[paste0("rent_status_", year)]]
  panel[[paste0("tc_flag_rent_", year)]] <- case_when(status == "top_coded" ~ 1, status == "observed" ~ 0, .default = NA_real_)
  panel[[paste0("rent_censor_bound_", year)]] <- if_else(status == "top_coded", if (year == "16") 3500 * 1.307 else 3500, NA_real_)
}
panel <- bind_rows(panel, mutate(panel[1, ], tr2010_id = tract_id(13)),
                   mutate(panel[1, ], tr2010_id = "06013000001")) |> select(all_of(map_panel_columns))
box <- function(x, y, size = 1000) st_polygon(list(rbind(c(x, y), c(x + size, y),
  c(x + size, y + size), c(x, y + size), c(x, y))))
boundaries <- st_sf(tr2010_id = tract_id(1:12), ALAND10 = rep(1e6, 12), AWATER10 = rep(0, 12),
  geometry = st_sfc(lapply(0:11, function(i) box((i %% 4) * 1000, (2 - i %/% 4) * 1000)), crs = 3310))
validate_map_panel(panel)
selected <- filter(panel, startsWith(tr2010_id, "06001"))
joined <- join_panel_to_boundaries(boundaries, selected)
mapped <- prepare_map_measures(joined$mapped)
expected <- tibble(tr2010_id = tract_id(1:12),
  baseline_status = c("value", "value", "value", "top_coded", "value", "unavailable",
                      "value", "value", "value", "value", "unavailable", "unavailable"),
  change_status = c("value", "value", "value", "top_coded", "top_coded", "unavailable",
                    "unavailable", "unavailable", "unavailable", "value", "top_coded", "unavailable"),
  baseline_rent = c(1000, 2000, 1500, NA, 1800, NA, 1700, 0, 1800, 3000, NA, NA),
  rent_change_pct = c(50, -30, 0, NA, NA, NA, NA, NA, NA, 100 / 6, NA, NA))
observed <- st_drop_geometry(mapped) |> select(all_of(names(expected))) |> arrange(tr2010_id)
stopifnot(identical(observed$tr2010_id, expected$tr2010_id),
  identical(observed$baseline_status, expected$baseline_status), identical(observed$change_status, expected$change_status),
  map_values_equal(observed$baseline_rent, expected$baseline_rent),
  map_values_equal(observed$rent_change_pct, expected$rent_change_pct),
  identical(display_summary(mapped)$counts$baseline, c(8L, 1L, 3L)),
  identical(display_summary(mapped)$counts$change, c(4L, 3L, 5L)),
  nrow(mapped) == nrow(boundaries), identical(mapped$tr2010_id, boundaries$tr2010_id),
  sum(joined$coverage$coverage == "matched") == 11,
  identical(joined$coverage$tr2010_id[joined$coverage$coverage == "panel_only"], tract_id(13)),
  identical(joined$coverage$tr2010_id[joined$coverage$coverage == "boundary_only"], tract_id(12)))
empty_join <- prepare_map_measures(join_panel_to_boundaries(boundaries, selected[0, ])$mapped)
stopifnot(all(empty_join$baseline_status == "unavailable"), all(empty_join$change_status == "unavailable"))
cat("Passed: keyed Python fixture parity, zero/3500 rents, precedence, and unmatched join coverage.\n")

expect_error(validate_map_panel(select(panel, -rent_status_24)), "canonical fields")
expect_error(validate_map_panel(bind_rows(panel, panel[1, ])), "duplicate tract IDs")
expect_error(validate_map_panel(mutate(panel, tr2010_id = as.numeric(tr2010_id))), "California GEOIDs")
expect_error(validate_map_panel(mutate(panel, rentE_16 = as.character(rentE_16))), "must be numeric")
for (case in list(list("tc_flag_rent_24", 1, 1), list("rentE_16", 1, Inf),
                  list("rent_status_24", 1, NA_character_), list("interp_rentPOST", 1, 50),
                  list("rent_censor_bound_16", 4, 3500), list("acs_source_24", 1, "bg_agg"),
                  list("interp_rent", 5, 3500))) {
  broken <- panel
  broken[[case[[1]]]][case[[2]]] <- case[[3]]
  expect_error(validate_map_panel(broken), "")
}
unknown_geo <- panel
unknown_geo$geo_consistent[c(1, 2)] <- c(NA, 9)
unknown_geo$acs_source_24[c(1, 2)] <- "bg_agg"
validate_map_panel(unknown_geo)
expect_error(join_panel_to_boundaries(rbind(boundaries, boundaries[1, ]), selected), "duplicate tract IDs")
expect_error(join_panel_to_boundaries(boundaries, bind_rows(selected, selected[1, ])), "duplicate tract IDs")
expect_error(county_scope("1"), "three-character")
stopifnot(identical(county_scope("013"), list(name = "Contra Costa", suffix = "contra_costa")))

# Water-only multipart geometry extends far west; unknown, zero/zero, and mixed areas remain.
water_boundaries <- boundaries
water_boundaries$ALAND10[c(2, 6, 12)] <- c(0, NA, 0)
water_boundaries$AWATER10[c(5, 9, 12)] <- c(100, NA, 300)
st_geometry(water_boundaries)[12] <- st_sfc(st_multipolygon(list(
  unclass(box(-9000, 0, 100)), unclass(box(-7000, 1000, 100)), unclass(box(-5000, 2000, 100))
)), crs = 3310)
water_mapped <- prepare_map_measures(join_panel_to_boundaries(water_boundaries, selected)$mapped)
before <- water_mapped
water_only <- confirmed_water_only(water_mapped)
plot_data <- water_mapped[!water_only, ]
stopifnot(identical(which(water_only), 12L), identical(water_mapped, before),
  identical(plot_data, water_mapped[1:11, ]), !any(confirmed_water_only(select(water_mapped, -ALAND10))),
  all(water_mapped$tr2010_id[which(water_mapped$ALAND10 > 0)] %in% plot_data$tr2010_id),
  identical(display_summary(plot_data)$counts$baseline, c(8L, 1L, 2L)),
  identical(display_summary(plot_data)$counts$change, c(4L, 3L, 4L)))
top_water <- water_mapped
top_water$ALAND10[4] <- 0
top_water$AWATER10[4] <- 100
stopifnot(identical(which(confirmed_water_only(top_water)), c(4L, 12L)))
cat("Passed: water-only exclusion, multipart omission, and retained unknown/mixed/zero-area tracts.\n")

temporary <- tempfile("acs-map-test-")
dir.create(temporary)
source_dir <- file.path(temporary, "source")
dir.create(source_dir)
stem <- "tl_2010_06001_tract10"
source_boundaries <- water_boundaries |>
  st_transform(4269) |> rename(GEOID10 = tr2010_id) |> mutate(STATEFP10 = "06", COUNTYFP10 = "001")
st_write(source_boundaries, file.path(source_dir, paste0(stem, ".shp")), quiet = TRUE)
archive <- file.path(source_dir, paste0(stem, ".zip"))
quiet(utils::zip(archive, list.files(source_dir, full.names = TRUE), flags = "-jq"))
validate_boundary_archive(archive, "001")
expect_error(validate_boundary_archive(archive, "013"), "Invalid 2010 tract archive")

# Exercise the download/cache path with a local ZIP, so the test stays offline.
test_cache <- cache_boundaries
environment(test_cache) <- new.env(parent = environment(cache_boundaries))
environment(test_cache)$boundary_base_url <- paste0("file://", source_dir)
cache_dir <- file.path(temporary, "cache")
cached <- quiet(test_cache(cache_dir, "001"))
stopifnot(identical(readBin(cached, "raw", file.info(cached)$size), readBin(archive, "raw", file.info(archive)$size)))
environment(test_cache)$boundary_base_url <- "invalid://must-not-download"
stopifnot(identical(quiet(test_cache(cache_dir, "001")), cached))
loaded <- load_boundaries(cached, "001")
stopifnot(identical(loaded$tr2010_id, water_boundaries$tr2010_id),
  identical(which(confirmed_water_only(loaded)), 12L), st_crs(loaded)$epsg == 3310)
expect_error(load_boundaries(cached, "001", "EPSG:4326"), "projected CRS")

bad_source <- file.path(temporary, "bad-source")
dir.create(bad_source)
writeLines("not a ZIP", file.path(bad_source, paste0(stem, ".zip")))
environment(test_cache)$boundary_base_url <- paste0("file://", bad_source)
expect_error(suppressWarnings(test_cache(file.path(temporary, "bad-cache"), "001")), "")
stopifnot(!file.exists(file.path(temporary, "bad-cache", paste0(stem, ".zip"))))
missing_area_dir <- file.path(temporary, "missing-area")
dir.create(missing_area_dir)
st_write(select(source_boundaries, -ALAND10, -AWATER10), file.path(missing_area_dir, paste0(stem, ".shp")), quiet = TRUE)
missing_archive <- file.path(missing_area_dir, paste0(stem, ".zip"))
quiet(utils::zip(missing_archive, list.files(missing_area_dir, full.names = TRUE), flags = "-jq"))
missing_area <- load_boundaries(missing_archive, "001")
stopifnot(all(is.na(missing_area$ALAND10)), all(is.na(missing_area$AWATER10)), !any(confirmed_water_only(missing_area)))
cat("Passed: cached ZIP reuse/checksums, staged download failure, vintage/CRS, and missing area fields.\n")

# Diagonal lines must not fill polygon holes or spill into neighboring tracts.
outer <- unclass(box(0, 0))[[1]]
inner <- unclass(box(300, 300, 400))[[1]][5:1, ]
with_hole <- st_sf(geometry = st_sfc(st_polygon(list(outer, inner)), crs = 3310))
hatches <- map_hatch_lines(with_hole, st_bbox(with_hole), 100)
hole <- st_sfc(box(301, 301, 398), crs = 3310)
stopifnot(!any(lengths(st_intersects(hatches, hole)) > 0))
stopifnot(all(st_geometry_type(hatches) %in% c("LINESTRING", "MULTILINESTRING")))

grDevices::png(file.path(temporary, "rendering_device.png"), width = 1400, height = 900,
               type = if (capabilities("aqua")) "quartz" else "cairo")
preview <- draw_paired_maps(plot_data, "Test County", synthetic = TRUE)
layouts <- lapply(preview$panels, function(p) ggplot_build(p)$layout$panel_params[[1]])
stopifnot(identical(layouts[[1]]$x_range, layouts[[2]]$x_range),
  identical(layouts[[1]]$y_range, layouts[[2]]$y_range),
  identical(unname(layouts[[1]]$x_range), c(-100, 4100)),
  identical(unname(layouts[[1]]$y_range), c(-100, 3100)))
for (p in preview$panels) {
  for (layer in p$layers) {
    if ("tr2010_id" %in% names(layer$data)) stopifnot(!tract_id(12) %in% layer$data$tr2010_id)
  }
}
extreme <- plot_data
extreme$rent_change_pct[1] <- 12000
extreme_maps <- draw_paired_maps(extreme, "Test County", synthetic = TRUE)
stopifnot(identical(extreme_maps$panels[[2]]$scales$get_scales("fill")$limits, c(-12000, 12000)))
for (row in c(12, 1, 2, 3, 4, 8)) {
  one <- mapped[row, ]
  maps <- draw_paired_maps(one, "Test County", synthetic = TRUE)
  if (!is.na(one$rent_change_pct)) {
    limits <- maps$panels[[2]]$scales$get_scales("fill")$limits
    stopifnot(limits[1] < 0, limits[2] > 0, limits[1] == -limits[2])
    if (one$rent_change_pct == 0) stopifnot(identical(limits, c(-1, 1)))
  }
  stopifnot(inherits(patchwork::patchworkGrob(maps$figure), "gtable"))
}
exports <- save_paired_figure(preview$figure, file.path(temporary, "synthetic_pair"))
stopifnot(identical(readBin(exports[1], "raw", 8), as.raw(c(137, 80, 78, 71, 13, 10, 26, 10))),
          identical(readChar(exports[2], 4, useBytes = TRUE), "%PDF"))
hashes <- vapply(exports, function(path) digest(file = path, algo = "sha256"), "")
expect_error(save_paired_figure(preview$figure, file.path(temporary, "synthetic_pair")), "Existing figures")
stopifnot(identical(hashes, vapply(exports, function(path) digest(file = path, algo = "sha256"), "")))
cat("Passed: hatch holes, shared extent/all layers, full scales, empty/constant panels, PNG/PDF, and overwrite guard.\n")
invisible(grDevices::dev.off())

# Exercise every display status and multipart components with the same prepared frame.
hover_data <- plot_data
for (row in c(1, 4, 6)) {
  bounds <- st_bbox(hover_data[row, ])
  st_geometry(hover_data)[row] <- st_sfc(st_multipolygon(list(
    unclass(box(bounds["xmin"], bounds["ymin"], 350)),
    unclass(box(bounds["xmax"] - 350, bounds["ymax"] - 350, 350))
  )), crs = 3310)
}
hover_before <- hover_data
baseline_hover <- map_hover_data(hover_data, "baseline")
change_hover <- map_hover_data(hover_data, "change")
stopifnot(identical(hover_data, hover_before),
  identical(st_geometry(baseline_hover), st_geometry(hover_data)),
  !anyDuplicated(c(baseline_hover$map_data_id, change_hover$map_data_id)),
  identical(baseline_hover$map_tooltip[1], "Tract GEOID: 06001000001<br>Baseline rent: $1,000 (2024 dollars)"),
  identical(change_hover$map_tooltip[1:3], c(
    "Tract GEOID: 06001000001<br>Inflation-adjusted rent change: +50.0%",
    "Tract GEOID: 06001000002<br>Inflation-adjusted rent change: -30.0%",
    "Tract GEOID: 06001000003<br>Inflation-adjusted rent change: 0.0%")),
  endsWith(change_hover$map_tooltip[10], "+16.7%"),
  endsWith(baseline_hover$map_tooltip[8], "$0 (2024 dollars)"),
  endsWith(baseline_hover$map_tooltip[4], "Top-coded"),
  endsWith(baseline_hover$map_tooltip[6], "Unavailable"),
  endsWith(baseline_hover$map_tooltip[5], "$1,800 (2024 dollars)"),
  endsWith(change_hover$map_tooltip[5], "Top-coded"),
  endsWith(baseline_hover$map_tooltip[11], "Unavailable"),
  endsWith(change_hover$map_tooltip[11], "Top-coded"))
placeholders <- hover_data
placeholders$baseline_rent[placeholders$baseline_status != "value"] <- 4574.5
placeholders$rent_change_pct[placeholders$change_status != "value"] <- 99999
stopifnot(identical(map_hover_data(placeholders, "baseline")$map_tooltip, baseline_hover$map_tooltip),
          identical(map_hover_data(placeholders, "change")$map_tooltip, change_hover$map_tooltip))
fractional_rent <- hover_data[1, ]
fractional_rent$baseline_rent <- 1306.6
stopifnot(endsWith(map_hover_data(fractional_rent, "baseline")$map_tooltip, "$1,307 (2024 dollars)"))

hover_maps <- draw_paired_maps(hover_data, "Test County", synthetic = TRUE, hover = TRUE)
static_maps <- draw_paired_maps(hover_data, "Test County", synthetic = TRUE)
for (i in 1:2) {
  interactive_build <- ggplot_build(hover_maps$panels[[i]])
  static_build <- ggplot_build(static_maps$panels[[i]])
  for (field in c("x_range", "y_range", "crs", "default_crs")) {
    stopifnot(identical(interactive_build$layout$panel_params[[1]][[field]],
                        static_build$layout$panel_params[[1]][[field]]))
  }
  stopifnot(identical(interactive_build$data[seq_along(static_build$data)], static_build$data))
  overlay <- tail(hover_maps$panels[[i]]$layers, 1)[[1]]
  stopifnot(identical(overlay$data$tr2010_id, hover_data$tr2010_id),
            identical(overlay$aes_params$fill, "transparent"), is.na(overlay$aes_params$colour))
}
widget <- draw_paired_map_widget(hover_data, "Test County", synthetic = TRUE)
stopifnot(widget$x$settings$zoom$min == 1, widget$x$settings$zoom$max == 1,
  !widget$x$settings$zoom$default_on, widget$x$settings$select$type == "none",
  !widget$x$settings$hover$reactive, !widget$x$settings$hover$linked,
  all(c("selection", "zoom", "misc") %in% widget$x$settings$toolbar$hidden),
  widget$x$settings$sizing$rescale, widget$x$settings$sizing$width == 1,
  widget$sizingPolicy$browser$defaultWidth == "100%")
svg <- read_xml(widget$x$html)
stopifnot(sum(startsWith(xml_text(xml_find_all(svg, "//*[local-name()='text']")), "Source:")) == 1L)
hit_targets <- xml_find_all(svg, "//*[@data-id]")
target_ids <- xml_attr(hit_targets, "data-id")
stopifnot(setequal(target_ids, c(baseline_hover$map_data_id, change_hover$map_data_id)),
          !any(grepl(tract_id(12), target_ids, fixed = TRUE)))
for (labels in list(baseline_hover, change_hover)) {
  for (row in seq_len(nrow(labels))) {
    nodes <- hit_targets[target_ids == labels$map_data_id[row]]
    stopifnot(length(nodes) >= 1L,
              all(xml_attr(nodes, "title") == as.character(htmlEscape(labels$map_tooltip[row]))))
    if (st_geometry_type(labels)[row] == "MULTIPOLYGON") {
      stopifnot(length(nodes) == length(st_geometry(labels)[[row]]))
    }
  }
}
html_export <- save_paired_html(widget, file.path(temporary, "synthetic_hover"))
html_doc <- read_html(html_export)
assets <- xml_attr(xml_find_all(html_doc, "//script[@src]"), "src")
assets <- c(assets, xml_attr(xml_find_all(html_doc, "//link[@rel='stylesheet']"), "href"))
stopifnot(all(startsWith(assets, "data:")),
          !dir.exists(file.path(temporary, "synthetic_hover_files")),
          identical(hashes, vapply(exports, function(path) digest(file = path, algo = "sha256"), "")))
html_hash <- digest(file = html_export, algo = "sha256")
expect_error(save_paired_html(widget, file.path(temporary, "synthetic_hover")), "Existing figure")
stopifnot(identical(html_hash, digest(file = html_export, algo = "sha256")))
cat("Passed: panel-specific hover labels/statuses, censored placeholders, unchanged static layers/extents, SVG targets, self-contained HTML, and overwrite guard.\n")

# Execute the actual notebook chunks with only synthetic paths after configuration.
lines <- readLines(here::here("05_map_tract_rents.Rmd"), warn = FALSE)
headings <- grep("^# [0-9]+\\. ", lines, value = TRUE)
stopifnot(identical(sub("^# ([0-9]+)\\..*", "\\1", headings), as.character(1:6)))
chunks <- sub("^```\\{r ([^,}]+).*", "\\1", grep("^```\\{r ", lines, value = TRUE))
invisible(lapply(chunks, notebook_chunk))
synthetic_panel <- file.path(temporary, "synthetic_panel.feather")
write_feather(panel, synthetic_panel)
env <- new.env(parent = globalenv())
grDevices::png(file.path(temporary, "synthetic_inline.png"), width = 1400, height = 900,
               type = if (capabilities("aqua")) "quartz" else "cairo")
tryCatch({
  for (label in chunks) {
    quiet(eval(notebook_chunk(label), env))
    if (label == "load-packages") {
      env$draw_paired_maps <- local({
        draw <- get("draw_paired_maps", envir = env)
        function(mapped, county_label, synthetic = FALSE, hover = FALSE) {
          draw(mapped, "Test County", synthetic = TRUE, hover = hover)
        }
      })
    }
    if (label == "configuration") {
      env$panel_path <- synthetic_panel
      env$boundary_cache_dir <- cache_dir
      env$output_stem <- file.path(temporary, "synthetic_notebook")
    }
  }
}, finally = grDevices::dev.off())
stopifnot(nrow(env$mapped) == 12, nrow(env$plot_data) == 11, env$omitted_water_only_count == 1,
          identical(env$status_counts$change, c(4L, 3L, 4L)), all(file.exists(env$export_paths)),
          length(env$export_paths) == 3L, endsWith(env$html_path, ".html"))
cat("Passed: parsing, contiguous sections, and every notebook chunk on synthetic Feather/2010 boundaries.\n")

args <- commandArgs(trailingOnly = TRUE)
if (length(args)) {
  stopifnot(length(args) == 2L, args[1] == "--preview-dir")
  paths <- save_paired_figure(static_maps$figure, file.path(args[2], "synthetic_tract_rents"), overwrite = TRUE)
  paths <- c(paths, save_paired_html(widget, file.path(args[2], "synthetic_tract_rents"), overwrite = TRUE))
  cat("Synthetic preview only:", paste(paths, collapse = ", "), "\n")
}
unlink(temporary, recursive = TRUE)
cat("All tract rent map checks passed.\n")
