# Validation and static plotting helpers for 05_map_tract_rents.Rmd.
# Load dplyr, sf, ggplot2, patchwork, digest, and RColorBrewer in the caller.

map_counties <- c(
  "001" = "Alameda", "013" = "Contra Costa", "037" = "Los Angeles",
  "041" = "Marin", "055" = "Napa", "059" = "Orange", "065" = "Riverside",
  "071" = "San Bernardino", "075" = "San Francisco", "081" = "San Mateo",
  "085" = "Santa Clara", "095" = "Solano", "097" = "Sonoma", "111" = "Ventura"
)
map_panel_columns <- c(
  "tr2010_id", "rentE_16", "interp_rent", "interp_rentPOST",
  "rent_status_16", "rent_status_24", "tc_flag_rent_16", "tc_flag_rent_24",
  "rent_censor_bound_16", "rent_censor_bound_24", "acs_source_24", "geo_consistent"
)
map_display_statuses <- c("value", "top_coded", "unavailable")
boundary_base_url <- "https://www2.census.gov/geo/tiger/TIGER2010/TRACT/2010"

county_scope <- function(county_fips) {
  if (!is.character(county_fips) || length(county_fips) != 1L ||
      !county_fips %in% names(map_counties)) {
    stop("Select a three-character county FIPS from map_counties.")
  }
  name <- unname(map_counties[county_fips])
  list(name = name, suffix = gsub(" ", "_", tolower(name), fixed = TRUE))
}

validate_map_tract_ids <- function(ids, context) {
  if (!is.character(ids) || anyNA(ids) || !all(grepl("^06[0-9]{9}$", ids))) {
    stop(context, ": expected nonmissing 11-character California GEOIDs.")
  }
  if (anyDuplicated(ids)) stop(context, ": duplicate tract IDs: ", paste(ids[duplicated(ids)], collapse = ", "))
  invisible(TRUE)
}

# Elementwise tolerance matches the original map's numpy comparisons.
map_values_equal <- function(x, y, rtol = 1e-10, atol = 1e-12) {
  if (length(x) != length(y) || !identical(is.na(x), is.na(y))) return(FALSE)
  keep <- !is.na(x)
  all(is.finite(x[keep]) & is.finite(y[keep]) &
        abs(x[keep] - y[keep]) <= atol + rtol * abs(y[keep]))
}

validate_map_panel <- function(panel) {
  missing <- setdiff(map_panel_columns, names(panel))
  if (length(missing)) stop("Panel lacks current canonical fields: ", paste(missing, collapse = ", "),
                            ". See schemas/acs_full.md.")
  if (!nrow(panel) || anyDuplicated(names(panel))) stop("Panel must be nonempty with distinct column names.")
  validate_map_tract_ids(panel$tr2010_id, "ACS panel (one row per tract, both periods wide)")
  numeric_columns <- setdiff(map_panel_columns, c("tr2010_id", "rent_status_16", "rent_status_24", "acs_source_24"))
  if (!all(vapply(panel[numeric_columns], is.numeric, logical(1)))) {
    stop("Canonical rent, flag, bound, ratio, and geographic flag fields must be numeric.")
  }
  for (year in c("16", "24")) {
    status <- panel[[paste0("rent_status_", year)]]
    flag <- panel[[paste0("tc_flag_rent_", year)]]
    censor <- panel[[paste0("rent_censor_bound_", year)]]
    rent <- panel[[if (year == "16") "rentE_16" else "interp_rent"]]
    bound <- if (year == "16") 3500 * 1.307 else 3500
    if (!all(status %in% c("observed", "top_coded", "unavailable_other", "unresolved"))) {
      stop("Invalid or missing rent_status_", year)
    }
    observed <- status == "observed"
    top <- status == "top_coded"
    valid <- all(is.finite(rent[observed]) & rent[observed] >= 0 & rent[observed] <= bound) &&
      all(is.na(rent[!observed])) && all(!is.na(flag[observed]) & flag[observed] == 0) &&
      all(!is.na(flag[top]) & flag[top] == 1) && all(is.na(flag[!observed & !top])) &&
      map_values_equal(censor[top], rep(bound, sum(top)), rtol = 0, atol = 1e-8) &&
      all(is.na(censor[!top]))
    if (!isTRUE(valid)) stop("Invalid ", year, " rent/status/flag/bound combination; check the canonical producer.")
  }
  expected_source <- ifelse(panel$geo_consistent %in% 1, "tract", "bg_agg")
  if (anyNA(panel$acs_source_24) || !all(panel$acs_source_24 == expected_source)) {
    stop("acs_source_24 disagrees with canonical geographic source selection.")
  }
  expected_ratio <- panel$interp_rent / ifelse(panel$rentE_16 > 0, panel$rentE_16, NA_real_)
  if (!map_values_equal(panel$interp_rentPOST, expected_ratio)) {
    stop("interp_rentPOST does not equal interp_rent / positive rentE_16.")
  }
  invisible(panel)
}

