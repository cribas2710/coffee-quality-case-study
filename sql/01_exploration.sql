-- =============================================
-- Phase 2 — Exploration: row counts, nulls, distinct values, ranges
-- Project: What Makes Great Coffee?
-- Dataset: coffee_quality (BigQuery)
-- =============================================
-- Table: `coffee-quality-case-study.coffee_quality.arabica_raw`
-- Note: every column was loaded as STRING on purpose (raw layer).
--       Type conversion happens explicitly in 02_cleaning.sql.


-- ---------------------------------------------
-- 1. OVERVIEW: size and uniqueness
-- ---------------------------------------------

-- 1.1 Row count and uniqueness of the original index
SELECT
  COUNT(*)                  AS total_rows,
  COUNT(DISTINCT row_index) AS distinct_row_index,
  COUNT(*) - COUNT(DISTINCT row_index) AS repeated_index_values
FROM `coffee-quality-case-study.coffee_quality.arabica_raw`;

-- 1.2 Which index values repeat, and are those rows full duplicates?
SELECT *
FROM `coffee-quality-case-study.coffee_quality.arabica_raw`
WHERE row_index IN (
  SELECT row_index
  FROM `coffee-quality-case-study.coffee_quality.arabica_raw`
  GROUP BY row_index
  HAVING COUNT(*) > 1
)
ORDER BY row_index;


-- ---------------------------------------------
-- 2. COMPLETENESS: missing values
-- ---------------------------------------------

-- 2.1 Candidate junk columns (scraper artifacts): how many non-empty values?
SELECT
  COUNT(view_certificate_1)               AS view_certificate_1,
  COUNT(view_certificate_2)               AS view_certificate_2,
  COUNT(cupping_protocol_and_descriptors) AS cupping_protocol,
  COUNT(view_green_analysis_details)      AS view_green_analysis,
  COUNT(request_a_sample)                 AS request_a_sample,
  COUNT(na_0)                             AS na_0,
  COUNT(na_1)                             AS na_1,
  COUNT(na_2)                             AS na_2,
  COUNT(na_3)                             AS na_3,
  COUNT(unnamed_51)                       AS unnamed_51,
  COUNT(notes)                            AS notes
FROM `coffee-quality-case-study.coffee_quality.arabica_raw`;

-- 2.2 Missing values in the columns we need for the analysis
--     (NULL or blank text both count as missing)
SELECT
  COUNT(*) AS total_rows,
  COUNTIF(country_of_origin    IS NULL OR TRIM(country_of_origin)    = '') AS missing_country,
  COUNTIF(altitude             IS NULL OR TRIM(altitude)             = '') AS missing_altitude,
  COUNTIF(region               IS NULL OR TRIM(region)               = '') AS missing_region,
  COUNTIF(harvest_year         IS NULL OR TRIM(harvest_year)         = '') AS missing_harvest_year,
  COUNTIF(variety              IS NULL OR TRIM(variety)              = '') AS missing_variety,
  COUNTIF(processing_method    IS NULL OR TRIM(processing_method)    = '') AS missing_processing,
  COUNTIF(total_cup_points     IS NULL OR TRIM(total_cup_points)     = '') AS missing_total_points,
  COUNTIF(aroma                IS NULL OR TRIM(aroma)                = '') AS missing_aroma,
  COUNTIF(moisture             IS NULL OR TRIM(moisture)             = '') AS missing_moisture,
  COUNTIF(category_one_defects IS NULL OR TRIM(category_one_defects) = '') AS missing_cat1_defects,
  COUNTIF(category_two_defects IS NULL OR TRIM(category_two_defects) = '') AS missing_cat2_defects,
  COUNTIF(color                IS NULL OR TRIM(color)                = '') AS missing_color
FROM `coffee-quality-case-study.coffee_quality.arabica_raw`;

-- 2.3 The single sample with no country: can it be identified from other columns?
SELECT
  row_index, owner, producer, farm_name, region, mill, company,
  in_country_partner, certification_body, altitude, total_cup_points
