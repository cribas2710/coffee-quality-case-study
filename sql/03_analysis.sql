-- =============================================
-- Phase 4 — Analysis: aggregations for guiding questions Q1–Q5
-- Project: What Makes Great Coffee?
-- Dataset: coffee_quality (BigQuery)
-- =============================================
-- Table: `coffee-quality-case-study.coffee_quality.arabica_clean` (1,311 rows)
-- Reminder: results describe associations among samples SUBMITTED to CQI
-- (selection bias, F16), not causes and not market-wide shares.


-- ---------------------------------------------
-- Q1. BENCHMARK: where does Honduras stand against other producers?
-- ---------------------------------------------

-- Q1.1 Country ranking (countries with at least 10 samples)
--   ci95_low / ci95_high: 95% confidence interval of the mean
--   (mean ± 1.96 × standard error; standard error = std / √n)
WITH by_country AS (
  SELECT
    country,
    COUNT(*)                                            AS samples,
    AVG(total_cup_points)                               AS mean_score,
    APPROX_QUANTILES(total_cup_points, 2)[OFFSET(1)]    AS median_score,
    STDDEV(total_cup_points)                            AS std_score,
    AVG(CAST(is_specialty AS INT64))                    AS specialty_rate,
    AVG(CAST(total_cup_points >= 85 AS INT64))          AS excellent_rate
  FROM `coffee-quality-case-study.coffee_quality.arabica_clean`
  WHERE country != 'Unknown'
  GROUP BY country
  HAVING COUNT(*) >= 10
)
SELECT
  RANK() OVER (ORDER BY mean_score DESC)                       AS rank_by_mean,
  country,
  samples,
  ROUND(mean_score, 2)                                         AS mean_score,
  ROUND(median_score, 2)                                       AS median_score,
  ROUND(mean_score - 1.96 * std_score / SQRT(samples), 2)      AS ci95_low,
  ROUND(mean_score + 1.96 * std_score / SQRT(samples), 2)      AS ci95_high,
  ROUND(100 * specialty_rate, 1)                               AS specialty_rate_pct,
  ROUND(100 * excellent_rate, 1)                               AS excellent_rate_pct
FROM by_country
ORDER BY rank_by_mean;

-- Q1.2 Honduras vs. the five benchmark competitors (+ all countries)
--   gap_vs_honduras: how many points above (+) or below (-) Honduras
WITH benchmark AS (
  SELECT
    country,
    COUNT(*)                                            AS samples,
    AVG(total_cup_points)                               AS mean_score,
    APPROX_QUANTILES(total_cup_points, 2)[OFFSET(1)]    AS median_score,
    AVG(CAST(is_specialty AS INT64))                    AS specialty_rate,
    AVG(CAST(total_cup_points >= 85 AS INT64))          AS excellent_rate
  FROM `coffee-quality-case-study.coffee_quality.arabica_clean`
  WHERE country IN ('Honduras', 'Colombia', 'Guatemala', 'Costa Rica', 'Ethiopia', 'Brazil')
  GROUP BY country

  UNION ALL

  SELECT
    'All countries',
    COUNT(*),
    AVG(total_cup_points),
    APPROX_QUANTILES(total_cup_points, 2)[OFFSET(1)],
    AVG(CAST(is_specialty AS INT64)),
    AVG(CAST(total_cup_points >= 85 AS INT64))
  FROM `coffee-quality-case-study.coffee_quality.arabica_clean`
)
SELECT
  country,
  samples,
  ROUND(mean_score, 2)                                         AS mean_score,
  ROUND(median_score, 2)                                       AS median_score,
  ROUND(mean_score - MAX(IF(country = 'Honduras', mean_score, NULL)) OVER (), 2) AS gap_vs_honduras,
  ROUND(100 * specialty_rate, 1)                               AS specialty_rate_pct,
  ROUND(100 * excellent_rate, 1)                               AS excellent_rate_pct
FROM benchmark
ORDER BY mean_score DESC;

