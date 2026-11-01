"""Validation and static plotting helpers for 05_map_tract_rents.ipynb."""

from pathlib import Path
import hashlib
import shutil
import tempfile
from urllib.request import Request, urlopen
from zipfile import ZipFile

import geopandas as gpd
import matplotlib.pyplot as plt
from matplotlib.cm import ScalarMappable
from matplotlib.colors import Normalize, TwoSlopeNorm
from matplotlib.patches import Patch
from matplotlib.ticker import FuncFormatter
import numpy as np
import pandas as pd


COUNTIES = {
    "001": "Alameda", "013": "Contra Costa", "037": "Los Angeles",
    "041": "Marin", "055": "Napa", "059": "Orange", "065": "Riverside",
    "071": "San Bernardino", "075": "San Francisco", "081": "San Mateo",
    "085": "Santa Clara", "095": "Solano", "097": "Sonoma", "111": "Ventura",
}
PANEL_COLUMNS = [
    "tr2010_id", "rentE_16", "interp_rent", "interp_rentPOST",
    "rent_status_16", "rent_status_24", "tc_flag_rent_16", "tc_flag_rent_24",
    "rent_censor_bound_16", "rent_censor_bound_24", "acs_source_24",
    "geo_consistent",
]
DISPLAY_STATUSES = ["value", "top_coded", "unavailable"]
BOUNDARY_BASE_URL = "https://www2.census.gov/geo/tiger/TIGER2010/TRACT/2010"


def county_scope(county_fips):
    """Use the panel's documented California county universe."""
    if county_fips not in COUNTIES:
        raise ValueError(f"Select a three-character county FIPS from {COUNTIES}")
    name = COUNTIES[county_fips]
    return name, name.lower().replace(" ", "_")


def validate_tract_ids(ids, context):
    """Reject damaged keys instead of guessing lost zeros or removing duplicates."""
    valid = ids.map(lambda value: isinstance(value, str)).all()
    if not valid or ids.isna().any() or not ids.str.fullmatch(r"06[0-9]{9}").all():
        raise ValueError(f"{context}: expected nonmissing 11-character California GEOIDs")
    if ids.duplicated().any():
        raise ValueError(f"{context}: duplicate tract IDs: {ids[ids.duplicated()].tolist()}")


def validate_panel(panel):
    """Enforce the current wide-panel rent contract without adding sample filters."""
    missing = sorted(set(PANEL_COLUMNS) - set(panel.columns))
    if missing:
        raise ValueError(f"Panel lacks current canonical fields: {missing}. See schemas/acs_full.md.")
    if panel.columns.duplicated().any() or panel.empty:
        raise ValueError("Panel must be nonempty with distinct column names")
    validate_tract_ids(panel["tr2010_id"], "ACS panel (one row per tract, both periods wide)")
    numeric = [name for name in PANEL_COLUMNS if name not in {
        "tr2010_id", "rent_status_16", "rent_status_24", "acs_source_24",
    }]
    if not all(pd.api.types.is_numeric_dtype(panel[name]) for name in numeric):
        raise ValueError("Canonical rent, flag, bound, ratio, and geographic flag fields must be numeric")

    for year, rent_column, bound in [("16", "rentE_16", 3500 * 1.307),
                                     ("24", "interp_rent", 3500)]:
        status = panel[f"rent_status_{year}"]
        flag = panel[f"tc_flag_rent_{year}"]
        censor = panel[f"rent_censor_bound_{year}"]
        rent = panel[rent_column]
        if not status.isin(["observed", "top_coded", "unavailable_other", "unresolved"]).all():
            raise ValueError(f"Invalid or missing rent_status_{year}")
        observed, top = status.eq("observed"), status.eq("top_coded")
        valid = (
            np.isfinite(rent[observed]).all()
            and rent[observed].between(0, bound).all()
            and rent[~observed].isna().all()
            and flag[observed].notna().all() and flag[observed].eq(0).all()
            and flag[top].notna().all() and flag[top].eq(1).all()
            and flag[~observed & ~top].isna().all()
            and censor[top].notna().all()
            and np.isclose(censor[top], bound, rtol=0, atol=1e-8).all()
            and censor[~top].isna().all()
        )
        if not valid:
            raise ValueError(f"Invalid {year} rent/status/flag/bound combination; check the canonical producer")

    expected_source = np.where(panel["geo_consistent"].eq(1).fillna(False), "tract", "bg_agg")
    if panel["acs_source_24"].isna().any() or not panel["acs_source_24"].eq(expected_source).all():
        raise ValueError("acs_source_24 disagrees with canonical geographic source selection")
    positive_baseline = panel["rentE_16"].gt(0)
    expected_ratio = panel["interp_rent"].div(panel["rentE_16"].where(positive_baseline))
    if not np.allclose(panel["interp_rentPOST"], expected_ratio, rtol=1e-10, atol=1e-12, equal_nan=True):
        raise ValueError("interp_rentPOST does not equal interp_rent / positive rentE_16")