FROM `coffee-quality-case-study.coffee_quality.arabica_raw`
WHERE country_of_origin IS NULL OR TRIM(country_of_origin) = '';

-- 2.4 Altitude and color have the same number of missing values (217).
--     Coincidence, or are they missing in the same rows?
SELECT
  COUNTIF(altitude IS NULL AND color IS NULL)     AS both_missing,
  COUNTIF(altitude IS NULL AND color IS NOT NULL) AS only_altitude_missing,
  COUNTIF(altitude IS NOT NULL AND color IS NULL) AS only_color_missing
FROM `coffee-quality-case-study.coffee_quality.arabica_raw`;

-- 2.5 Triangulate the missing country (row_index 1197):
--     what country do other samples from the same owner / in-country partner have?
SELECT
  'owner = Racafe'          AS evidence,
  country_of_origin,
  COUNT(*)                  AS samples
FROM `coffee-quality-case-study.coffee_quality.arabica_raw`
WHERE LOWER(owner) LIKE 'racafe%'
GROUP BY country_of_origin
UNION ALL
SELECT
  'partner = Almacafé',
  country_of_origin,
  COUNT(*)
FROM `coffee-quality-case-study.coffee_quality.arabica_raw`
WHERE in_country_partner = 'Almacafé'
GROUP BY country_of_origin
ORDER BY evidence, samples DESC;


-- ---------------------------------------------
-- 3. CATEGORIES: distinct values and their frequency
-- ---------------------------------------------

-- 3.1 Countries: spelling variants and sample size per country
SELECT
  country_of_origin,
  COUNT(*) AS samples
FROM `coffee-quality-case-study.coffee_quality.arabica_raw`
GROUP BY country_of_origin
ORDER BY samples DESC;

-- 3.2 Processing methods
SELECT
  processing_method,
  COUNT(*) AS samples,
  ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct
FROM `coffee-quality-case-study.coffee_quality.arabica_raw`
GROUP BY processing_method
ORDER BY samples DESC;

-- 3.3 Varieties
SELECT
  variety,
  COUNT(*) AS samples
FROM `coffee-quality-case-study.coffee_quality.arabica_raw`
GROUP BY variety
ORDER BY samples DESC;

-- 3.4 Green bean color
SELECT
  color,
  COUNT(*) AS samples
FROM `coffee-quality-case-study.coffee_quality.arabica_raw`
GROUP BY color
ORDER BY samples DESC;


-- ---------------------------------------------
-- 4. FORMATS & RANGES (part A: scores)
-- ---------------------------------------------

-- 4.1 Can total_cup_points ("Sample  83.58") be parsed, and does it match quality_score?
WITH parsed AS (
  SELECT
    SAFE_CAST(REGEXP_EXTRACT(total_cup_points, r'\d+(?:\.\d+)?') AS FLOAT64) AS total_parsed,
    SAFE_CAST(quality_score AS FLOAT64)                                      AS quality_num
  FROM `coffee-quality-case-study.coffee_quality.arabica_raw`
)
SELECT
  COUNT(*)                                          AS total_rows,
  COUNTIF(total_parsed IS NULL)                     AS failed_parse,
  COUNTIF(ABS(total_parsed - quality_num) > 0.01)   AS mismatch_vs_quality_score,
  MIN(total_parsed)                                 AS min_score,
  MAX(total_parsed)                                 AS max_score,
  ROUND(AVG(total_parsed), 2)                       AS avg_score,
  COUNTIF(total_parsed < 70)                        AS below_70,
  COUNTIF(total_parsed >= 80)                       AS specialty_samples,
  ROUND(100 * COUNTIF(total_parsed >= 80) / COUNT(*), 1) AS specialty_rate_pct
FROM parsed;

-- 4.2 Range of each sensory attribute (UNPIVOT turns 10 columns into rows)
SELECT
  attribute,
  COUNTIF(SAFE_CAST(score AS FLOAT64) IS NULL) AS failed_cast,
  MIN(SAFE_CAST(score AS FLOAT64))             AS min_score,
  MAX(SAFE_CAST(score AS FLOAT64))             AS max_score,
  ROUND(AVG(SAFE_CAST(score AS FLOAT64)), 2)   AS avg_score
