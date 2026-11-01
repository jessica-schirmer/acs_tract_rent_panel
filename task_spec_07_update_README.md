Revise `README.md` and directly affected supporting documentation to prepare this ACS cleaning repository for public release. Follow applicable repository guidance. Preserve the existing overview, figure placement, notebook sequence, and inputs/outputs/numbered-steps structure.

This is a documentation task. Inspect current notebooks, helpers, schemas, and dependency files to verify instructions; do not change processing code, paths, dependencies, or data.

**1. Add a concise “Getting started” section before the notebook details**

Consolidate setup instructions currently buried in Step 5 and cover the full pipeline:

- R/environment setup using the repository’s actual dependency-management configuration.
- Required system dependencies, distinguishing full-pipeline requirements from mapping/export requirements.
- Census API-key setup if required. Use placeholders or environment-variable instructions; never include an actual key.
- Where to obtain the two NHGIS crosswalks and the Census tract relationship file. Provide verified source links and identify the required products/geographies; distinguish manual downloads or account requirements from automated retrieval.
- Exact expected input locations, consistent with current code.
- Notebook execution order, including which stages can run independently or in either order.
- How to enable saving `acs_full.feather` in notebook 4. Explicitly explain that notebook 5 requires the saved panel and identify where to set `write_panel = TRUE`, including any overwrite behavior users need to know.

Inspect notebook 1 to establish whether the 2000-to-2010 crosswalk is mandatory for its current execution despite being unused downstream. State the actual requirement clearly; do not describe it as optional unless the code supports that.

Do not claim standalone execution or a complete restorable environment if unresolved path or dependency issues remain. State confirmed limitations briefly and report fixes requiring code changes separately.

**2. Shorten Step 5 considerably**

Retain:
- Its purpose.
- Inputs and outputs.
- Concise numbered steps aligned with notebook sections.
- The render command.
- Brief instructions for opening the HTML and using hover labels.

Remove implementation detail from the README, including:
- Clipped line geometry for hatching.
- Quartz versus Cairo rendering.
- ZIP checksum verification.
- Specific installed package versions.
- Synthetic-preview details.
- Historical Alameda acceptance counts and references to the “three western water-only pieces.”

Retain useful technical details in existing notebook prose or an appropriate mapping guide. Avoid creating duplicate documentation or a new guide unless necessary. Keep essential system requirements in “Getting started”; package versions belong in the lockfile.

**3. Move migration history out of the README**

Move the “Rent metadata migration” material into an existing suitable migration/history document, or create one focused document if none exists. Preserve relevant evidence links, dates, and historical qualifications. Add one concise README link if useful.

Address the contradictions currently listed under “Detailed documentation and known inconsistencies”:
- Interpolation with missing rent-distribution bins.
- Obsolete rent-share/flag semantics.
- Step 3 described as diagnostic-only despite its role in canonical source selection.
- Superseded downstream migration instructions.

Use current schemas and implementation to verify present behavior. Correct documentation intended as current guidance. For historical records, preserve their historical meaning but clearly mark them as superseded and link to current guidance. Do not leave conflicting instructions presented as equally current.

If authoritative documentation and code disagree on a substantive rule, report the specific discrepancy rather than choosing silently or changing the methodology.

**4. Add a short “Methods and limitations” section**

Explain, in accessible prose:
- The ACS five-year windows and that these are period estimates, not single-year observations.
- Native-tract source selection versus geographic allocation, and the limits of allocated estimates.
- Conversion to 2024 dollars, including the documented source and calculation underlying the `1.307` factor.
- Treatment of top-coded and unavailable rent estimates.
- That mapped rent changes are descriptive and do not identify a causal effect.

Trace the inflation factor to existing code/documentation and verify its attribution. If its source cannot be established, flag that gap explicitly; do not invent a citation or alter the factor.

Link to schemas for detailed construction rules rather than repeating them.

**Validation and handoff**

Check edited links, paths, commands, section references, and consistency with current code. Do not run notebooks, regenerate outputs, install packages, or repeat the publication-readiness audit.

Summarize documentation changed and any unresolved factual questions or code/environment issues that prevent fully accurate setup instructions. Do not modify repository guidance files, commit, or push.