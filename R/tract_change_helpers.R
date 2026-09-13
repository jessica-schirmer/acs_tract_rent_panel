# Land-only tract relationship helpers for 03_tract_change.Rmd.
# Source R/helpers.R and R/geography_qa.R first for shared reporting/key checks.

assert_tract_relationship_source <- function(relationships) {
  keys <- c("tr2020_id", "tr2010_id")
  areas <- c("arealand_2020", "arealand_2010", "arealand_part")
  required <- c(keys, areas)
  if (!is.data.frame(relationships) || anyDuplicated(names(relationships)) ||
      !all(required %in% names(relationships)) || nrow(relationships) == 0L) {
    stop("Tract relationships require a nonempty table with both IDs and three land areas")
  }
  for (key in keys) {
    ids <- relationships[[key]]
    if (!is.character(ids) || anyNA(ids) || !all(grepl("^[0-9]{11}$", ids))) {
      stop("Invalid 11-digit character GEOID: ", key)
    }
  }
  if (!all(startsWith(relationships$tr2020_id, "06"))) {
    stop("Expected California 2020 tract GEOIDs")
  }
  assert_unique_key(relationships, keys, "Source tract intersections")
  for (area in areas) {
    values <- relationships[[area]]
    if (!is.numeric(values) || anyNA(values) || any(!is.finite(values)) ||
        any(values < 0 | values >= 2^53 | values != floor(values))) {
      stop("Invalid land area (finite nonnegative exact integers required): ", area)
    }
  }
  for (vintage in c("2020", "2010")) {
    totals <- relationships |>
      dplyr::group_by(.data[[paste0("tr", vintage, "_id")]]) |>
      dplyr::summarise(n_totals = dplyr::n_distinct(.data[[paste0("arealand_", vintage)]]),
                       .groups = "drop")
    if (any(totals$n_totals != 1L)) stop("Inconsistent repeated land total: ", vintage)
  }
  if (any(relationships$arealand_part > relationships$arealand_2020 |
          relationships$arealand_part > relationships$arealand_2010)) {
    stop("Intersection land area exceeds a tract total")
  }
  invisible(relationships)
}

tract_relationship_class <- function(n_2010_partners, n_2020_partners, geo_consistent) {
  dplyr::case_when(
    n_2010_partners > 1L & n_2020_partners > 1L ~ "many_to_many",
    n_2010_partners > 1L ~ "merge",
    n_2020_partners > 1L ~ "split",
    geo_consistent == 1 ~ "consistent",
    TRUE ~ "one_to_one_changed"
  )
}

characterize_tract_relationships <- function(relationships) {
  assert_tract_relationship_source(relationships)
  relationships |>
    dplyr::mutate(dplyr::across(dplyr::starts_with("arealand_"), as.double)) |>
    dplyr::group_by(tr2020_id) |>
    dplyr::mutate(n_2010_partners = dplyr::n_distinct(tr2010_id)) |>
    dplyr::ungroup() |>
    dplyr::group_by(tr2010_id) |>
    dplyr::mutate(n_2020_partners = dplyr::n_distinct(tr2020_id)) |>
    dplyr::ungroup() |>
    dplyr::mutate(
      share_2020_land = arealand_part / dplyr::na_if(arealand_2020, 0),
      share_2010_land = arealand_part / dplyr::na_if(arealand_2010, 0),
      zero_land_area = as.double(arealand_2020 == 0 | arealand_2010 == 0),
      same_geoid = as.double(tr2020_id == tr2010_id),
      geo_consistent = as.double(
        n_2010_partners == 1L & n_2020_partners == 1L &
          arealand_2020 > 0 & arealand_2010 > 0 &
          arealand_part == arealand_2020 & arealand_part == arealand_2010
      ),
      relationship_class = tract_relationship_class(
        n_2010_partners, n_2020_partners, geo_consistent
      )
    )
}

build_tract_crosswalk <- function(relationships) {
  tract_index <- relationships |>
    dplyr::group_by(tr2020_id) |>
    dplyr::summarise(
      n_2010_partners = dplyr::first(n_2010_partners),
      max_n_2020_partners = max(n_2020_partners),
      arealand_2020 = dplyr::first(arealand_2020),
      geo_consistent = as.double(any(geo_consistent == 1)),
      zero_land_area = as.double(any(zero_land_area == 1)),
      .groups = "drop"
    )
  report_n(tract_index, "2020 tract index (one row per source 2020 tract)")
  unique_links <- relationships |>
    dplyr::filter(n_2010_partners == 1L) |>
    dplyr::select(tr2020_id, tr2010_id, same_geoid, n_2020_partners,
                  share_2020_land, share_2010_land, arealand_2010, arealand_part)
  report_n(unique_links, "Unique 2010 links retained for pair-specific output fields")
  crosswalk <- tract_index |>
    dplyr::left_join(unique_links, by = "tr2020_id", relationship = "one-to-one") |>
    dplyr::mutate(relationship_class = tract_relationship_class(
      n_2010_partners, max_n_2020_partners, geo_consistent
    )) |>
    dplyr::select(tr2020_id, tr2010_id, geo_consistent, same_geoid,
                  relationship_class, zero_land_area, n_2010_partners,
                  n_2020_partners, max_n_2020_partners, share_2020_land,
                  share_2010_land, arealand_2020, arealand_2010, arealand_part) |>
    dplyr::arrange(tr2020_id)
  report_n(crosswalk, "Unique-link join (no row multiplication)", nrow(tract_index))
  stopifnot("Unique-link join changed tract count" = nrow(crosswalk) == nrow(tract_index))
  crosswalk
}