-- Q1.3 Honduras' lowest scores: what pulls the mean below the median?
SELECT
  sample_id, total_cup_points, processing_method, altitude_m,
  cat1_defects, cat2_defects, uniformity, clean_cup, sweetness, grading_year
FROM `coffee-quality-case-study.coffee_quality.arabica_clean`
WHERE country = 'Honduras'
ORDER BY total_cup_points
LIMIT 8;


-- ---------------------------------------------
-- Q2. ALTITUDE: is altitude associated with higher scores?
-- Bands defined in Phase 1: <1000, 1000-1399, 1400-1799, >=1800 m
-- ---------------------------------------------

-- Q2.1 Score by altitude band (all samples with a valid altitude)
WITH banded AS (
  SELECT
    *,
    CASE
      WHEN altitude_m < 1000 THEN '1. <1000 m'
      WHEN altitude_m < 1400 THEN '2. 1000-1399 m'
      WHEN altitude_m < 1800 THEN '3. 1400-1799 m'
      ELSE                        '4. >=1800 m'
    END AS altitude_band
  FROM `coffee-quality-case-study.coffee_quality.arabica_clean`
  WHERE altitude_m IS NOT NULL
)
SELECT
  altitude_band,
  COUNT(*)                                                         AS samples,
  ROUND(AVG(total_cup_points), 2)                                  AS mean_score,
  ROUND(APPROX_QUANTILES(total_cup_points, 2)[OFFSET(1)], 2)       AS median_score,
  ROUND(AVG(total_cup_points) - 1.96 * STDDEV(total_cup_points) / SQRT(COUNT(*)), 2) AS ci95_low,
  ROUND(AVG(total_cup_points) + 1.96 * STDDEV(total_cup_points) / SQRT(COUNT(*)), 2) AS ci95_high,
  ROUND(100 * AVG(CAST(is_specialty AS INT64)), 1)                 AS specialty_rate_pct,
  ROUND(100 * AVG(CAST(total_cup_points >= 85 AS INT64)), 1)       AS excellent_rate_pct,
  COUNTIF(country = 'Honduras')                                    AS honduras_samples
FROM banded
GROUP BY altitude_band
ORDER BY altitude_band;

-- Q2.2 Robustness check: same bands using ONLY altitudes reported in meters or
--      explicit feet (excludes 'assumed_feet' and 'recovered', Phase 3 steps 28 and 30)
WITH banded AS (
  SELECT
    *,
    CASE
      WHEN altitude_m < 1000 THEN '1. <1000 m'
      WHEN altitude_m < 1400 THEN '2. 1000-1399 m'
      WHEN altitude_m < 1800 THEN '3. 1400-1799 m'
      ELSE                        '4. >=1800 m'
    END AS altitude_band
  FROM `coffee-quality-case-study.coffee_quality.arabica_clean`
  WHERE altitude_flag IN ('meters', 'feet')
)
SELECT
  altitude_band,
  COUNT(*)                                                         AS samples,
  ROUND(AVG(total_cup_points), 2)                                  AS mean_score,
  ROUND(100 * AVG(CAST(total_cup_points >= 85 AS INT64)), 1)       AS excellent_rate_pct
FROM banded
GROUP BY altitude_band
ORDER BY altitude_band;


-- ---------------------------------------------
-- Q3. PROCESSING: which method is associated with higher scores and fewer defects?
-- ---------------------------------------------

-- Q3.1 Score and defects by processing method
SELECT
  processing_method,
  COUNT(*)                                                         AS samples,
  ROUND(AVG(total_cup_points), 2)                                  AS mean_score,
  ROUND(APPROX_QUANTILES(total_cup_points, 2)[OFFSET(1)], 2)       AS median_score,
  ROUND(AVG(total_cup_points) - 1.96 * STDDEV(total_cup_points) / SQRT(COUNT(*)), 2) AS ci95_low,
  ROUND(AVG(total_cup_points) + 1.96 * STDDEV(total_cup_points) / SQRT(COUNT(*)), 2) AS ci95_high,
  ROUND(100 * AVG(CAST(total_cup_points >= 85 AS INT64)), 1)       AS excellent_rate_pct,
  ROUND(100 * AVG(CAST(cat1_defects > 0 AS INT64)), 1)             AS pct_with_cat1_defect,
  ROUND(AVG(cat2_defects), 2)                                      AS mean_cat2_defects
