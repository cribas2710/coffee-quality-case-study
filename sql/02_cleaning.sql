-- =============================================
-- Phase 3 — Cleaning: structural cleaning of the raw CQI Arabica table
-- Project: What Makes Great Coffee?
-- Dataset: coffee_quality (BigQuery)
-- =============================================
-- Input : coffee_quality.arabica_raw    (1,312 rows, 53 STRING columns, never modified)
-- Output: coffee_quality.arabica_stage  (1,311 rows, typed and standardized)
--
-- Pipeline:
--   arabica_raw --[this script]--> arabica_stage --[Python: altitude, harvest year]--> arabica_clean
--
-- Every rule below references an exploration finding (F#) in
-- docs/02_prepare_data_sources.md and is logged in docs/03_process_changelog.md.
-- =============================================

CREATE OR REPLACE TABLE `coffee-quality-case-study.coffee_quality.arabica_stage` AS

WITH

-- ---------------------------------------------
-- STEP 1. Select the columns we keep and convert types
--   Dropped (F4, F5, dictionary): 11 scraper artifacts, owner_1, lot_number,
--   ico_number, expiration, certification_*, status, species, number_of_bags,
--   bag_weight, quality_score (used only to validate total_cup_points, F15)
-- ---------------------------------------------
typed AS (
  SELECT
    SAFE_CAST(row_index AS INT64)                  AS source_row_index,

    -- origin & producer (text, trimmed)
    TRIM(country_of_origin)                        AS country_raw,
    TRIM(region)                                   AS region,
    TRIM(owner)                                    AS owner,
    TRIM(producer)                                 AS producer,
    TRIM(farm_name)                                AS farm_name,
    TRIM(mill)                                     AS mill,
    TRIM(company)                                  AS company,
    TRIM(in_country_partner)                       AS in_country_partner,

    -- free-text fields parsed later in Python (F23, F24, F25)
    TRIM(altitude)                                 AS altitude_raw,
    TRIM(harvest_year)                             AS harvest_year_raw,

    -- "April 4th, 2015" -> DATE (F26): collapse line breaks, drop st/nd/rd/th
    SAFE.PARSE_DATE('%B %d, %Y',
      REGEXP_REPLACE(
        TRIM(REGEXP_REPLACE(grading_date, r'\s+', ' ')),
        r'(\d+)(st|nd|rd|th)', r'\1'))             AS grading_date,

    TRIM(variety)                                  AS variety_raw,
    TRIM(processing_method)                        AS processing_raw,
    TRIM(color)                                    AS color_raw,

    -- sensory scores (F17)
    SAFE_CAST(aroma         AS FLOAT64)            AS aroma,
    SAFE_CAST(flavor        AS FLOAT64)            AS flavor,
    SAFE_CAST(aftertaste    AS FLOAT64)            AS aftertaste,
    SAFE_CAST(acidity       AS FLOAT64)            AS acidity,
    SAFE_CAST(body          AS FLOAT64)            AS body,
    SAFE_CAST(balance       AS FLOAT64)            AS balance,
    SAFE_CAST(uniformity    AS FLOAT64)            AS uniformity,
    SAFE_CAST(clean_cup     AS FLOAT64)            AS clean_cup,
    SAFE_CAST(sweetness     AS FLOAT64)            AS sweetness,
    SAFE_CAST(cupper_points AS FLOAT64)            AS cupper_points,

    -- "Sample  83.58" -> 83.58 (F15)
    SAFE_CAST(REGEXP_EXTRACT(total_cup_points, r'\d+(?:\.\d+)?') AS FLOAT64) AS total_cup_points,

    -- "12 %" -> 12 ; "2 full defects" -> 2 (F21, F22)
    SAFE_CAST(REGEXP_EXTRACT(moisture, r'\d+(?:\.\d+)?') AS FLOAT64)         AS moisture_parsed,
    SAFE_CAST(REGEXP_EXTRACT(category_one_defects, r'\d+') AS INT64)         AS cat1_defects,
    SAFE_CAST(REGEXP_EXTRACT(category_two_defects, r'\d+') AS INT64)         AS cat2_defects,
    SAFE_CAST(quakers AS INT64)                                              AS quakers
  FROM `coffee-quality-case-study.coffee_quality.arabica_raw`
),

-- ---------------------------------------------
-- STEP 2. Standardize categories and handle hidden missing values
-- ---------------------------------------------
standardized AS (
  SELECT
    * EXCEPT (country_raw, variety_raw, processing_raw, color_raw, moisture_parsed),

    -- Country (F8, F10, F11, F28)
    CASE
      WHEN country_raw IS NULL AND LOWER(owner) LIKE 'racafe%'          THEN 'Colombia'
      WHEN country_raw = 'United States'
           AND in_country_partner = 'Almacafé'
           AND region LIKE 'Antioqu%'                                    THEN 'Colombia'
      WHEN country_raw = 'United States'
           AND LOWER(region) LIKE '%berastagi%'                          THEN 'Indonesia'
      WHEN country_raw = 'United States'                                 THEN 'Unknown'
      WHEN country_raw = 'Tanzania, United Republic Of'                  THEN 'Tanzania'
      WHEN STARTS_WITH(country_raw, 'Cote d')                            THEN "Côte d'Ivoire"
      ELSE country_raw
    END AS country,

    -- TRUE when the country was inferred from other columns, not taken from the source
    (country_raw IS NULL OR country_raw = 'United States')               AS country_recovered,

    -- Processing method: short labels, missing -> Unknown (F12)
    CASE processing_raw
      WHEN 'Washed / Wet'              THEN 'Washed'
      WHEN 'Natural / Dry'             THEN 'Natural'
      WHEN 'Semi-washed / Semi-pulped' THEN 'Semi-washed'
      WHEN 'Pulped natural / honey'    THEN 'Honey'
      WHEN 'Other'                     THEN 'Other'
      ELSE 'Unknown'
    END AS processing_method,

    -- Variety: out of scope, only missing -> Unknown (F13)
    IFNULL(variety_raw, 'Unknown') AS variety,

    -- Color: 'None' is a hidden missing value; Blue-Green = Bluish-Green (F14)
    CASE
      WHEN color_raw IS NULL OR color_raw = 'None' THEN 'Unknown'
      WHEN color_raw = 'Blue-Green'                THEN 'Bluish-Green'
      ELSE color_raw
    END AS color,

    -- Moisture: 0 % means "not measured" -> NULL (F21, option A)
    NULLIF(moisture_parsed, 0) AS moisture_pct,
    CASE
      WHEN moisture_parsed IS NULL OR moisture_parsed = 0 THEN 'missing'
      WHEN moisture_parsed < 8 OR moisture_parsed > 16    THEN 'implausible'
      ELSE 'ok'
    END AS moisture_flag
  FROM typed
)

-- ---------------------------------------------
-- STEP 3. Remove invalid records, add a new key and derived metrics
-- ---------------------------------------------
SELECT
  -- new unique key (F1, F2): the scraper index has duplicates
  ROW_NUMBER() OVER (ORDER BY source_row_index, country) AS sample_id,
  *,
  EXTRACT(YEAR FROM grading_date)          AS grading_year,
  total_cup_points >= 80                   AS is_specialty,
  cat1_defects + cat2_defects              AS total_defects
FROM standardized
-- the empty record (all scores = 0, Honduras #1310) is not a real grading (F19)
WHERE total_cup_points > 0;


-- =============================================
-- VALIDATION: run after creating arabica_stage
-- =============================================

-- V1. Row count and key uniqueness (expected: 1,311 rows, 1,311 distinct ids)
SELECT
  COUNT(*)                  AS total_rows,
  COUNT(DISTINCT sample_id) AS distinct_ids,
  COUNTIF(country = 'Honduras') AS honduras_rows
FROM `coffee-quality-case-study.coffee_quality.arabica_stage`;

-- V2. Did every conversion work? (expected: all 0 except quakers = 1, moisture = 253)
SELECT
  COUNTIF(grading_date     IS NULL) AS null_grading_date,
  COUNTIF(total_cup_points IS NULL) AS null_total,
  COUNTIF(aroma            IS NULL) AS null_aroma,
  COUNTIF(cat1_defects     IS NULL) AS null_cat1,
  COUNTIF(cat2_defects     IS NULL) AS null_cat2,
  COUNTIF(quakers          IS NULL) AS null_quakers,
  COUNTIF(moisture_pct     IS NULL) AS null_moisture,
  MIN(total_cup_points)             AS min_total,
  MIN(grading_date)                 AS first_grading,
  MAX(grading_date)                 AS last_grading
FROM `coffee-quality-case-study.coffee_quality.arabica_stage`;

-- V3. Recovered countries (expected: 9 rows)
SELECT
  source_row_index, country, owner, region, in_country_partner
FROM `coffee-quality-case-study.coffee_quality.arabica_stage`
WHERE country_recovered
ORDER BY country;

-- V4. Category distributions after standardization
SELECT 'processing_method' AS field, processing_method AS value, COUNT(*) AS samples
FROM `coffee-quality-case-study.coffee_quality.arabica_stage` GROUP BY processing_method
UNION ALL
SELECT 'color', color, COUNT(*)
FROM `coffee-quality-case-study.coffee_quality.arabica_stage` GROUP BY color
UNION ALL
SELECT 'moisture_flag', moisture_flag, COUNT(*)
FROM `coffee-quality-case-study.coffee_quality.arabica_stage` GROUP BY moisture_flag
ORDER BY field, samples DESC;


-- =============================================
-- STAGE 3: after the Python notebook
-- Upload data/clean/coffee_arabica_clean.csv as coffee_quality.arabica_clean
-- (schema auto-detect, header row skipped), then validate:
-- =============================================

-- V5. Final table (expected: 1,311 rows, Honduras 52, altitude 1,069, 0 out-of-range altitudes)
SELECT
  COUNT(*)                                          AS total_rows,
  COUNT(DISTINCT sample_id)                         AS distinct_ids,
  COUNTIF(country = 'Honduras')                     AS honduras_rows,
  COUNT(altitude_m)                                 AS with_altitude,
  COUNTIF(altitude_m NOT BETWEEN 100 AND 3000)      AS altitude_out_of_range,
  COUNT(harvest_year)                               AS with_harvest_year,
  ROUND(AVG(total_cup_points), 2)                   AS avg_score,
  ROUND(100 * AVG(CAST(is_specialty AS INT64)), 1)  AS specialty_rate_pct
FROM `coffee-quality-case-study.coffee_quality.arabica_clean`;