validate_boundary_archive <- function(path, county_fips) {
  stem <- paste0("tl_2010_06", county_fips, "_tract10")
  members <- utils::unzip(path, list = TRUE)$Name
  if (!all(paste0(stem, c(".shp", ".shx", ".dbf", ".prj")) %in% members)) {
    stop("Invalid 2010 tract archive: ", path)
  }
  unzip <- Sys.which("unzip")
  if (!nzchar(unzip)) stop("System unzip is required to verify boundary ZIP checksums.")
  check <- suppressWarnings(system2(unzip, c("-tqq", shQuote(normalizePath(path))), stdout = TRUE, stderr = TRUE))
  if (!is.null(attr(check, "status"))) stop("Invalid 2010 tract archive: ", path, "\n", paste(check, collapse = "\n"))
  invisible(path)
}

cache_boundaries <- function(cache_dir, county_fips) {
  county_scope(county_fips)
  path <- file.path(cache_dir, paste0("tl_2010_06", county_fips, "_tract10.zip"))
  url <- paste0(boundary_base_url, "/", basename(path))
  if (!file.exists(path)) {
    dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
    download <- tempfile("tiger2010-", tmpdir = cache_dir, fileext = ".zip")
    on.exit(unlink(download), add = TRUE)
    old_options <- options(timeout = 45)
    on.exit(options(old_options), add = TRUE)
    message("Downloading Census 2010 tract boundaries: ", url)
    utils::download.file(url, download, mode = "wb", method = "libcurl",
                         headers = c("User-Agent" = "ACS-tract-rent-maps/1.0"))
    validate_boundary_archive(download, county_fips)
    if (!file.copy(download, path, overwrite = FALSE)) stop("Could not create boundary cache: ", path)
  }
  validate_boundary_archive(path, county_fips)
  cat("Boundary source: ", url, "\nCache: ", path,
      "\nSHA-256: ", digest::digest(file = path, algo = "sha256"), "\n", sep = "")
  path
}