FROM `coffee-quality-case-study.coffee_quality.arabica_clean`
GROUP BY processing_method
ORDER BY mean_score DESC;

-- Q3.2 Is the method a country effect? Methods used by the benchmark countries
SELECT
  country,
  COUNTIF(processing_method = 'Washed')      AS washed,
  COUNTIF(processing_method = 'Natural')     AS natural,
  COUNTIF(processing_method = 'Semi-washed') AS semi_washed,
  COUNTIF(processing_method = 'Honey')       AS honey,
  COUNTIF(processing_method IN ('Other', 'Unknown')) AS other_or_unknown
FROM `coffee-quality-case-study.coffee_quality.arabica_clean`
WHERE country IN ('Honduras', 'Colombia', 'Guatemala', 'Costa Rica', 'Ethiopia', 'Brazil', 'Mexico')
GROUP BY country
ORDER BY washed DESC;


-- ---------------------------------------------
-- Q4. DEFECTS: how strongly are defects associated with lower scores?
-- ---------------------------------------------

-- Q4.1 Score by number of Category 2 (secondary) defects
SELECT
  CASE
    WHEN cat2_defects = 0  THEN '1. 0'
    WHEN cat2_defects <= 2 THEN '2. 1-2'
    WHEN cat2_defects <= 5 THEN '3. 3-5'
    WHEN cat2_defects <= 10 THEN '4. 6-10'
    ELSE                        '5. >10'
  END                                                              AS cat2_defects_band,
  COUNT(*)                                                         AS samples,
  ROUND(AVG(total_cup_points), 2)                                  AS mean_score,
  ROUND(APPROX_QUANTILES(total_cup_points, 2)[OFFSET(1)], 2)       AS median_score,
  ROUND(100 * AVG(CAST(is_specialty AS INT64)), 1)                 AS specialty_rate_pct,
  ROUND(100 * AVG(CAST(total_cup_points >= 85 AS INT64)), 1)       AS excellent_rate_pct
FROM `coffee-quality-case-study.coffee_quality.arabica_clean`
GROUP BY cat2_defects_band
ORDER BY cat2_defects_band;

-- Q4.2 Score with vs. without any Category 1 (severe) defect
SELECT
  cat1_defects > 0                                                 AS has_cat1_defect,
  COUNT(*)                                                         AS samples,
  ROUND(AVG(total_cup_points), 2)                                  AS mean_score,
  ROUND(APPROX_QUANTILES(total_cup_points, 2)[OFFSET(1)], 2)       AS median_score,
  ROUND(100 * AVG(CAST(is_specialty AS INT64)), 1)                 AS specialty_rate_pct
FROM `coffee-quality-case-study.coffee_quality.arabica_clean`
GROUP BY has_cat1_defect;