FROM `coffee-quality-case-study.coffee_quality.arabica_raw`
UNPIVOT (score FOR attribute IN (
  aroma, flavor, aftertaste, acidity, body, balance,
  uniformity, clean_cup, sweetness, cupper_points
))
GROUP BY attribute
ORDER BY avg_score;

-- 4.3 Is total_cup_points exactly the sum of the 10 attributes?
--     (difference = total - sum; a non-zero difference suggests cup-defect deductions)
WITH s AS (
  SELECT
    SAFE_CAST(REGEXP_EXTRACT(total_cup_points, r'\d+(?:\.\d+)?') AS FLOAT64) AS total,
      SAFE_CAST(aroma AS FLOAT64)      + SAFE_CAST(flavor AS FLOAT64)
    + SAFE_CAST(aftertaste AS FLOAT64) + SAFE_CAST(acidity AS FLOAT64)
    + SAFE_CAST(body AS FLOAT64)       + SAFE_CAST(balance AS FLOAT64)
    + SAFE_CAST(uniformity AS FLOAT64) + SAFE_CAST(clean_cup AS FLOAT64)
    + SAFE_CAST(sweetness AS FLOAT64)  + SAFE_CAST(cupper_points AS FLOAT64) AS attribute_sum
  FROM `coffee-quality-case-study.coffee_quality.arabica_raw`
)
SELECT
  ROUND(total - attribute_sum, 2) AS difference,
  COUNT(*)                        AS samples
FROM s
GROUP BY difference
ORDER BY samples DESC;

-- 4.4 Inspect the anomalies: score = 0, total != attribute sum, cupper_points = 10
WITH s AS (
  SELECT
    row_index, country_of_origin, owner,
    SAFE_CAST(REGEXP_EXTRACT(total_cup_points, r'\d+(?:\.\d+)?') AS FLOAT64) AS total,
      SAFE_CAST(aroma AS FLOAT64)      + SAFE_CAST(flavor AS FLOAT64)
    + SAFE_CAST(aftertaste AS FLOAT64) + SAFE_CAST(acidity AS FLOAT64)
    + SAFE_CAST(body AS FLOAT64)       + SAFE_CAST(balance AS FLOAT64)
    + SAFE_CAST(uniformity AS FLOAT64) + SAFE_CAST(clean_cup AS FLOAT64)
    + SAFE_CAST(sweetness AS FLOAT64)  + SAFE_CAST(cupper_points AS FLOAT64) AS attribute_sum,
    aroma, flavor, cupper_points, uniformity, clean_cup, sweetness
  FROM `coffee-quality-case-study.coffee_quality.arabica_raw`
)
SELECT
  *,
  ROUND(total - attribute_sum, 2) AS difference
FROM s
WHERE total = 0
   OR ABS(total - attribute_sum) > 0.05
   OR SAFE_CAST(cupper_points AS FLOAT64) = 10
ORDER BY total;


-- ---------------------------------------------
-- 4. FORMATS & RANGES (part B: green coffee grading)
-- ---------------------------------------------

-- 4.5 Moisture: distribution of the parsed percentage ("12 %" -> 12)
SELECT
  SAFE_CAST(REGEXP_EXTRACT(moisture, r'\d+(?:\.\d+)?') AS FLOAT64) AS moisture_pct,
  COUNT(*) AS samples
FROM `coffee-quality-case-study.coffee_quality.arabica_raw`
GROUP BY moisture_pct
ORDER BY moisture_pct;

-- 4.6 Defects: parse "2 full defects" -> 2 and summarize each defect type
WITH d AS (
  SELECT
    SAFE_CAST(REGEXP_EXTRACT(category_one_defects, r'\d+') AS INT64) AS cat1_defects,
    SAFE_CAST(REGEXP_EXTRACT(category_two_defects, r'\d+') AS INT64) AS cat2_defects,
    SAFE_CAST(quakers AS INT64)                                      AS quakers
  FROM `coffee-quality-case-study.coffee_quality.arabica_raw`
)
SELECT
  defect_type,
  COUNT(*)                                  AS non_null,   -- UNPIVOT drops NULLs
  COUNTIF(n = 0)                            AS zero_defects,
  ROUND(100 * COUNTIF(n = 0) / COUNT(*), 1) AS pct_zero,
  APPROX_QUANTILES(n, 2)[OFFSET(1)]         AS median,
  ROUND(AVG(n), 2)                          AS avg,
  MAX(n)                                    AS max
