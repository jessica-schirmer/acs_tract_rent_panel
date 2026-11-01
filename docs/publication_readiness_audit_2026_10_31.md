# Publication-readiness audit — 2026-10-31

The intended public workflow is Steps 1–4 followed by the baseline-rent and
rent-change maps in Step 5; the ADU-supply map is postponed.

Preserving meaningful Git history looks reasonably straightforward after
targeted credential cleanup and owner review of downstream diagnostic data.
A new repository containing selected current files would avoid the historical
credential, but would still need the reproducibility fixes below. The analyst's
preference is to preserve meaningful history if safe and reasonably straightforward.

The audit was read-only. This report was saved afterward at the analyst's
request; no remediation, history changes, dependency installation, credential
rotation, pipeline execution, or output regeneration was performed. Findings
and line references describe the audited snapshot, not a subsequent re-audit.

**Subsequent local history cleanup:** The identified credential was redacted
from retained history, and internal task specs, prompts, the rent-missingness
session log, and the QA-hardening plan were removed. The latter two removals
were explicitly selected by the owner. Commit identifiers below describe the
pre-cleanup history retained in the private backup. Credential revocation and
downstream diagnostic sharing remain separate owner decisions.

The confirmed findings are:

| Priority | Exact location | Evidence and practical consequence | Smallest recommended fix |
|---|---|---|---|
| **Publication blocker** | Commit `25da173a52a0`, `01_acs.Rmd:50` | A literal Census API key appears once in the initial commit. It was removed in `0a9ed5e`, but remains recoverable from history. Its current validity was not tested. No secret value is reproduced here. | Owner confirms revocation or replaces an active key. For preserved history, redact that historical occurrence in a separate publication copy and rescan all exported refs. |
| **Reproducibility gap** | Path configuration in [01_import_acs.Rmd](../01_import_acs.Rmd):167, [02a_build_measures_from_block_groups.Rmd](../02a_build_measures_from_block_groups.Rmd):80, [02b_build_measures_from_tracts.Rmd](../02b_build_measures_from_tracts.Rmd):85, [03_identify_tract_boundary_changes.Rmd](../03_identify_tract_boundary_changes.Rmd):78, [04_assemble_tract_panel.Rmd](../04_assemble_tract_panel.Rmd):91, and [05_map_tract_rents.Rmd](../05_map_tract_rents.Rmd):89 | Steps 1–5 depend on `../../../data/` and `../../../data-raw-temp/`. Steps 1–2 also use working-directory-relative strings. Writers assume the shared data directory already exists. An arbitrary standalone clone lacks this layout. | Provide explicit configurable data paths and document/create the required output directory. |
| **Reproducibility gap** | [README.md](../README.md), Steps 1 and 3; [01_import_acs.Rmd](../01_import_acs.Rmd):514 and :590; [03_identify_tract_boundary_changes.Rmd](../03_identify_tract_boundary_changes.Rmd):78 | `nhgis_bg2020_tr2010_06.csv`, `nhgis_tr2000_tr2010_06.csv`, and `tab20_tract20_tract10_st06.txt` are required, but reproducible acquisition/extraction instructions are missing. Step 1 requires the 2000–2010 crosswalk even though later active stages do not consume it. | Document exact download selections, preparation, and destination paths for all three inputs. |
| **Reproducibility gap** | [renv.lock](../renv.lock):79, `Hmisc` entry | `Hmisc` declares `viridis` as an import, but `viridis` has no lockfile entry. The README acknowledges this incomplete environment. This is a lockfile-completeness finding, not an observed pipeline failure. | Resolve and pin the missing dependency, or verify and remove an unnecessary dependency declaration/load before restoring again. |
| **Reproducibility gap** | [README.md](../README.md):249; [01_import_acs.Rmd](../01_import_acs.Rmd):120 | Setup is fragmented: only notebook 5 has a render command; API-key setup is confined to code comments. There is no complete guide covering R 4.5.1, initial `renv` setup, platform requirements for spatial/graphics packages, and running Steps 1–4. | Add one short fresh-checkout quickstart covering those requirements and the full execution order. |
| **Optional polish** | [.gitignore](../.gitignore); `.claude/settings.local.json`; `.Rhistory`; `.DS_Store`, `docs/.DS_Store`, `docs/task_spec_archive/.DS_Store`, `outputs/.DS_Store`, and `schemas/.DS_Store` | Environment files, R workspaces/history, and rendered notebooks are not ignored. Local settings contain machine paths; `.Rhistory` is empty. These are ordinary development hygiene issues, not evidence of an additional exposed secret. | Add targeted ignore rules and omit unwanted local metadata from the public tree. Keep intended example figures trackable. |
| **Optional polish** | [README.md](../README.md):103, :289, and :316–318 | The income-note link is broken; downstream links escape the repository. The README describes the example as becoming available later, although PNG/PDF/HTML examples are already tracked. | Correct local links and distinguish included examples from datasets users must regenerate. |
| **Optional polish** | [outputs/figures/tract_rent_baseline_and_change_alameda.html](../outputs/figures/tract_rent_baseline_and_change_alameda.html) and [the PDF](../outputs/figures/tract_rent_baseline_and_change_alameda.pdf) | These tracked examples are approximately **21.6 MB** and **5.6 MB**. Historical versions add further bulk. This is a size/presentation choice, not a publication blocker. | Retain the formats useful to the portfolio; unnecessary generated versions can be excluded if desired. |