assert_tract_crosswalk <- function(crosswalk, relationships) {
  types <- c(tr2020_id = "character", tr2010_id = "character",
             geo_consistent = "double", same_geoid = "double",
             relationship_class = "character", zero_land_area = "double",
             n_2010_partners = "integer", n_2020_partners = "integer",
             max_n_2020_partners = "integer", share_2020_land = "double",
             share_2010_land = "double", arealand_2020 = "double",
             arealand_2010 = "double", arealand_part = "double")
  stopifnot("Crosswalk columns/types differ from schema" =
              identical(vapply(crosswalk, typeof, character(1)), types))
  assert_tract_keys(crosswalk, relationships$tr2020_id, "Tract crosswalk", key = "tr2020_id")
  stopifnot("Invalid output GEOIDs" =
              all(grepl("^06[0-9]{9}$", crosswalk$tr2020_id)) &&
              all(grepl("^[0-9]{11}$", stats::na.omit(crosswalk$tr2010_id))))
  for (flag in c("geo_consistent", "same_geoid", "zero_land_area")) {
    stopifnot("Invalid 0/1 flag" = all(stats::na.omit(crosswalk[[flag]]) %in% c(0, 1)))
  }
  stopifnot("Missing required tract fields" = !anyNA(crosswalk[c(
    "geo_consistent", "zero_land_area", "relationship_class", "n_2010_partners",
    "max_n_2020_partners", "arealand_2020"
  )]))
  unique_link <- crosswalk$n_2010_partners == 1L
  pair_fields <- c("tr2010_id", "same_geoid", "n_2020_partners", "share_2020_land",
                   "share_2010_land", "arealand_2010", "arealand_part")
  stopifnot("Multiple partners must not supply pair-specific fields" =
              all(is.na(crosswalk[!unique_link, pair_fields])))
  stopifnot("A unique link requires its 2010 key and areas" =
              !anyNA(crosswalk[unique_link, c("tr2010_id", "same_geoid", "n_2020_partners",
                                            "arealand_2010", "arealand_part")]))
  source_counts <- table(relationships$tr2020_id)
  reverse_counts <- table(relationships$tr2010_id)
  stopifnot("Incorrect forward partner counts" = identical(
    crosswalk$n_2010_partners, as.integer(source_counts[crosswalk$tr2020_id])
  ))
  expected_max <- tapply(as.integer(reverse_counts[relationships$tr2010_id]),
                         relationships$tr2020_id, max)
  stopifnot("Incorrect maximum reverse partner counts" = identical(
    crosswalk$max_n_2020_partners, as.integer(expected_max[crosswalk$tr2020_id])
  ))
  expected_zero <- tapply(relationships$arealand_2020 == 0 | relationships$arealand_2010 == 0,
                          relationships$tr2020_id, any)
  stopifnot("Incorrect tract zero-land flag" = identical(
    crosswalk$zero_land_area, as.double(expected_zero[crosswalk$tr2020_id])
  ))
  source_index <- match(crosswalk$tr2020_id, relationships$tr2020_id)
  stopifnot("2020 land areas changed" = identical(
    crosswalk$arealand_2020, relationships$arealand_2020[source_index]
  ))
  for (field in pair_fields) {
    stopifnot("Unique-link fields differ from source relationship" = identical(
      crosswalk[[field]][unique_link], relationships[[field]][source_index[unique_link]]
    ))
  }
  stopifnot("Incorrect reverse partner counts" = identical(
    crosswalk$n_2020_partners[unique_link],
    as.integer(reverse_counts[crosswalk$tr2010_id[unique_link]])
  ))
  for (vintage in c("2020", "2010")) {
    share <- crosswalk[[paste0("share_", vintage, "_land")]]
    denominator <- crosswalk[[paste0("arealand_", vintage)]]
    defined <- unique_link & !is.na(denominator) & denominator > 0
    stopifnot("Incorrect share missingness" = identical(!is.na(share), defined),
              "Non-finite or out-of-range overlap shares" =
                all(is.finite(share[defined]) & share[defined] >= 0 & share[defined] <= 1),
              "Incorrect land-overlap share" =
                all(share[defined] == crosswalk$arealand_part[defined] / denominator[defined]))
  }
  consistent <- crosswalk$geo_consistent == 1
  criteria <- with(crosswalk,
    n_2010_partners == 1L & n_2020_partners == 1L &
      arealand_2020 > 0 & arealand_2010 > 0 &
      arealand_part == arealand_2020 & arealand_part == arealand_2010
  )
  stopifnot("Consistency must match all six conditions" =
              identical(consistent, dplyr::coalesce(criteria, FALSE)),
            "Zero-land or multiple-partner tract flagged consistent" =
              all(crosswalk$zero_land_area[consistent] == 0 &
                    crosswalk$n_2010_partners[consistent] == 1L &
                    crosswalk$n_2020_partners[consistent] == 1L),
            "Consistent shares must equal exactly 1" =
              all(crosswalk$share_2020_land[consistent] == 1 &
                    crosswalk$share_2010_land[consistent] == 1))
  assert_unique_key(crosswalk[consistent, ], "tr2010_id", "Consistent 2010 keys")
  stopifnot("Incorrect tract relationship classification" = identical(
    crosswalk$relationship_class,
    tract_relationship_class(crosswalk$n_2010_partners,
                              crosswalk$max_n_2020_partners, crosswalk$geo_consistent)
  ))
  invisible(crosswalk)
}

