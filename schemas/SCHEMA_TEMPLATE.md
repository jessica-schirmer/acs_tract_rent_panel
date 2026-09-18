# Schema: `<filename>`

## 1. Dataset contract

| Property | Contract |
|---|---|
| Producer | `<notebook/script>` |
| Output | `<path>` |
| Role / status | `<canonical / intermediate / diagnostic / etc.>` |
| Row grain | `<what one row represents>` |
| Primary key | `<key + uniqueness/nonmissing constraints>` |
| Geographic scope | `<scope>` |
| Temporal scope | `<vintage / period>` |

## 2. Inputs and provenance

| Input | Source grain / key | Role |
|---|---|---|
| `<input>` | `<grain/key>` | `<purpose>` |

## 3. Construction rules

Briefly document only non-obvious rules needed to interpret the output:
- aggregation / weighting
- hierarchy
- derived measures
- exclusions
- denominator rules
- alias handling

## 4. Join / allocation contract

Describe relevant joins, crosswalks, cardinality, or contributor rules.

Omit this section if genuinely not applicable.

## 5. Columns

| Column | Type | Source / construction | Description | Valid values / missingness |
|---|---|---|---|---|
| `<column>` | `<type>` | `<source or formula>` | `<meaning>` | `<constraints>` |

List every persisted column. Define repeated conventions once rather than repeating long descriptions.

## 6. Missingness and special-value rules

- distinguish `NA` from valid zero
- document propagation / imputation rules
- document zero-denominator behavior
- document censoring/top-code/sentinel handling where relevant

## 7. Validation contract

### Fail-fast invariants

| Checkpoint | Required condition |
|---|---|
| `<stage>` | `<asserted invariant>` |

### Analyst-review diagnostics

| Diagnostic | Review expectation |
|---|---|
| `<diagnostic>` | `<what to inspect>` |

## 8. Known limitations / intentional exceptions

- `<only limitations needed to safely interpret or consume the dataset>`

## 9. Validation and regeneration

- **Focused validation:** `<test/helper>`
- **Documentation/column audit:** `<if applicable>`
- **Analyst-run regeneration:** `<how/where>`