load_boundaries <- function(path, county_fips, map_crs = "EPSG:3310") {
  county_scope(county_fips)
  validate_boundary_archive(path, county_fips)
  stem <- paste0("tl_2010_06", county_fips, "_tract10.shp")
  tracts <- sf::st_read(paste0("/vsizip/", normalizePath(path), "/", stem), quiet = TRUE)
  if (!all(c("GEOID10", "STATEFP10", "COUNTYFP10") %in% names(tracts)) ||
      !nrow(tracts) || is.na(sf::st_crs(tracts))) {
    stop("Boundary file lacks the documented 2010 fields, polygons, or CRS.")
  }
  validate_map_tract_ids(tracts$GEOID10, "Census 2010 boundaries")
  if (!isTRUE(all(tracts$STATEFP10 == "06" & tracts$COUNTYFP10 == county_fips &
                  startsWith(tracts$GEOID10, paste0("06", county_fips))))) {
    stop("Boundary file does not match the configured county.")
  }
  # Check source coordinates with GEOS, as in the original planar validation.
  geometry <- sf::st_geometry(tracts)
  if (any(sf::st_is_empty(geometry)) ||
      !isTRUE(all(sf::st_is_valid(sf::st_set_crs(geometry, NA)))) ||
      !all(sf::st_geometry_type(geometry) %in% c("POLYGON", "MULTIPOLYGON"))) {
    stop("Boundary geometry needs analyst review; no polygons were dropped or repaired.")
  }
  for (column in c("ALAND10", "AWATER10")) {
    if (!column %in% names(tracts)) tracts[[column]] <- NA_real_
  }
  tracts <- tracts |>
    dplyr::select(tr2010_id = GEOID10, ALAND10, AWATER10) |>
    sf::st_transform(map_crs)
  if (!isFALSE(sf::st_is_longlat(tracts))) stop("Use a projected CRS for both maps.")
  tracts
}

join_panel_to_boundaries <- function(boundaries, panel) {
  validate_map_tract_ids(boundaries$tr2010_id, "Selected boundaries")
  validate_map_tract_ids(panel$tr2010_id, "Selected ACS panel")
  coverage <- dplyr::full_join(
    tibble::tibble(tr2010_id = boundaries$tr2010_id, boundary = TRUE),
    tibble::tibble(tr2010_id = panel$tr2010_id, panel = TRUE),
    by = "tr2010_id", relationship = "one-to-one", na_matches = "never"
  ) |>
    dplyr::transmute(tr2010_id, coverage = dplyr::case_when(
      boundary & panel ~ "matched", boundary ~ "boundary_only", .default = "panel_only"
    )) |>
    dplyr::arrange(tr2010_id)
  mapped <- dplyr::left_join(boundaries, dplyr::mutate(panel, panel_join = "both"),
                             by = "tr2010_id", relationship = "one-to-one", na_matches = "never") |>
    dplyr::mutate(panel_join = dplyr::coalesce(panel_join, "left_only"))
  stopifnot(nrow(mapped) == nrow(boundaries), !anyDuplicated(mapped$tr2010_id),
            identical(mapped$tr2010_id, boundaries$tr2010_id))
  list(mapped = mapped, coverage = coverage)
}

prepare_map_measures <- function(mapped) {
  baseline <- mapped$rentE_16
  later <- mapped$interp_rent
  baseline_top <- mapped$tc_flag_rent_16 %in% 1
  later_top <- mapped$tc_flag_rent_24 %in% 1
  baseline_valid <- mapped$rent_status_16 %in% "observed" & is.finite(baseline) & baseline >= 0 & !baseline_top
  change_valid <- baseline_valid & baseline > 0 & is.finite(later) & later > 0 &
    mapped$rent_status_24 %in% "observed" & !later_top
  result <- dplyr::mutate(mapped,
    baseline_status = dplyr::case_when(baseline_top ~ "top_coded", baseline_valid ~ "value", .default = "unavailable"),
    change_status = dplyr::case_when(baseline_top | later_top ~ "top_coded", change_valid ~ "value", .default = "unavailable"),
    baseline_rent = dplyr::if_else(baseline_valid, baseline, NA_real_),
    rent_change_pct = 100 * (dplyr::if_else(change_valid, later, NA_real_) /
                             dplyr::if_else(change_valid, baseline, NA_real_) - 1)
  )
  if (!all(is.finite(result$rent_change_pct[change_valid]))) stop("Percentage change overflowed; inspect the positive rent values.")
  for (period in c("baseline", "change")) {
    status <- result[[paste0(period, "_status")]]
    value <- result[[if (period == "baseline") "baseline_rent" else "rent_change_pct"]]
    stopifnot(all(status %in% map_display_statuses), identical(status == "value", !is.na(value)))
  }
  result
}