def validate_boundary_archive(path, county_fips):
    stem = f"tl_2010_06{county_fips}_tract10"
    with ZipFile(path) as archive:
        expected = {f"{stem}{suffix}" for suffix in (".shp", ".shx", ".dbf", ".prj")}
        if not expected.issubset(archive.namelist()) or archive.testzip() is not None:
            raise ValueError(f"Invalid 2010 tract archive: {path}")


def cache_boundaries(cache_dir, county_fips):
    """Reuse a validated original Census ZIP, or download it without extracting."""
    county_scope(county_fips)
    cache_dir = Path(cache_dir)
    path = cache_dir / f"tl_2010_06{county_fips}_tract10.zip"
    url = f"{BOUNDARY_BASE_URL}/{path.name}"
    if not path.exists():
        cache_dir.mkdir(parents=True, exist_ok=True)
        print(f"Downloading Census 2010 tract boundaries: {url}")
        request = Request(url, headers={"User-Agent": "ACS-tract-rent-maps/1.0"})
        with tempfile.TemporaryDirectory(dir=cache_dir) as temporary:
            download = Path(temporary) / path.name
            with urlopen(request, timeout=45) as response, download.open("wb") as target:
                shutil.copyfileobj(response, target)
            validate_boundary_archive(download, county_fips)
            with path.open("xb") as target, download.open("rb") as source:
                shutil.copyfileobj(source, target)
    validate_boundary_archive(path, county_fips)
    print(f"Boundary source: {url}\nCache: {path}\nSHA-256: {hashlib.sha256(path.read_bytes()).hexdigest()}")
    return path


def load_boundaries(path, county_fips, map_crs="EPSG:3310"):
    """Retain every tract and its source areas; absent area fields stay unknown."""
    county_scope(county_fips)
    validate_boundary_archive(path, county_fips)
    tracts = gpd.read_file(f"zip://{Path(path).resolve()}", engine="fiona")
    required = {"GEOID10", "STATEFP10", "COUNTYFP10", "geometry"}
    if not required.issubset(tracts.columns) or tracts.empty or tracts.crs is None:
        raise ValueError("Boundary file lacks the documented 2010 fields, polygons, or CRS")
    validate_tract_ids(tracts["GEOID10"], "Census 2010 boundaries")
    if not (tracts["STATEFP10"].eq("06").all()
            and tracts["COUNTYFP10"].eq(county_fips).all()
            and tracts["GEOID10"].str.startswith(f"06{county_fips}").all()):
        raise ValueError("Boundary file does not match the configured county")
    if (tracts.geometry.isna().any() or tracts.geometry.is_empty.any()
            or not tracts.geometry.is_valid.all()
            or not tracts.geom_type.isin(["Polygon", "MultiPolygon"]).all()):
        raise ValueError("Boundary geometry needs analyst review; no polygons were dropped or repaired")
    tracts = tracts.reindex(columns=["GEOID10", "ALAND10", "AWATER10", "geometry"]).rename(
        columns={"GEOID10": "tr2010_id"},
    )
    tracts["tr2010_id"] = tracts["tr2010_id"].astype("string")
    tracts = tracts.to_crs(map_crs)
    if not tracts.crs.is_projected:
        raise ValueError("Use a projected CRS for both maps")
    return tracts


def join_panel_to_boundaries(boundaries, panel):
    """Keep every boundary, with separate audit records for both unmatched sets."""
    validate_tract_ids(boundaries["tr2010_id"], "Selected boundaries")
    validate_tract_ids(panel["tr2010_id"], "Selected ACS panel")
    coverage = boundaries[["tr2010_id"]].merge(
        panel[["tr2010_id"]], on="tr2010_id", how="outer", validate="one_to_one",
        indicator="coverage", sort=True,
    )
    coverage["coverage"] = coverage["coverage"].cat.rename_categories({
        "left_only": "boundary_only", "right_only": "panel_only", "both": "matched",
    })
    mapped = boundaries.merge(
        panel, on="tr2010_id", how="left", validate="one_to_one", indicator="panel_join", sort=False,
    )
    assert len(mapped) == len(boundaries) and mapped["tr2010_id"].is_unique
    assert mapped["tr2010_id"].tolist() == boundaries["tr2010_id"].tolist()
    return mapped, coverage


