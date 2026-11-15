# Phase 2 — Prepare: Data Sources

**Project:** What Makes Great Coffee? Quality Drivers for a Honduran Coffee Cooperative
**Phase goal:** identify and document the data, assess its credibility, and explore it before any cleaning.

## 1. Data Source

| Item | Detail |
|---|---|
| **Original source** | [Coffee Quality Institute (CQI)](https://www.coffeeinstitute.org/) — public coffee review database. Each review is a sample graded by certified Q-graders using the SCA cupping protocol. |
| **Collected by** | James LeDoux, who scraped the CQI website in January 2018 |
| **Repository** | [github.com/jldbc/coffee-quality-database](https://github.com/jldbc/coffee-quality-database) |
| **File used** | `data/arabica_ratings_raw.csv` — 1,312 rows × 53 columns |
| **Files not used** | `robusta_ratings_raw.csv` (28 rows; Robusta uses a different grading scale, out of scope). `arabica_data_cleaned.csv` (the author's cleaned version) was deliberately **not** used, so that every cleaning decision is made and documented in this project — that version also keeps physically impossible altitudes (e.g., 190,164 m). |
| **Time span** | Samples graded between 2010 and 2018 (based on `grading_date`; 2018 has only 6 samples). |
| **Granularity** | One row = one graded coffee sample (lot). |

## 2. License & Privacy

- **License:** the repository is published under the **MIT License**, which allows reuse with attribution. The underlying reviews were publicly available on the CQI website.
- **Attribution:** CQI as the original source and James LeDoux as the collector are credited in this document and in the README.
- **Affiliation:** this is an independent educational project, not affiliated with or endorsed by CQI. The client (*Cooperativa Cafetalera Hondureña*) is fictional.
- **Personal data:** the dataset includes owner and producer names (public business information) and **contact names and phone numbers** of certification staff (`certification_contact`). Contact data is not needed for the analysis and is **dropped during cleaning**. Owner and producer names are kept only as context and are not highlighted in any deliverable.

## 3. Data Organization

- **Format:** a single wide CSV table. Each row is a sample; columns combine origin metadata, processing, 10 sensory scores, the total score and green-coffee grading (moisture, defects, color).
- **Storage:**

| Layer | Location | Notes |
|---|---|---|
| Raw file | `data/raw/arabica_ratings_raw.csv` | Unmodified copy of the source file |
| Raw table | BigQuery `coffee-quality-case-study.coffee_quality.arabica_raw` | All 53 columns loaded as `STRING`, never modified |
| Clean table | BigQuery `coffee_quality.arabica_clean` + `data/clean/coffee_arabica_clean.csv` | Built in Phase 3 |

- **Loading decisions** (schema: [`sql/schema/arabica_raw_schema.json`](../sql/schema/arabica_raw_schema.json)):
  - **All columns as STRING.** Many "numeric" columns contain text (`"Sample  83.58"`, `"12 %"`), so auto-detection would fail or silently convert values. Types are converted explicitly in Phase 3.
  - **Custom column names.** The CSV has two empty headers and names BigQuery rejects (`Owner.1`, names with spaces). Columns were renamed to snake_case **by position**; the original header is kept in each field's description.
  - **Quoted newlines enabled.** 5 rows contain line breaks inside quoted fields (addresses, dates); without this option the load fails with 19 broken lines.
- **Sandbox note:** BigQuery Sandbox tables expire after 60 days. The project is fully reproducible from the raw CSV, the schema file and the SQL scripts.

## 4. ROCCC Assessment

| Criterion | Rating | Evidence |
|---|---|---|
| **Reliable** | Medium–High | Scores come from certified Q-graders using a standardized protocol; the parsed total score matches the source's own numeric copy in 100% of rows (F15) and equals the sum of the 10 attributes within rounding in 1,310 of 1,312 rows (F18). Weaknesses: one empty record (F19), a few grader inconsistencies (F20) and implausible self-reported values (F21, F24). |
| **Original** | Medium | Second-party: scraped from CQI by a third party, not exported by CQI itself. Scraping artifacts are visible (empty columns, repeated index, embedded line breaks, the author's parsing notes). |
| **Comprehensive** | Medium | Rich variables for the business task (origin, altitude, processing, 10 sensory scores, defects), but 36 countries with uneven coverage (16 with fewer than 10 samples) and only 52 valid samples from Honduras. Key factors have missing values: altitude 16.5%, processing 11.7%. |
| **Current** | **Low** | Samples graded 2010–2018. Quality, varieties and processing practices may have changed since then. |
| **Cited** | Yes | CQI is the recognized authority for Q-grading; the repository is public, documented and widely used in data analysis projects. |

**Conclusion:** the data is suitable for a **descriptive and correlational** analysis of quality drivers, as long as results are presented as associations within *submitted* samples and the limitations below are stated.

## 5. Data Dictionary

Raw table: `coffee_quality.arabica_raw` (53 columns, all loaded as STRING). Column names were converted to snake_case by position; the original header is kept in each field's description in BigQuery.

**Role:** `Key` = identifier · `Analysis` = answers a guiding question · `Context` = descriptive, kept for filtering or the dashboard · `Drop` = removed in cleaning (reason given).

### Identification & metadata
| Column | Description | Raw example | Role |
|---|---|---|---|
| `row_index` | Row number assigned by the scraper | `348` | Drop — not unique (F1); replaced by `sample_id` |
| `quality_score` | Total score as shown on the CQI listing page (numeric copy of `total_cup_points`) | `83.58` | Context — used to validate the parsed `total_cup_points` |
| `species` | Coffee species | `Arabica` | Analysis filter (all rows are Arabica) |
| `status` | Status of the CQI review | `Completed` | Context |
| `grading_date` | Date the sample was graded by Q-graders | `June 6th, 2012` | Context — parse to DATE |
| `expiration` | Expiration date of the quality certificate (≈ 1 year after grading) | `June 6th, 2013` | Drop — derived from `grading_date` |

### Origin & producer
| Column | Description | Raw example | Role |
|---|---|---|---|
| `country_of_origin` | Producing country | `Honduras` | **Analysis (Q1, Q5)** — standardize names |
| `region` | Producing region within the country (free text) | `XALAPA` | Context — too inconsistent for analysis |
| `altitude` | Farm altitude as reported by the producer (free text: ranges, units, feet/meters mixed) | `1000 MSNM`, `1950-2200` | **Analysis (Q2)** — parse into `altitude_mean_m` |
| `owner` | Person or company that owns/submitted the sample | `ALFREDO BOJALIL` | Context |
| `owner_1` | Owner name repeated from a second table on the CQI page | `ALFREDO BOJALIL` | Drop — duplicate of `owner` |
| `producer` | Farmer or producing entity | `JULIAN ALBERTO URRUTIA MOYA` | Context |
| `farm_name` | Name of the farm | `OJO DE AGUA` | Context |
| `lot_number` | Producer's lot identifier | — | Drop — mostly empty, not analytical |
| `mill` | Wet/dry mill where the coffee was processed | `AGROINDUSTRIAS UNIDAS DE MEXICO` | Context |
| `ico_number` | International Coffee Organization export identifier | `3-59-1327` | Drop — identifier with no analytical use |
| `company` | Exporting or trading company | `ECOMTRADING` | Context |
| `in_country_partner` | CQI-licensed organization that coordinated the grading in the country | `AMECAFE`, `Almacafé` | Context |
| `number_of_bags` | Number of bags in the lot | `250` | Context — cast to INT64 |
| `bag_weight` | Weight per bag, with unit in text | `1 kg`, `70 kg` | Context — parse value and unit |

### Coffee & processing
| Column | Description | Raw example | Role |
|---|---|---|---|
| `harvest_year` | Harvest year or season (mixed formats) | `2012`, `2014/2015` | **Analysis (time trend)** — standardize to a single year |
| `variety` | Arabica cultivar | `Typica`, `Bourbon`, `Caturra` | Context — high missing rate (see 2.2) |
| `processing_method` | Post-harvest processing method | `Washed / Wet`, `Natural / Dry`, `Pulped natural / honey` | **Analysis (Q3)** |

### Sensory scores (SCA cupping form)
Each attribute is scored by certified Q-graders on a 0–10 scale (in practice 6–10, in 0.25 steps).

| Column | Description | Role |
|---|---|---|
| `aroma` | Fragrance (dry grounds) and aroma (brewed) | **Analysis (Q5)** |
| `flavor` | Main taste and retronasal aroma combined | **Analysis (Q5)** |
| `aftertaste` | Length and quality of the taste after swallowing | **Analysis (Q5)** |
| `acidity` | Brightness; scored on quality, not intensity | **Analysis (Q5)** |
| `body` | Mouthfeel / tactile weight of the coffee | **Analysis (Q5)** |
| `balance` | How flavor, aftertaste, acidity and body work together | **Analysis (Q5)** |
| `uniformity` | Consistency across 5 cups (2 points per uniform cup) | **Analysis (Q5)** |
| `clean_cup` | Absence of negative impressions across 5 cups (2 points per cup) | **Analysis (Q5)** |
| `sweetness` | Pleasant sweetness across 5 cups (2 points per cup) | **Analysis (Q5)** |
| `cupper_points` | Grader's holistic overall rating | **Analysis (Q5)** |
| `total_cup_points` | Final score (0–100): sum of the 10 attributes (verified in 4.3: equal within ±0.03 rounding for 1,310 of 1,312 samples). Stored with a text prefix | **Analysis (all)** — parse `"Sample  83.58"` → `83.58` |

### Green coffee grading (physical defects)
Measured on a green (unroasted) sample, typically 350 g.

| Column | Description | Raw example | Role |
|---|---|---|---|
| `moisture` | Moisture content of the green beans (SCA target ≈ 10–12%) | `12 %`, `0 %` | Analysis — parse; `0 %` likely means "not measured" |
| `category_one_defects` | Count of primary (severe) full defects: full black, full sour, fungus, foreign matter, severe insect damage | `0 full defects` | **Analysis (Q3, Q4)** — parse to INT64 |
| `category_two_defects` | Count of secondary full defects: partial black/sour, broken, immature, withered, shells, slight insect damage | `2 full defects` | **Analysis (Q3, Q4)** — parse to INT64 |
| `quakers` | Unripe beans that stay pale after roasting | `0` | Analysis (Q4) — cast to INT64 |
| `color` | Color of the green beans | `Green`, `Bluish-Green` | Context |

### Certification (contact data)
| Column | Description | Role |
|---|---|---|
| `certification_body` | Organization that issued the certificate (usually the in-country partner) | Drop — duplicate of `in_country_partner` |
| `certification_address` | Postal address of the certification body | Drop — not analytical |
| `certification_contact` | Contact person name and phone number | Drop — personal contact data, not needed (privacy) |

### Scraper artifacts (verified in query 2.1)
| Column | Non-null values | Content | Role |
|---|---|---|---|
| `view_certificate_1`, `view_certificate_2`, `cupping_protocol_and_descriptors`, `view_green_analysis_details`, `request_a_sample` | 0 | Labels of links/buttons on the CQI web page | Drop — 100% empty |
| `na_0` | 1,310 | Only the word `Sample` (section label) | Drop — no information |
| `na_1` | 1,312 | Only the word `Sample` | Drop — no information |
| `na_2`, `na_3`, `unnamed_51` | 0 | Empty | Drop — 100% empty |
| `notes` | 5 | Scraper author's notes on which web table was parsed | Drop — mention in limitations |

## 6. Initial Exploration Findings

Queries: [`sql/01_exploration.sql`](../sql/01_exploration.sql)

| # | Query | Finding | Implication for cleaning |
|---|---|---|---|
| F1 | 1.1 | 1,312 rows, but only 1,310 distinct values in the original index (`row_index`): 2 values repeat (348 and 1229). | The scraper's index is not a reliable key. |
| F2 | 1.2 | The repeated index values belong to **different samples** (different owner, country, grading date and scores), not to duplicated records. | Keep all rows; create a new unique key (`sample_id`) during cleaning. |
| F3 | 1.2 | Format issues already visible: `total_cup_points` stored as text with a prefix (`"Sample  83.00"`), `moisture` as `"12 %"` and also `"0 %"`, defects as `"2 full defects"`, altitude with units in text (`"1000 MSNM"`). | Parse to numeric types; investigate `moisture = 0 %` (probably missing, not a real 0). |
| F4 | 2.1 | 9 scraper columns are 100% empty; `na_0` and `na_1` are almost 100% filled but only contain the label `Sample`. | Drop all 11 artifact columns: a full column is not necessarily an informative one. |
| F5 | 2.1 | `notes` has 5 values: the scraper author's comments on parsing choices. | Drop the column; record as a data-provenance limitation. |
| F6 | 2.2 | Scores, sensory attributes, moisture and defect counts are **100% complete** (no missing values). | The core outcome variables are reliable for all 1,312 samples. |
| F7 | 2.2 | Missing values in key factors: `altitude` 217 (16.5%), `color` 217 (16.5%), `variety` 202 (15.4%), `processing_method` 153 (11.7%), `region` 55 (4.2%), `harvest_year` 47 (3.6%), `country_of_origin` 1 (0.1%). | Do **not** drop rows globally. Keep missing categories as `Unknown` and exclude them only from the analysis that needs that variable. Do not impute altitude. |
| F8 | 2.3 | The only sample without a country (`row_index` 1197) has owner *Racafe & Cia S.C.A* (a Colombian exporter) and in-country partner *Almacafé* (Colombia's CQI partner). | Recover `country = Colombia` from two independent pieces of evidence (pending confirmation in 2.5); flag the row as recovered. |
| F9 | 2.4 | `altitude` and `color` are both missing in 73 rows; each is missing alone in 144 rows. If missingness were independent we would expect ~36 shared rows (217² / 1,312), so there is a weak overlap pattern, but mostly they are missing in different rows. | No action: `color` is not an analysis variable. Note that missingness is not completely random. |
| F10 | 2.5 | All 59 other Racafe samples are from Colombia; 171 of 177 Almacafé samples with a country are Colombian (the other 6 are labeled `United States`). | **Confirmed:** set `country = Colombia` for `row_index` 1197 and flag it. Investigate the 6 "United States" samples graded by Almacafé. |
| F11 | 3.1 | 36 countries. Variants to standardize: `Tanzania, United Republic Of` → `Tanzania`; `Cote d?Ivoire` (encoding error) → `Côte d'Ivoire`. US appears as `United States` (8), `United States (Hawaii)` (73) and `United States (Puerto Rico)` (4). 16 countries have fewer than 10 samples. | Standardize names. Keep Hawaii and Puerto Rico as separate origins. Use a minimum sample size for country rankings. Benchmark countries all have n ≥ 45 (Honduras = 53). |
| F12 | 3.2 | Processing labels are consistent (no spelling variants). Washed 61.9%, Natural 19.1%, missing 11.7%, Semi-washed 4.3%, Other 2.0%, Honey 1.1% (n = 14). | Shorten the labels; missing → `Unknown`. Report Honey results with a small-sample warning. |
| F13 | 3.3 | 29 variety labels, with 202 missing and 108 `Other`. Some labels are not cultivars but origins or bean types (`Peaberry`, `Java`, `Sumatra`, `Hawaiian Kona`, `Ethiopian Yirgacheffe`). | Variety is out of the analysis scope: missing → `Unknown`, no further cleaning (document as a limitation). |
| F14 | 3.4 | Color has two forms of missing data: NULL (217) and the text `None` (51), for 268 missing in total. `Blue-Green` (82) and `Bluish-Green` (112) look like the same color written two ways. | Convert `None` → missing. Merge `Blue-Green` into `Bluish-Green`. |
| F15 | 4.1 | `total_cup_points` was parsed for all 1,312 rows and matches `quality_score` exactly (0 mismatches). Range 0.0–90.58; mean 82.09; 9 samples below 70; at least one sample scores 0. | Parsing rule validated. Investigate and remove the `0` score (impossible for a graded sample). |
| F16 | 4.1 | **86.1% of samples are specialty grade (≥ 80)**, far above the share of specialty coffee in the real market. | Confirms selection bias: producers submit their best lots to CQI. Compare groups *relative to each other*, not as market estimates. Consider an additional, stricter threshold (e.g., ≥ 85) to separate groups. |
| F17 | 4.2 | All 10 attributes parse correctly; each has a minimum of 0.0 (likely the single 0-score sample). The 6 quality attributes average 7.40–7.56 (aftertaste lowest). `uniformity`, `clean_cup` and `sweetness` average 9.83–9.90: almost every sample gets the maximum. | Remove the 0-score sample. For Q5, focus the sensory comparison on the 7 attributes that vary; the 3 per-cup attributes have a ceiling effect and barely differentiate samples. |
| F18 | 4.3 | `total − sum of attributes` is within ±0.03 for 1,310 samples (rounding of averaged cupper scores). Exceptions: −0.5 (1 sample) and +0.1 (1 sample). | The Phase 1 definition ("sum of 10 attributes") holds. Inspect the 2 exceptions (query 4.4). |
| F19 | 4.4 | The 0-score sample (`row_index` 1310) is **from Honduras**: every attribute is 0, so it is an empty record, not a real grading. | Remove it (Honduras: 53 → 52 samples). Keeping it would unfairly lower Honduras' average by ~1.5 points. |
| F20 | 4.4 | The 2 sum anomalies (−0.5 Mexico #1229, +0.1 Brazil #961) are small and both rows are among the 5 with embedded line breaks. 4 Taiwanese samples (same owner, *CQI Taiwan ICP*) have `cupper_points = 10` while their other attributes are ~7–7.7. | Keep all of them; `total_cup_points` is the official score. Flag the Taiwan pattern as a possible grader inconsistency (Taiwan is outside the benchmark). |
| F21 | 4.5 | Moisture: 253 samples (19.3%) report **0%**, and 50 report 1–7%, both physically implausible for green coffee. 920 samples (70%) fall in the expected 10–13% range; a few go up to 28%. | **Decision (option A):** `0` → missing; keep other implausible values but add `moisture_flag = 'implausible'` (moisture is a supporting variable). |
| F22 | 4.6 | Defects are highly skewed. Cat. 1: 84.8% of samples have zero, mean 0.43, max 31. Cat. 2: only 27.7% have zero, median 2, mean 3.59, max 55. Quakers: 92.8% zero, 1 missing. | Use medians and rank-based correlation (Spearman) in Phase 4. Consider a binary variable "has any Cat. 1 defect". |
| F23 | 4.7 | `harvest_year` has 25 formats. 84% are a single year; the rest are seasons (`2015/2016`, `2017 / 2018`, `2009-2010`), quarters (`4T/10`), month + year (`March 2010`), months without a year (`Mayo a Julio`) and junk (`TEST`, `mmm`). | Rule: take the first year mentioned (2-digit years → 20xx); month-only and junk values → missing. Parse in Python. |
| F24 | 4.8–4.9 | `altitude` has 123 formats: plain numbers (628), meters in several languages (`msnm`, `m`, `MASL`, `metros`, `公尺`), feet (`ft`, `PSNM` = *pies sobre el nivel del mar*), ranges (`1200-1400`, `De 1200 a 1400 msnm`), `1800++`, and dots/commas as thousands separators (`1.872`). 64 unitless values exceed 3,000 m (e.g., Guatemala `4300`, `5000`), which is implausible in meters and likely feet. | Parse in Python: extract numbers, detect unit, average ranges, convert feet (× 0.3048), and set values outside a plausible range to missing. Document every rule. |
| F25 | 4.9 | Unitless altitudes above 3,000: Guatemala 58 (3,280–190,164), Myanmar 5 (3,800–4,287), Indonesia 1 (3,500). `3280` ft is almost exactly 1,000 m, supporting the feet hypothesis. | Rule: unitless value > 3,000 → treat as feet and convert; if still implausible after conversion (e.g., 190,164) → missing. |
| F26 | 4.10 | `grading_date` is complete and uses one format, `Month D<suffix>, YYYY` (suffixes st/nd/rd/th). | Parse to DATE (remove the suffix). Candidate time variable for the trend analysis instead of `harvest_year`. |
| F27 | 5.1–5.2 | Honduras: 53 samples (52 after removing the 0-score record); altitude 51, processing 49 (Washed 35, Natural 14, Unknown 4), harvest year 53, real moisture 53. Graded 2013–2018, mostly in 2014 (17), 2015 (12) and 2017 (16). | Honduras benchmark and sensory profile are feasible; a Honduras-only time trend is limited to about 2014–2017. |
| F28 | Phase 3 check | The 8 samples labeled `United States` are not US coffee: 6 were graded by Almacafé with regions in Antioquia (a Colombian department), 1 comes from Berastagi (North Sumatra, Indonesia) and 1 only says "Central America". | Recover 6 → Colombia and 1 → Indonesia; set the last one to `Unknown`. Flag all as `country_recovered`. |

## 7. Limitations

1. **Selection bias.** Only lots voluntarily submitted to CQI are included, and producers submit their best coffee: 86.1% of samples are specialty grade (F16). Results compare groups *relative to each other*; they do not estimate the real market share of specialty coffee.
2. **Observational data.** Findings describe associations, not causes (for example, high-altitude farms may also have better processing practices).
3. **Small samples per country.** Honduras has 52 valid samples, unevenly spread over time (F27). Small groups (e.g., Honey processing, n = 14) are reported with a warning.
4. **Self-reported, inconsistent fields.** Altitude is reported by producers in 123 formats, mixing meters and feet (F24, F25); harvest year mixes seasons, quarters and month names (F23).
5. **Non-random missing data.** Altitude, processing method, variety and color are partly missing, and missingness overlaps more than chance would predict (F9). Moisture hides missing values as `0 %` (F21).
6. **Currency.** Data from 2010–2018 may not reflect current varieties, practices or climate conditions.
7. **Scraping artifacts.** Repeated index values, empty columns, embedded line breaks and the scraper author's notes on which web table was parsed (F1, F4, F5) show that some records may have been extracted imperfectly.
8. **Variety is unreliable** (missing, `Other`, and labels that are origins rather than cultivars, F13), so it is out of the analysis scope.