confirmed_water_only <- function(mapped) {
  if (!all(c("ALAND10", "AWATER10") %in% names(mapped))) return(rep(FALSE, nrow(mapped)))
  !is.na(mapped$ALAND10) & !is.na(mapped$AWATER10) & mapped$ALAND10 == 0 & mapped$AWATER10 > 0
}

display_summary <- function(mapped) {
  counts <- tibble::tibble(display_status = map_display_statuses,
    baseline = as.integer(table(factor(mapped$baseline_status, levels = map_display_statuses))),
    change = as.integer(table(factor(mapped$change_status, levels = map_display_statuses))))
  ranges <- dplyr::bind_rows(lapply(c("baseline_rent", "rent_change_pct"), function(column) {
    values <- mapped[[column]][!is.na(mapped[[column]])]
    tibble::tibble(measure = column, count = length(values),
                  min = if (length(values)) min(values) else NA_real_,
                  max = if (length(values)) max(values) else NA_real_)
  }))
  list(counts = counts, ranges = ranges)
}

# Clip parallel lines to the top-coded polygons; holes and multipart geometry remain intact.
map_hatch_lines <- function(polygons, bounds, spacing) {
  if (!nrow(polygons)) return(sf::st_sfc(crs = sf::st_crs(polygons)))
  intercepts <- seq(bounds["ymin"] - bounds["xmax"], bounds["ymax"] - bounds["xmin"], by = spacing)
  lines <- lapply(intercepts, function(b) sf::st_linestring(rbind(
    c(bounds["xmin"], bounds["xmin"] + b), c(bounds["xmax"], bounds["xmax"] + b))))
  clipped <- sf::st_intersection(sf::st_sfc(lines, crs = sf::st_crs(polygons)), sf::st_union(sf::st_geometry(polygons)))
  if (any(sf::st_geometry_type(clipped) == "GEOMETRYCOLLECTION")) {
    clipped <- sf::st_collection_extract(clipped, "LINESTRING")
  }
  clipped[sf::st_geometry_type(clipped) %in% c("LINESTRING", "MULTILINESTRING")]
}

map_color_scale <- function(values, period) {
  if (period == "baseline") {
    limits <- range(values)
    breaks <- seq(limits[1], limits[2], length.out = 5)
    if (diff(limits) == 0) {
      spread <- max(abs(limits[1]) * 0.01, 1)
      breaks <- limits[1]
      limits <- c(max(0, limits[1] - spread), limits[2] + spread)
    }
    colors <- RColorBrewer::brewer.pal(9, "YlGnBu")
    labels <- function(x) paste0("$", format(round(x), big.mark = ",", scientific = FALSE, trim = TRUE))
    title <- "Monthly median gross rent (2024 dollars)"
  } else {
    limit <- if (all(values == 0)) 1 else max(abs(values), 1e-12)
    limits <- c(-limit, limit)
    breaks <- seq(-limit, limit, length.out = 5)
    colors <- rev(RColorBrewer::brewer.pal(11, "RdBu"))
    labels <- function(x) ifelse(x == 0, "0%", sprintf("%+.3g%%", x))
    title <- "Inflation-adjusted rent change (%)"
  }
  ggplot2::scale_fill_gradientn(
    colours = grDevices::colorRampPalette(colors, space = "rgb")(256), limits = limits,
    breaks = breaks, labels = labels, name = title,
    guide = ggplot2::guide_colourbar(direction = "horizontal", title.position = "bottom",
      barwidth = grid::unit(5.4, "in"), barheight = grid::unit(0.14, "in"),
      frame.colour = "#525c66", ticks.colour = "#525c66")
  )
}