def prepare_map_measures(mapped):
    """Only derive display fields; retain every polygon and original rent field."""
    result = mapped.copy()
    baseline, later = result["rentE_16"], result["interp_rent"]
    baseline_top = result["tc_flag_rent_16"].eq(1).fillna(False)
    later_top = result["tc_flag_rent_24"].eq(1).fillna(False)
    baseline_valid = (result["rent_status_16"].eq("observed").fillna(False)
                      & np.isfinite(baseline) & baseline.ge(0) & ~baseline_top)
    change_valid = (baseline_valid & baseline.gt(0) & np.isfinite(later) & later.gt(0)
                    & result["rent_status_24"].eq("observed").fillna(False) & ~later_top)
    result["baseline_status"] = np.select(
        [baseline_top, baseline_valid], ["top_coded", "value"], default="unavailable",
    )
    result["change_status"] = np.select(
        [baseline_top | later_top, change_valid], ["top_coded", "value"], default="unavailable",
    )
    result["baseline_rent"] = baseline.where(baseline_valid)
    result["rent_change_pct"] = 100 * (later.where(change_valid) / baseline.where(change_valid) - 1)
    if not np.isfinite(result.loc[change_valid, "rent_change_pct"]).all():
        raise ValueError("Percentage change overflowed; inspect the positive rent values")
    for status_column, value_column in [("baseline_status", "baseline_rent"),
                                        ("change_status", "rent_change_pct")]:
        assert result[status_column].isin(DISPLAY_STATUSES).all()
        assert result[status_column].eq("value").equals(result[value_column].notna())
    return result


def display_summary(mapped):
    counts = pd.DataFrame({
        "baseline": mapped["baseline_status"].value_counts().reindex(DISPLAY_STATUSES, fill_value=0),
        "change": mapped["change_status"].value_counts().reindex(DISPLAY_STATUSES, fill_value=0),
    }).rename_axis("display_status")
    ranges = mapped[["baseline_rent", "rent_change_pct"]].agg(["count", "min", "max"]).T
    return counts, ranges