FROM d
UNPIVOT (n FOR defect_type IN (cat1_defects, cat2_defects, quakers))
GROUP BY defect_type;


-- ---------------------------------------------
-- 4. FORMATS & RANGES (part C: free-text fields)
-- Technique: "format fingerprint" -- replace every run of digits with '9'
-- so that "1200-1400 msnm" and "1500-1800 msnm" collapse into the same
-- pattern "9-9 msnm". Counting patterns shows how many formats exist.
-- ---------------------------------------------

-- 4.7 Harvest year formats
SELECT
  REGEXP_REPLACE(harvest_year, r'\d+', '9') AS format_pattern,
  COUNT(*)                                  AS samples,
  ANY_VALUE(harvest_year)                   AS example
FROM `coffee-quality-case-study.coffee_quality.arabica_raw`
GROUP BY format_pattern
ORDER BY samples DESC;

-- 4.8 Altitude formats
SELECT
  REGEXP_REPLACE(altitude, r'\d+', '9') AS format_pattern,
  COUNT(*)                              AS samples,
  ANY_VALUE(altitude)                   AS example
FROM `coffee-quality-case-study.coffee_quality.arabica_raw`
GROUP BY format_pattern
ORDER BY samples DESC;

-- 4.9 Unitless altitudes that are physically implausible in meters
--     (Arabica is rarely grown above ~2,500 m): are they feet?
SELECT
  country_of_origin,
  COUNT(*)                         AS samples,
  MIN(SAFE_CAST(altitude AS INT64)) AS min_value,
  MAX(SAFE_CAST(altitude AS INT64)) AS max_value
FROM `coffee-quality-case-study.coffee_quality.arabica_raw`
WHERE REGEXP_CONTAINS(altitude, r'^\d+$')
  AND SAFE_CAST(altitude AS INT64) > 3000
GROUP BY country_of_origin
ORDER BY samples DESC;

-- 4.10 Grading date formats: a possible alternative time variable to harvest_year
SELECT
  REGEXP_REPLACE(grading_date, r'\d+', '9') AS format_pattern,
  COUNT(*)                                  AS samples,
  ANY_VALUE(grading_date)                   AS example
FROM `coffee-quality-case-study.coffee_quality.arabica_raw`
GROUP BY format_pattern
ORDER BY samples DESC;


-- ---------------------------------------------
-- 5. HONDURAS: how much usable data does the client's country have?
-- ---------------------------------------------

-- 5.1 Honduras coverage per analysis variable
SELECT
  COUNT(*)                                                    AS samples,
  COUNTIF(altitude IS NOT NULL)                               AS with_altitude,
  COUNTIF(processing_method IS NOT NULL)                      AS with_processing,
  COUNTIF(harvest_year IS NOT NULL)                           AS with_harvest_year,
  COUNTIF(REGEXP_EXTRACT(moisture, r'\d+') != '0')            AS with_real_moisture,
  MIN(REGEXP_EXTRACT(grading_date, r'\d{4}'))                 AS first_grading_year,
  MAX(REGEXP_EXTRACT(grading_date, r'\d{4}'))                 AS last_grading_year
FROM `coffee-quality-case-study.coffee_quality.arabica_raw`
WHERE country_of_origin = 'Honduras';

-- 5.2 Honduras samples by processing method
SELECT
  IFNULL(processing_method, 'Unknown') AS processing_method,
  COUNT(*)                             AS samples
FROM `coffee-quality-case-study.coffee_quality.arabica_raw`
WHERE country_of_origin = 'Honduras'
GROUP BY processing_method
ORDER BY samples DESC;