Two substantive questions remain for the owner:

- **Downstream data sharing:** [acs_rent_expected_tract_changes.csv](acs_rent_expected_tract_changes.csv)
  and [acs_rent_coverage_tract_changes.csv](acs_rent_coverage_tract_changes.csv)
  include downstream sample-membership indicators, including `in_common_input`
  and, in the expected-change report, `prior_audit_full_complete_case` and
  `prior_audit_quality_complete_case`. Their
  [documented provenance](../schemas/acs_rent_expected_tract_changes.md)
  includes combined ADU/ACS inputs and downstream audits. This does not establish
  that sharing is prohibited, but approval should be explicit. If restricted,
  exclude the affected material from both the public tree and preserved history.
  These diagnostics are not required by the active notebook sequence.
- **Ownership, licensing, and research notes:** No project code license is
  present. Census and NHGIS source credits are present, but the owner should
  confirm code ownership, redistribution terms for examples, and the desired
  license/citations. Historical `NOTES.md` at `25da173` and downstream research
  notes, including [acs_tract_bay_area_inspection.md](acs_tract_bay_area_inspection.md),
  warrant editorial review. Task specs and session records are otherwise ordinary
  development provenance; their presence alone does not justify removing
  meaningful history. No license or redistribution permission was inferred.

Other machine-specific material includes paths in
[acs_rent_metadata_input_manifest.csv](acs_rent_metadata_input_manifest.csv):2–7
and [acs_rent_expected_change_input_manifest.csv](acs_rent_expected_change_input_manifest.csv):2–16.
Historical `05_map_tract_rents.ipynb` versions at `0a38762` and `319350b` retain
executed outputs with machine paths in cells 4, 8, and 12. These are ordinary
path/output cleanup candidates unless owner review identifies additional
sensitivity. Historical notes and task specs were preserved during the audit.

Both release options remain available:

| Release option | Assessment |
|---|---|
| **Preserve meaningful history — preferred** | Locally bounded: 45 commits, one branch, no tags, no signed commits, and one occurrence of the identified credential. Redacting the initial commit would change descendant commit identifiers while preserving the substantive development sequence. Resolve any restricted diagnostic content across retained history as well. Ordinary development clutter does not require a history purge. |
| **New repository with selected current files** | Avoids the historical credential if the old Git database/history is not copied, but sacrifices development provenance. Current diagnostic-sharing, ownership, and reproducibility questions still require resolution. |

Checks that passed:

- All **126 R chunks across six notebooks**, plus **21 helper/test R files**,
  parsed successfully. These were syntax checks, not execution of the test
  scripts or notebooks. Required notebook helpers are present inside this
  repository; no parent-directory helper is required by the active sequence.
- Notebook 5 requires only the saved ACS panel and public Census boundaries.
  **The postponed ADU map and its external input are not execution dependencies.**
  Missing parity references are handled as optional.
- The README PNG exists, is tracked, and is permitted by ignore rules. Boundary
  retrieval/cache validation is implemented; the cache ZIP is ignored and was
  not found in reachable history.
- Geographic harmonization, inflation adjustment, top-coding, and missingness
  are documented in the current schemas.
- No additional credential candidates were found in the scanned current files.
  No raw proprietary dataset files were identified; the downstream
  diagnostic-sharing question remains separate.

Scope and limitations:

- Reviewed **132 tracked files and 510 unique blobs across all 45 locally
  reachable commits**, from `25da173a52a0bc746898742f0ea94c28ff11a3fa` through
  `f208c4d1fd14422ce8fee2ff4e7e4ec38331de0e` (2026-06-10 to 2026-10-31).
  The checkout was not shallow. The only available ref was `refs/heads/main`;
  no remote was configured and no remote-tracking history or tags were available.
  No missing reachable objects were reported.
- At audit time there were no visible untracked files and one ignored file:
  `outputs/cache/tiger2010/tl_2010_06001_tract10.zip`. These observations describe
  the audit snapshot, before this report was saved. A concurrent README edit
  was observed during the audit and left untouched.
- Used local static inspection, credential-pattern and exact-credential searches,
  Git object/path inventories, dependency metadata checks, syntax checks, ignore
  probes, and inspection of existing map/notebook artifacts. No repository
  content was uploaded to an external scanning service.
- Reflog-only/unreachable objects, other clones, live credential validity,
  redistribution permissions, full empirical correctness, and clean-environment
  execution were not assessed. This is a targeted audit, not comprehensive
  security clearance.

After addressing the relevant findings, the analyst-run fresh-clone checklist is:

1. Clone the proposed public version outside the existing ADU Rent directory;
   rescan its complete exported history and confirm the approved file selection.
2. Set up R 4.5.1, bootstrap `renv`, restore the corrected lockfile, and verify
   spatial/graphics requirements, Pandoc, and `unzip`.
3. Configure data directories, obtain the three documented raw inputs, and
   supply your own `CENSUS_API_KEY` through an ignored environment file.
4. From the repository root, render **01 → 02a → 02b → 03 → 04 → 05**, with
   Step 4 saving enabled and no inherited panel or boundary cache.
5. Review notebook validation results and all three map exports; confirm Git
   status contains only intended public artifacts.
