"""Offline synthetic checks; never read or overwrite the canonical ACS panel.

Run: python tests/test_tract_rent_maps.py --preview-dir /tmp/acs_tract_map_preview
"""

import argparse
import ast
import contextlib
import io
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
from zipfile import ZipFile

import geopandas as gpd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import nbformat
import numpy as np
import pandas as pd
from shapely.geometry import box

REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT))
import tract_rent_maps as maps


def synthetic_inputs():
    # Baseline/later status cases, including valid zeros and a genuine $3,500.
    cases = [
        (1000, 1500, "observed", "observed"),
        (2000, 1400, "observed", "observed"),
        (1500, 1500, "observed", "observed"),
        (np.nan, 2000, "top_coded", "observed"),
        (1800, np.nan, "observed", "top_coded"),
        (np.nan, 1600, "unavailable_other", "observed"),
        (1700, np.nan, "observed", "unresolved"),
        (0, 1500, "observed", "observed"),
        (1800, 0, "observed", "observed"),
        (3000, 3500, "observed", "observed"),
        (np.nan, np.nan, "unresolved", "top_coded"),
    ]
    records = []
    for number, (baseline, later, baseline_status, later_status) in enumerate(cases, 1):
        record = {
            "tr2010_id": f"06001{number:06d}", "rentE_16": baseline,
            "interp_rent": later, "interp_rentPOST": later / baseline if baseline > 0 else np.nan,
            "rent_status_16": baseline_status, "rent_status_24": later_status,
            "acs_source_24": "tract" if number % 2 else "bg_agg",
            "geo_consistent": float(number % 2),
        }
        for year, status, bound in [("16", baseline_status, 3500 * 1.307),
                                     ("24", later_status, 3500)]:
            record[f"tc_flag_rent_{year}"] = {"top_coded": 1., "observed": 0.}.get(status, np.nan)
            record[f"rent_censor_bound_{year}"] = bound if status == "top_coded" else np.nan
        records.append(record)
    records.append(dict(records[0], tr2010_id="06001000013"))  # Panel-only.
    records.append(dict(records[0], tr2010_id="06013000001"))  # Another county.
    panel = pd.DataFrame(records)[maps.PANEL_COLUMNS]
    boundaries = gpd.GeoDataFrame(
        {"tr2010_id": [f"06001{number:06d}" for number in range(1, 13)]},
        geometry=[box((i % 4) * 1000, (2 - i // 4) * 1000,
                      (i % 4 + 1) * 1000, (3 - i // 4) * 1000) for i in range(12)],
        crs="EPSG:3310",
    )
    return panel, boundaries


def joined_fixture():
    panel, boundaries = synthetic_inputs()
    maps.validate_panel(panel)
    selected = panel.loc[panel["tr2010_id"].str.startswith("06001")]
    joined, coverage = maps.join_panel_to_boundaries(boundaries, selected)
    return maps.prepare_map_measures(joined), coverage


class TractRentMapTests(unittest.TestCase):
    def tearDown(self):
        plt.close("all")

    def test_values_status_precedence_and_join_coverage(self):
        mapped, coverage = joined_fixture()
        self.assertEqual(len(mapped), 12)
        self.assertEqual(coverage["coverage"].value_counts().to_dict(),
                         {"matched": 11, "boundary_only": 1, "panel_only": 1})
        self.assertEqual(coverage.loc[coverage["coverage"].eq("panel_only"), "tr2010_id"].tolist(),
                         ["06001000013"])
        counts, ranges = maps.display_summary(mapped)
        self.assertEqual(counts["baseline"].tolist(), [8, 1, 3])
        self.assertEqual(counts["change"].tolist(), [4, 3, 5])
        self.assertEqual(mapped["baseline_status"].tolist(),
                         ["value", "value", "value", "top_coded", "value", "unavailable",
                          "value", "value", "value", "value", "unavailable", "unavailable"])
        self.assertEqual(mapped["change_status"].tolist(),
                         ["value", "value", "value", "top_coded", "top_coded", "unavailable",
                          "unavailable", "unavailable", "unavailable", "value", "top_coded", "unavailable"])
        np.testing.assert_allclose(mapped.loc[[0, 1, 2, 9], "rent_change_pct"], [50, -30, 0, 100 / 6])
        self.assertEqual(mapped.loc[0, "baseline_rent"], 1000)  # No second inflation adjustment.
        self.assertEqual(mapped.loc[9, "interp_rent"], 3500)  # No ad hoc >= 3500 censoring.
        self.assertEqual(ranges.loc["baseline_rent", "min"], 0)
        self.assertAlmostEqual(ranges.loc["rent_change_pct", "min"], -30)
        self.assertEqual(ranges.loc["rent_change_pct", "max"], 50)

    def test_bad_schema_keys_flags_and_units_fail(self):
        panel, boundaries = synthetic_inputs()
        variants = []
        variants.append(panel.drop(columns="rent_status_24"))
        variants.append(pd.concat([panel, panel.iloc[[0]]], ignore_index=True))
        numeric_ids = panel.copy()
        numeric_ids["tr2010_id"] = numeric_ids["tr2010_id"].astype(int)
        variants.append(numeric_ids)
        for column, row, value in [("tc_flag_rent_24", 0, 1), ("rentE_16", 0, np.inf),
                                   ("rent_status_24", 0, None), ("interp_rentPOST", 0, 50),
                                   ("rent_censor_bound_16", 3, 3500),
                                   ("acs_source_24", 0, "bg_agg"), ("interp_rent", 4, 3500)]:
            broken = panel.copy()
            broken.loc[row, column] = value
            variants.append(broken)
        for broken in variants:
            with self.subTest(columns=broken.columns.tolist()), self.assertRaises(ValueError):
                maps.validate_panel(broken)
        with self.assertRaises(ValueError):
            maps.join_panel_to_boundaries(pd.concat([boundaries, boundaries.iloc[[0]]]), panel)
        with self.assertRaises(ValueError):
            maps.county_scope("1")
        self.assertEqual(maps.county_scope("013"), ("Contra Costa", "contra_costa"))

    def test_boundary_download_cache_reuse_and_rejection(self):
        buffer = io.BytesIO()
        stem = "tl_2010_06001_tract10"
        with ZipFile(buffer, "w") as archive:
            for suffix in (".shp", ".shx", ".dbf", ".prj"):
                archive.writestr(stem + suffix, b"synthetic download fixture")
        payload = buffer.getvalue()
        with tempfile.TemporaryDirectory() as directory, contextlib.redirect_stdout(io.StringIO()):
            with patch.object(maps, "urlopen", return_value=io.BytesIO(payload)) as download:
                path = maps.cache_boundaries(directory, "001")
                self.assertEqual(download.call_args.args[0].full_url,
                                 f"{maps.BOUNDARY_BASE_URL}/{stem}.zip")
                self.assertEqual(path.read_bytes(), payload)
            with patch.object(maps, "urlopen", side_effect=AssertionError("Cache was downloaded twice")):
                self.assertEqual(maps.cache_boundaries(directory, "001"), path)
                with self.assertRaises(ValueError):
                    maps.validate_boundary_archive(path, "013")
            corrupt_dir = Path(directory) / "corrupt"
            with patch.object(maps, "urlopen", return_value=io.BytesIO(b"not a ZIP")):
                with self.assertRaises(Exception):
                    maps.cache_boundaries(corrupt_dir, "001")
            self.assertFalse((corrupt_dir / f"{stem}.zip").exists())

    def test_render_extents_full_scales_and_export_guard(self):
        mapped, _ = joined_fixture()
        # Include an extreme positive change to prove the color scale does not clip it.
        mapped.loc[0, "rent_change_pct"] = 12000
        fig, axes = maps.draw_paired_maps(mapped, "Test County", synthetic=True)
        self.assertEqual(axes[0].get_xlim(), axes[1].get_xlim())
        self.assertEqual(axes[0].get_ylim(), axes[1].get_ylim())
        norm = axes[1].collections[1].norm
        self.assertEqual((norm.vmin, norm.vcenter, norm.vmax), (-12000, 0, 12000))
        self.assertEqual([text.get_text() for text in fig.legends[0].get_texts()],
                         ["Top-coded", "Missing / unavailable"])
        with tempfile.TemporaryDirectory() as directory:
            stem = Path(directory) / "paired"
            outputs = maps.save_paired_figure(fig, stem)
            self.assertEqual(outputs[0].read_bytes()[:8], b"\x89PNG\r\n\x1a\n")
            self.assertEqual(outputs[1].read_bytes()[:4], b"%PDF")
            original = [path.read_bytes() for path in outputs]
            with self.assertRaises(FileExistsError):
                maps.save_paired_figure(fig, stem)
            self.assertEqual([path.read_bytes() for path in outputs], original)

    def test_missing_only_zero_only_and_one_sided_change_scales(self):
        mapped, _ = joined_fixture()
        for frame in [mapped.iloc[[11]].copy(), mapped.iloc[[0]].copy(),
                      mapped.iloc[[1]].copy(), mapped.iloc[[2]].copy()]:
            with self.subTest(rows=frame.index.tolist()):
                fig, axes = maps.draw_paired_maps(frame, "Test County", synthetic=True)
                fig.canvas.draw()
                if frame["rent_change_pct"].notna().any():
                    norm = axes[1].collections[1].norm
                    self.assertLess(norm.vmin, 0)
                    self.assertGreater(norm.vmax, 0)
                    self.assertEqual(norm.vcenter, 0)
                plt.close(fig)

    def test_every_notebook_cell_with_offline_synthetic_inputs(self):
        notebook = nbformat.read(REPO_ROOT / "05_map_tract_rents.ipynb", as_version=4)
        nbformat.validate(notebook)
        headings = [cell.source.splitlines()[0] for cell in notebook.cells if cell.cell_type == "markdown"]
        self.assertEqual([heading.split()[1] for heading in headings if heading.startswith("# ")
                          and heading[2:3].isdigit()], [f"{number}." for number in range(1, 7)])
        for cell in notebook.cells:
            if cell.cell_type == "code":
                ast.parse(cell.source, filename=f"notebook:{cell.id}")
        panel, boundaries = synthetic_inputs()
        with tempfile.TemporaryDirectory() as directory:
            temporary = Path(directory)
            panel_path = temporary / "synthetic_panel.feather"
            panel.to_feather(panel_path)
            boundary_stem = "tl_2010_06001_tract10"
            source = boundaries.to_crs("EPSG:4269").rename(columns={"tr2010_id": "GEOID10"})
            source["STATEFP10"], source["COUNTYFP10"] = "06", "001"
            source.to_file(temporary / f"{boundary_stem}.shp", engine="fiona")
            with ZipFile(temporary / f"{boundary_stem}.zip", "w") as archive:
                for path in temporary.glob(f"{boundary_stem}.*"):
                    if path.suffix != ".zip":
                        archive.write(path, arcname=path.name)
            namespace = {}
            with patch.object(maps, "urlopen", side_effect=AssertionError("Offline test attempted a download")), \
                 contextlib.redirect_stdout(io.StringIO()):
                for cell in notebook.cells:
                    if cell.cell_type != "code":
                        continue
                    exec(compile(cell.source, f"notebook:{cell.id}", "exec"), namespace)
                    if cell.id == "imports":
                        namespace["display"] = lambda *args, **kwargs: None
                        namespace["draw_paired_maps"] = lambda frame, label: maps.draw_paired_maps(
                            frame, "Test County", synthetic=True,
                        )
                    if cell.id == "configuration":
                        namespace.update(panel_path=panel_path, boundary_cache_dir=temporary,
                                         output_stem=temporary / "synthetic_notebook")
            self.assertEqual(len(namespace["mapped"]), 12)
            self.assertEqual(len(namespace["county_panel"]), 12)
            self.assertEqual(namespace["status_counts"]["change"].tolist(), [4, 3, 5])
            self.assertTrue(all(path.exists() for path in namespace["export_paths"]))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--preview-dir", type=Path)
    args = parser.parse_args()
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(TractRentMapTests))
    if not result.wasSuccessful():
        raise SystemExit(1)
    if args.preview_dir:
        mapped, _ = joined_fixture()
        fig, _ = maps.draw_paired_maps(mapped, "Test County", synthetic=True)
        paths = maps.save_paired_figure(fig, args.preview_dir / "synthetic_tract_rents", overwrite=True)
        plt.close(fig)
        print("Synthetic preview only:", ", ".join(map(str, paths)))


if __name__ == "__main__":
    main()