map_status_legend <- function() {
  top_viewport <- grid::viewport(x = 0.34, y = 0.5, width = grid::unit(0.4, "in"),
                                 height = grid::unit(0.12, "in"), clip = "on")
  grid::grobTree(
    grid::rectGrob(gp = grid::gpar(fill = "#fff6dd", col = "#525c66"), vp = top_viewport),
    grid::segmentsGrob(x0 = seq(-0.3, 1, by = 0.18), y0 = 0,
                       x1 = seq(-0.3, 1, by = 0.18) + 0.3, y1 = 1,
                       gp = grid::gpar(col = "#525c66", lwd = 0.7), vp = top_viewport),
    grid::textGrob("Top-coded", x = 0.365, y = 0.5, just = "left", gp = grid::gpar(fontsize = 10)),
    grid::rectGrob(x = 0.5, y = 0.5, width = grid::unit(0.4, "in"), height = grid::unit(0.12, "in"),
                   gp = grid::gpar(fill = "#e6e8eb", col = "#525c66")),
    grid::textGrob("Missing / unavailable", x = 0.525, y = 0.5, just = "left", gp = grid::gpar(fontsize = 10))
  )
}

draw_paired_maps <- function(mapped, county_label, synthetic = FALSE) {
  if (!nrow(mapped) || is.na(sf::st_crs(mapped)) || !isFALSE(sf::st_is_longlat(mapped))) {
    stop("Maps require nonempty projected boundaries.")
  }
  counts <- display_summary(mapped)$counts
  font_family <- if (capabilities("aqua")) "Arial" else "sans"
  bounds <- sf::st_bbox(mapped)
  span <- max(bounds["xmax"] - bounds["xmin"], bounds["ymax"] - bounds["ymin"])
  padding <- span * 0.025
  xlim <- unname(bounds[c("xmin", "xmax")] + c(-padding, padding))
  ylim <- unname(bounds[c("ymin", "ymax")] + c(-padding, padding))
  panels <- lapply(c("baseline", "change"), function(period) {
    value_column <- if (period == "baseline") "baseline_rent" else "rent_change_pct"
    status <- mapped[[paste0(period, "_status")]]
    eligible <- mapped[status == "value", ]
    top <- mapped[status == "top_coded", ]
    status_line <- sprintf("%s colored  ·  %s top-coded  ·  %s unavailable",
                           format(counts[[period]], big.mark = ",", trim = TRUE)[1],
                           format(counts[[period]], big.mark = ",", trim = TRUE)[2],
                           format(counts[[period]], big.mark = ",", trim = TRUE)[3])
    p <- ggplot2::ggplot() +
      ggplot2::geom_sf(data = mapped, fill = "#e6e8eb", colour = "#525c66", linewidth = 0.25 / 2.845) +
      ggplot2::labs(title = if (period == "baseline") "2012–2016 baseline" else "2012–2016 → 2020–2024 change",
                    subtitle = status_line) +
      ggplot2::theme_void(base_family = font_family, base_size = 10) +
      ggplot2::theme(plot.title = ggplot2::element_text(size = 13, face = "bold", margin = ggplot2::margin(b = 8)),
        plot.subtitle = ggplot2::element_text(size = 9, colour = "#4b5563", margin = ggplot2::margin(b = 8)),
        legend.position = "bottom", legend.title = ggplot2::element_text(hjust = 0.5, margin = ggplot2::margin(t = 7)),
        legend.text = ggplot2::element_text(size = 9), plot.margin = ggplot2::margin(14, 12, 8, 12))
    if (nrow(eligible)) {
      p <- p + ggplot2::geom_sf(data = eligible, ggplot2::aes(fill = .data[[value_column]]),
                                colour = "#525c66", linewidth = 0.25 / 2.845) +
        map_color_scale(eligible[[value_column]], period)
    } else {
      p <- p + ggplot2::labs(caption = "No eligible values to color") +
        ggplot2::theme(plot.caption = ggplot2::element_text(hjust = 0.5, margin = ggplot2::margin(t = 12, b = 20)))
    }
    if (nrow(top)) {
      p <- p + ggplot2::geom_sf(data = top, fill = "#fff6dd", colour = "#525c66", linewidth = 0.25 / 2.845) +
        ggplot2::geom_sf(data = map_hatch_lines(top, bounds, span / 90), colour = "#525c66", linewidth = 0.7 / 2.845)
    }
    p + ggplot2::coord_sf(crs = sf::st_crs(mapped), default_crs = sf::st_crs(mapped),
                          xlim = xlim, ylim = ylim, expand = FALSE, datum = NA)
  })
  source <- if (synthetic) "Synthetic rents and polygons for validation; not empirical ACS results." else
    "Source: U.S. Census Bureau, ACS 2012–2016 / 2020–2024; 2010 TIGER/Line tract boundaries."
  notes <- paste(source,
    "Later rent uses native tract medians on unchanged geography; elsewhere, block-group rent distributions are allocated to 2010 tracts.",
    "Top-coded: baseline period at left; either period at right (including cases also missing the other period). Other unavailable tracts remain gray.",
    "Change requires positive rents in both periods. Baseline dollars already include the pipeline’s 1.307 inflation factor; no further adjustment.",
    paste0("Confirmed water-only tracts omitted from display. Full ranges; no trimming or CV/sample filters. Projection: ",
           sf::st_crs(mapped)$input, "."), sep = "\n")
  figure <- (patchwork::wrap_plots(panels, nrow = 1) /
    patchwork::wrap_elements(full = map_status_legend())) +
    patchwork::plot_layout(heights = c(1, 0.065)) +
    patchwork::plot_annotation(
      title = paste0(if (synthetic) "SYNTHETIC CHECK — " else "", "Gross rents across ", county_label),
      subtitle = "ACS five-year estimates  |  2010 census tracts  |  Both periods in 2024 dollars", caption = notes,
      theme = ggplot2::theme(
        text = ggplot2::element_text(family = font_family), plot.background = ggplot2::element_rect(fill = "white", colour = NA),
        plot.title = ggplot2::element_text(size = 21, face = "bold", colour = "#182536", margin = ggplot2::margin(b = 12)),
        plot.subtitle = ggplot2::element_text(size = 11, colour = "#4b5563", margin = ggplot2::margin(b = 10)),
        plot.caption = ggplot2::element_text(size = 8.5, hjust = 0, colour = "#4b5563", lineheight = 1.4,
                                             margin = ggplot2::margin(t = 10)),
        plot.margin = ggplot2::margin(24, 32, 20, 32)))
  list(figure = figure, panels = panels)
}