# Add notebook-only reasons for rejecting a pair that passes both partner counts.
add_tract_land_diagnostics <- function(crosswalk) {
  diagnostics <- crosswalk |>
    dplyr::mutate(
      one_to_one_candidate = n_2010_partners == 1L &
        dplyr::coalesce(n_2020_partners == 1L, FALSE),
      rejection_reason = dplyr::case_when(
        one_to_one_candidate & (arealand_2020 == 0 | arealand_2010 == 0) ~
          "zero_land_area",
        one_to_one_candidate & arealand_2020 > 0 & arealand_2010 > 0 &
          (arealand_part != arealand_2020 | arealand_part != arealand_2010) ~
          "positive_land_mismatch",
        TRUE ~ NA_character_
      )
    )
  stopifnot("One-to-one rejections must have exactly one land-based reason" = identical(
    !is.na(diagnostics$rejection_reason),
    diagnostics$one_to_one_candidate & diagnostics$geo_consistent == 0
  ))
  diagnostics
}

# Works statewide or by the supplied grouping columns; absent classes count as zero.
summarize_tract_classification <- function(diagnostics, groups = character()) {
  summary <- diagnostics |>
    dplyr::group_by(dplyr::across(dplyr::all_of(groups))) |>
    dplyr::summarise(
      n_2020_tracts = dplyr::n(),
      n_consistent = sum(relationship_class == "consistent"),
      n_one_to_one_changed = sum(relationship_class == "one_to_one_changed"),
      n_split = sum(relationship_class == "split"),
      n_merge = sum(relationship_class == "merge"),
      n_many_to_many = sum(relationship_class == "many_to_many"),
      n_one_to_one_candidates = sum(one_to_one_candidate),
      n_one_to_one_rejected = sum(one_to_one_candidate & geo_consistent == 0),
      n_positive_land_mismatch = sum(rejection_reason == "positive_land_mismatch", na.rm = TRUE),
      n_zero_land_excluded = sum(rejection_reason == "zero_land_area", na.rm = TRUE),
      .groups = "drop"
    ) |>
    dplyr::mutate(pct_consistent = 100 * n_consistent / dplyr::na_if(n_2020_tracts, 0L))
  stopifnot(
    "Classification counts must sum to total tracts" = with(summary,
      all(n_2020_tracts == n_consistent + n_one_to_one_changed + n_split + n_merge + n_many_to_many)),
    "One-to-one candidates must reconcile with consistency and exclusions" = with(summary,
      all(n_one_to_one_candidates == n_consistent + n_one_to_one_rejected &
            n_one_to_one_rejected == n_positive_land_mismatch + n_zero_land_excluded &
            n_one_to_one_rejected == n_one_to_one_changed))
  )
  summary
}

save_tract_crosswalk <- function(crosswalk, path, overwrite = FALSE) {
  if (file.exists(path)) {
    if (!isTRUE(overwrite)) stop("Refusing to overwrite existing tract crosswalk: ", path)
    message("Replacing tract crosswalk with overwrite_output = TRUE: ", path)
  } else {
    message("Writing new tract crosswalk: ", path)
  }
  arrow::write_feather(crosswalk, path)
  invisible(path)
}