def draw_paired_maps(mapped, county_label, *, synthetic=False):
    """Use the supplied plotting frame for every layer, count, range, and extent."""
    if mapped.empty or mapped.crs is None or not mapped.crs.is_projected:
        raise ValueError("Maps require nonempty projected boundaries")
    counts, _ = display_summary(mapped)
    with plt.rc_context({"font.family": "DejaVu Sans", "font.size": 10,
                         "hatch.linewidth": 0.7, "pdf.fonttype": 42}):
        fig = plt.figure(figsize=(14, 9), facecolor="white")
        grid = fig.add_gridspec(2, 2, height_ratios=[1, 0.035], left=0.055, right=0.945,
                               bottom=0.27, top=0.82, hspace=0.13, wspace=0.12)
        axes = [fig.add_subplot(grid[0, index]) for index in range(2)]
        color_axes = [fig.add_subplot(grid[1, index]) for index in range(2)]
        bounds = mapped.total_bounds
        padding = max(bounds[2] - bounds[0], bounds[3] - bounds[1]) * 0.025
        outline = {"edgecolor": "#525c66", "linewidth": 0.25}
        specs = [
            ("baseline_rent", "baseline_status", "baseline", "2012–2016 baseline", "YlGnBu"),
            ("rent_change_pct", "change_status", "change", "2012–2016 → 2020–2024 change", "RdBu_r"),
        ]
        for ax, color_ax, (value_column, status_column, period, title, cmap) in zip(axes, color_axes, specs):
            mapped.plot(ax=ax, color="#e6e8eb", **outline)
            eligible = mapped[status_column].eq("value")
            top = mapped[status_column].eq("top_coded")
            values = mapped.loc[eligible, value_column]
            if not values.empty:
                if period == "change":
                    limit = max(float(values.abs().max()), 1e-12)
                    if values.eq(0).all():
                        limit = 1.0
                    norm = TwoSlopeNorm(vmin=-limit, vcenter=0, vmax=limit)
                    ticks = np.linspace(-limit, limit, 5)
                    formatter = FuncFormatter(lambda value, _: f"{value:+.3g}%" if value else "0%")
                    label = "Inflation-adjusted rent change (%)"
                else:
                    minimum, maximum = float(values.min()), float(values.max())
                    if minimum == maximum:
                        spread = max(abs(minimum) * 0.01, 1)
                        norm = Normalize(vmin=max(0, minimum - spread), vmax=maximum + spread)
                        ticks = [minimum]
                    else:
                        norm = Normalize(vmin=minimum, vmax=maximum)
                        ticks = np.linspace(minimum, maximum, 5)
                    formatter = FuncFormatter(lambda value, _: f"${value:,.0f}")
                    label = "Monthly median gross rent (2024 dollars)"
                mapped.loc[eligible].plot(ax=ax, column=value_column, cmap=cmap, norm=norm, **outline)
                colorbar = fig.colorbar(ScalarMappable(norm=norm, cmap=cmap), cax=color_ax,
                                       orientation="horizontal", ticks=ticks, format=formatter)
                colorbar.set_label(label, labelpad=8)
                colorbar.outline.set_linewidth(0.4)
            else:
                color_ax.set_axis_off()
                color_ax.text(0.5, 0.5, "No eligible values to color", ha="center", va="center")
            if top.any():
                mapped.loc[top].plot(ax=ax, color="#fff6dd", hatch="////", **outline)
            ax.set_xlim(bounds[0] - padding, bounds[2] + padding)
            ax.set_ylim(bounds[1] - padding, bounds[3] + padding)
            ax.set_aspect("equal")
            ax.set_axis_off()
            ax.set_title(title, loc="left", fontsize=13, fontweight="bold", pad=28)
            status_line = (f"{counts.loc['value', period]:,} colored  ·  "
                           f"{counts.loc['top_coded', period]:,} top-coded  ·  "
                           f"{counts.loc['unavailable', period]:,} unavailable")
            ax.text(0, 1.025, status_line, transform=ax.transAxes, fontsize=9, color="#4b5563")
        heading = "SYNTHETIC CHECK — " if synthetic else ""
        fig.text(0.055, 0.945, f"{heading}Gross rents across {county_label}",
                 fontsize=21, fontweight="bold", color="#182536")
        fig.text(0.055, 0.905, "ACS five-year estimates  |  2010 census tracts  |  Both periods in 2024 dollars",
                 fontsize=11, color="#4b5563")
        fig.legend(handles=[
            Patch(facecolor="#fff6dd", edgecolor="#525c66", hatch="////", label="Top-coded"),
            Patch(facecolor="#e6e8eb", edgecolor="#525c66", label="Missing / unavailable"),
        ], loc="center", bbox_to_anchor=(0.5, 0.16), ncol=2, frameon=False, handlelength=3)
        source = ("Synthetic rents and polygons for validation; not empirical ACS results." if synthetic else
                  "Source: U.S. Census Bureau, ACS 2012–2016 / 2020–2024; 2010 TIGER/Line tract boundaries.")
        notes = (
            f"{source}\n"
            "Later rent uses native tract medians on unchanged geography; elsewhere, block-group rent distributions are allocated to 2010 tracts.\n"
            "Top-coded: baseline period at left; either period at right (including cases also missing the other period). Other unavailable tracts remain gray.\n"
            "Change requires positive rents in both periods. Baseline dollars already include the pipeline’s 1.307 inflation factor; no further adjustment.\n"
            "Confirmed water-only tracts omitted from display. Full ranges; no trimming or CV/sample filters. "
            f"Projection: {mapped.crs.to_string()}."
        )
        fig.text(0.055, 0.115, notes, va="top", fontsize=8.5, color="#4b5563", linespacing=1.5)
    return fig, axes


def save_paired_figure(fig, output_stem, *, overwrite=False):
    """Preflight both outputs before writing; refuse silent replacement."""
    paths = [Path(output_stem).with_suffix(extension) for extension in (".png", ".pdf")]
    existing = [str(path) for path in paths if path.exists()]
    if existing and not overwrite:
        raise FileExistsError(f"Existing figures: {existing}. Set overwrite_figures = True to replace them.")
    paths[0].parent.mkdir(parents=True, exist_ok=True)
    for path in paths:
        print(f"{'Replacing' if path.exists() else 'Saving'} {path}")
        fig.savefig(path, dpi=220, facecolor="white", metadata={"Title": "ACS tract gross rent: baseline and real change"})
        assert path.is_file() and path.stat().st_size > 0
    return paths