save_paired_figure <- function(figure, output_stem, overwrite = FALSE) {
  paths <- paste0(output_stem, c(".png", ".pdf"))
  existing <- paths[file.exists(paths)]
  if (length(existing) && !isTRUE(overwrite)) {
    stop("Existing figures: ", paste(existing, collapse = ", "), ". Set overwrite_figures = TRUE to replace them.")
  }
  quartz <- isTRUE(capabilities("aqua"))
  if (!quartz && !capabilities("cairo")) stop("Quartz or Cairo graphics support is required for PNG and vector PDF export.")
  dir.create(dirname(output_stem), recursive = TRUE, showWarnings = FALSE)
  for (path in paths) {
    message(if (file.exists(path)) "Replacing " else "Saving ", path)
    if (endsWith(path, ".png")) {
      grDevices::png(path, width = 14, height = 9, units = "in", res = 220,
                     type = if (quartz) "quartz" else "cairo", bg = "white")
    } else if (quartz) {
      grDevices::quartz(type = "pdf", file = path, width = 14, height = 9, family = "sans", bg = "white")
    } else {
      grDevices::cairo_pdf(path, width = 14, height = 9, family = "sans", bg = "white")
    }
    tryCatch(print(figure), finally = grDevices::dev.off())
  }
  stopifnot(all(file.exists(paths)), all(file.info(paths)$size > 0))
  paths
}