-- Q4.3 Cup defects: samples where at least one cup out of five failed
--      (clean_cup or uniformity below 10, the pattern of Honduras' low tail in Q1)
SELECT
  clean_cup < 10 OR uniformity < 10                                AS has_defective_cup,
  COUNT(*)                                                         AS samples,
  ROUND(AVG(total_cup_points), 2)                                  AS mean_score,
  ROUND(100 * AVG(CAST(is_specialty AS INT64)), 1)                 AS specialty_rate_pct,
  COUNTIF(country = 'Honduras')                                    AS honduras_samples
FROM `coffee-quality-case-study.coffee_quality.arabica_clean`
GROUP BY has_defective_cup;

-- Q4.4 Defect profile: Honduras vs. benchmark competitors
SELECT
  country,
  COUNT(*)                                                         AS samples,
  ROUND(100 * AVG(CAST(cat1_defects > 0 AS INT64)), 1)             AS pct_with_cat1_defect,
  ROUND(AVG(cat2_defects), 2)                                      AS mean_cat2_defects,
  ROUND(100 * AVG(CAST(clean_cup < 10 OR uniformity < 10 AS INT64)), 1) AS pct_defective_cup
FROM `coffee-quality-case-study.coffee_quality.arabica_clean`
WHERE country IN ('Honduras', 'Colombia', 'Guatemala', 'Costa Rica', 'Ethiopia', 'Brazil')
GROUP BY country
ORDER BY pct_defective_cup;


-- ---------------------------------------------
-- Q5. SENSORY PROFILE: where does Honduras win or lose points?
-- Focus on the 7 attributes that vary between samples; uniformity,
-- clean_cup and sweetness have a ceiling effect (F17).
-- ---------------------------------------------

-- Q5.1 Mean of each attribute: Honduras vs. benchmark competitors
SELECT
  country,
  COUNT(*)                        AS samples,
  ROUND(AVG(aroma), 2)            AS aroma,
  ROUND(AVG(flavor), 2)           AS flavor,
  ROUND(AVG(aftertaste), 2)       AS aftertaste,
  ROUND(AVG(acidity), 2)          AS acidity,
  ROUND(AVG(body), 2)             AS body,
  ROUND(AVG(balance), 2)          AS balance,
  ROUND(AVG(cupper_points), 2)    AS cupper_points
FROM `coffee-quality-case-study.coffee_quality.arabica_clean`
WHERE country IN ('Honduras', 'Colombia', 'Guatemala', 'Costa Rica', 'Ethiopia', 'Brazil')
GROUP BY country
ORDER BY AVG(total_cup_points) DESC;

-- Q5.2 Honduras' gap per attribute vs. the average of the 5 competitors
--      (negative = Honduras scores lower on that attribute)
WITH long_format AS (
  SELECT country, attribute, score
  FROM `coffee-quality-case-study.coffee_quality.arabica_clean`
  UNPIVOT (score FOR attribute IN (
    aroma, flavor, aftertaste, acidity, body, balance, cupper_points
  ))
  WHERE country IN ('Honduras', 'Colombia', 'Guatemala', 'Costa Rica', 'Ethiopia', 'Brazil')
)
SELECT
  attribute,
  ROUND(AVG(IF(country = 'Honduras', score, NULL)), 2)   AS honduras,
  ROUND(AVG(IF(country != 'Honduras', score, NULL)), 2)  AS competitors,
  ROUND(AVG(IF(country = 'Honduras', score, NULL))
      - AVG(IF(country != 'Honduras', score, NULL)), 2)  AS gap
FROM long_format
GROUP BY attribute
ORDER BY gap;


-- ---------------------------------------------
-- EXTRA. TREND: has Honduras improved over time?
-- Uses grading_year (complete and consistent, F26). Honduras has
-- enough samples only for 2014-2017 (F27).
-- ---------------------------------------------
SELECT
  grading_year,
  COUNTIF(country = 'Honduras')                                              AS honduras_samples,
  ROUND(AVG(IF(country = 'Honduras', total_cup_points, NULL)), 2)            AS honduras_mean,
  ROUND(AVG(IF(country = 'Honduras' AND NOT (clean_cup < 10 OR uniformity < 10),
               total_cup_points, NULL)), 2)                                  AS honduras_mean_no_defective_cup,
  COUNTIF(country IN ('Colombia', 'Guatemala', 'Costa Rica', 'Ethiopia', 'Brazil')) AS competitor_samples,
  ROUND(AVG(IF(country IN ('Colombia', 'Guatemala', 'Costa Rica', 'Ethiopia', 'Brazil'),
               total_cup_points, NULL)), 2)                                  AS competitors_mean
FROM `coffee-quality-case-study.coffee_quality.arabica_clean`
WHERE grading_year BETWEEN 2014 AND 2017
GROUP BY grading_year
ORDER BY grading_year;
