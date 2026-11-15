# Phase 3 — Process: Cleaning Changelog

**Goal:** turn the raw CQI table into an analysis-ready dataset, documenting every change so the result can be reproduced and audited.

## Pipeline

```
arabica_raw  ──[SQL: 02_cleaning.sql]──►  arabica_stage  ──[Python notebook]──►  arabica_clean
1,312 rows × 53 STRING cols               1,311 rows × 36 typed cols              + altitude_m, harvest_year
```

| Stage | Tool | Script |
|---|---|---|
| Structural cleaning (types, categories, missing values, filters) | BigQuery SQL | [`sql/02_cleaning.sql`](../sql/02_cleaning.sql) |
| Free-text parsing (altitude, harvest year) | Python (pandas, regex) | [`notebooks/coffee_quality_analysis.ipynb`](../notebooks/coffee_quality_analysis.ipynb), section 2 |

Finding references (F#) point to [`02_prepare_data_sources.md`](02_prepare_data_sources.md#6-initial-exploration-findings).

## Changelog — Stage 1: SQL (`arabica_raw` → `arabica_stage`)

| # | Step | Column(s) | Before | After | Rows affected | Reason |
|---|---|---|---|---|---|---|
| 1 | Drop columns | 11 scraper artifacts; `owner_1`, `lot_number`, `ico_number`, `expiration`, `status`, `species`, `number_of_bags`, `bag_weight`, `quality_score`, `certification_*` | 53 columns | 36 columns (incl. 4 derived) | all | Empty or constant columns (F4, F5); redundant or out-of-scope fields; personal contact data (privacy) |
| 2 | Parse total score | `total_cup_points` | `"Sample  83.58"` (STRING) | `83.58` (FLOAT64) | 1,312 | Text prefix (F15); validated against `quality_score`: 0 mismatches |
| 3 | Cast sensory scores | 10 attributes | STRING | FLOAT64 | 1,312 | 0 failed casts (F17) |
| 4 | Parse defects | `cat1_defects`, `cat2_defects`, `quakers` | `"2 full defects"` | `2` (INT64) | 1,312 | Text suffix (F22). `quakers` keeps 1 original missing value |
| 5 | Parse grading date | `grading_date` | `"April 4th, 2015"` | `2015-04-04` (DATE) | 1,312 | Ordinal suffix and 2 embedded line breaks removed (F26); 0 failures. Range 2010-04-09 → 2018-01-19 |
| 6 | **Remove empty record** | all | Honduras, `row_index` 1310, every score = 0 | removed | **1** (1,312 → 1,311) | Not a real grading (F19); would lower Honduras' mean by ~1.5 points |
| 7 | New unique key | `sample_id` | `row_index` with 2 repeated values | `sample_id` 1–1,311 | all | Scraper index not unique, rows are not duplicates (F1, F2). Original kept as `source_row_index` for traceability |
| 8 | Recover missing country | `country` | NULL (owner Racafe, partner Almacafé) | `Colombia` | 1 | Two independent pieces of evidence (F8, F10) |
| 9 | Recover mislabeled country | `country` | `United States` (partner Almacafé, region Antioquia) | `Colombia` | 6 | Region is a Colombian department (F28) |
| 10 | Recover mislabeled country | `country` | `United States` (region Berastagi) | `Indonesia` | 1 | Berastagi is in North Sumatra, Indonesia (F28) |
| 11 | Unidentifiable country | `country` | `United States` (region "Central America") | `Unknown` | 1 | Not US coffee, origin cannot be determined (F28) |
| 12 | Flag recovered rows | `country_recovered` | — | `TRUE` | 9 | Transparency: country inferred, not reported |
| 13 | Standardize country names | `country` | `Tanzania, United Republic Of`; `Cote d?Ivoire` | `Tanzania`; `Côte d'Ivoire` | 40; 1 | Naming variant and encoding error (F11) |
| 14 | Shorten processing labels | `processing_method` | `Washed / Wet`, `Natural / Dry`, `Semi-washed / Semi-pulped`, `Pulped natural / honey` | `Washed`, `Natural`, `Semi-washed`, `Honey` | 1,133 | Readability in charts (F12) |
| 15 | Missing processing | `processing_method` | NULL | `Unknown` | 152 | Option C: keep rows, exclude only from Q3 (F7, F12) |
| 16 | Missing variety | `variety` | NULL | `Unknown` | 202 | Variety out of scope, no further cleaning (F13) |
| 17 | Hidden missing color | `color` | NULL, `None` | `Unknown` | 268 | `None` is a missing value written as text (F14) |
| 18 | Merge color labels | `color` | `Blue-Green` | `Bluish-Green` | 82 | Same color written two ways (F14) |
| 19 | Hidden missing moisture | `moisture_pct` | `0 %` | NULL | 253 | 0% is physically impossible = not measured (F21) |
| 20 | Flag implausible moisture | `moisture_flag` | — | `ok` / `missing` / `implausible` | 61 implausible (< 8% or > 16%) | Option A: keep values, flag instead of delete (F21) |
| 21 | Derived columns | `grading_year`, `is_specialty`, `total_defects` | — | year; `total ≥ 80`; Cat.1 + Cat.2 | all | Simplify analysis and Tableau filters |

### Kept on purpose (reviewed, not errors)

| Record(s) | Why it looks odd | Decision |
|---|---|---|
| Ethiopia, total = 43.13 (new minimum) | Very low score | **Kept.** Aroma 6, flavor 6 but uniformity, clean cup and sweetness = 0: every cup was defective. A real (bad) grading, not a data error |
| Mexico #1229 (−0.5), Brazil #961 (+0.1) | Total ≠ sum of attributes | **Kept.** Small differences; `total_cup_points` is the official score (F18, F20) |
| 4 Taiwan samples, `cupper_points = 10` | Inconsistent with other attributes (~7) | **Kept and noted** as possible grader inconsistency; Taiwan is outside the benchmark (F20) |

## Changelog — Stage 2: Python (`arabica_stage` → `arabica_clean`)

Notebook: [`notebooks/coffee_quality_analysis.ipynb`](../notebooks/coffee_quality_analysis.ipynb), section 2. Each parser is covered by unit tests built from the real formats found in exploration (14 harvest-year cases, 21 altitude cases).

| # | Step | Column(s) | Before | After | Rows affected | Reason |
|---|---|---|---|---|---|---|
| 22 | Explicit missing values on load | all text columns | pandas default turns `"n/a"`, `"None"` into NaN | only empty cells are missing | 10 values kept as text | Every conversion to missing must be a documented decision |
| 23 | Parse harvest year | `harvest_year` (new) | 25 formats: `2015/2016`, `4T/10`, `March 2010`, `08/09 crop` | INT (first year mentioned; 2-digit → 20xx) | 1,264 parsed | F23 |
| 24 | Unparseable harvest year | `harvest_year` | `Mayo a Julio`, `TEST`, `mmm`, … | missing | 11 (+47 originally missing) | No year in the text |
| 25 | Impossible harvest year | `harvest_year` | Harvest year > grading year (Brazil, 2016 vs. 2015-12-28) | missing | 2 | Coffee cannot be graded before it is harvested; rows kept |
| 26 | Parse altitude | `altitude_m` (new), `altitude_flag` (new) | 123 free-text formats | meters (INT); range → midpoint | 1,066 valid | F24; 8 documented rules |
| 27 | Convert feet | `altitude_m` | `4000 PSNM`, `5,000 F`, `3,500 - 5,200 feet` | × 0.3048 | 47 (`feet`) | Explicit feet keyword |
| 28 | Assume feet | `altitude_m` | Unitless or "metros" value > 3,000 (`5000`, `5500 METROS`) | × 0.3048 | 71 (`assumed_feet`) | Impossible in meters; `3280` = 1,000 m exactly (F25). Flagged for robustness checks |
| 29 | Invalid altitude | `altitude_m` | `1`, `0`, `50`, `190164`, `11000 metros`, `100/2000`, `TEST`, `Huanuco`… | missing | 28 (`invalid`) | Outside 100–3,000 m or no number |
| 30 | Recover invalid altitudes | `altitude_m`, `altitude_flag` | `190164` · `16.8` · `11000 metros` | 1,902 · 1,680 · 1,100 m (`recovered`) | 3 (25 remain `invalid`) | Only with evidence: (a) same owner/farm reports `1901.64` in other samples; (b) a single-typo fix consistent with the region's known altitude (Moshi, Cerrado) |
| 31 | Export | all | 41 columns in stage | 37 columns; raw text fields (`altitude_raw`, `harvest_year_raw`) dropped | 1,311 | Analysis-ready file `data/clean/coffee_arabica_clean.csv` |

**Result:** altitude available for 1,069 of 1,311 samples (81.5%); median 1,311 m, range 100–2,560 m. Honduras: 50 of 52 samples, all in a narrow band (1,200–1,650 m, median 1,400 m).

## Validation summary

| Check | Expected | Result |
|---|---|---|
| Rows / distinct `sample_id` | 1,311 / 1,311 | ✅ 1,311 / 1,311 |
| Honduras samples | 52 | ✅ 52 |
| Failed conversions (date, total, scores, defects) | 0 | ✅ 0 |
| Missing `quakers` / `moisture_pct` | 1 / 253 | ✅ 1 / 253 |
| Recovered countries | 9 | ✅ 9 |
| **Final table `arabica_clean` (V5)** | 1,311 rows · 52 Honduras · 1,069 altitudes · 0 out of range · 1,251 harvest years · mean 82.15 · specialty 86.2% | ✅ all match |

## Output

| Artifact | Location |
|---|---|
| Clean CSV | `data/clean/coffee_arabica_clean.csv` (1,311 × 37) |
| Clean table | BigQuery `coffee-quality-case-study.coffee_quality.arabica_clean` |
