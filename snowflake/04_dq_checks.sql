-------------------------------------------------------------------------------
-- 04_dq_checks.sql · Data quality checks after every load
-- Each check inserts one row with STATUS = OK, FAIL or INFO.
-- Run the whole script; the last statement lists all results.
-------------------------------------------------------------------------------
USE ROLE SYSADMIN;
USE WAREHOUSE WH_ANALYTICS;
USE SCHEMA RAILANALYTICS.MART;

CREATE OR REPLACE TEMPORARY TABLE dq_results (
  check_name STRING, severity STRING, observed NUMBER, status STRING
);

-- 1. Fact grain is unique
INSERT INTO dq_results
SELECT 'fact_grain_unique', 'ERROR', COUNT(*), IFF(COUNT(*) = 0, 'OK', 'FAIL')
FROM (
  SELECT date_key, trip_id, station_key, arrival_scheduled
  FROM FACT_STOP_EVENT
  GROUP BY 1, 2, 3, 4 HAVING COUNT(*) > 1
);

-- 2. No orphan keys (every fact row joins to each dimension)
INSERT INTO dq_results
SELECT 'fact_orphan_keys', 'ERROR', COUNT(*), IFF(COUNT(*) = 0, 'OK', 'FAIL')
FROM FACT_STOP_EVENT f
LEFT JOIN DIM_DATE     d ON d.date_key     = f.date_key
LEFT JOIN DIM_STATION  s ON s.station_key  = f.station_key
LEFT JOIN DIM_OPERATOR o ON o.operator_key = f.operator_key
WHERE d.date_key IS NULL OR s.station_key IS NULL OR o.operator_key IS NULL;

-- 3. Row count STAGING (eligible rows) vs MART
INSERT INTO dq_results
SELECT 'staging_vs_mart_rowcount', 'ERROR', diff, IFF(diff = 0, 'OK', 'FAIL')
FROM (
  SELECT (SELECT COUNT(*) FROM RAILANALYTICS.STAGING.STG_STOP_EVENT
           WHERE arrival_scheduled IS NOT NULL AND NOT is_pass_through)
       - (SELECT COUNT(*) FROM FACT_STOP_EVENT) AS diff
);

-- 4. Implausible delays (more than 5 h late or 30 min early)
INSERT INTO dq_results
SELECT 'implausible_delays', 'WARN', COUNT(*), IFF(COUNT(*) = 0, 'OK', 'FAIL')
FROM FACT_STOP_EVENT
WHERE arrival_delay_min > 300 OR arrival_delay_min < -30;

-- 5. Punctuality rate in a plausible band (Swiss rail is usually 85 to 95 %)
INSERT INTO dq_results
SELECT 'punctuality_rate_pct', 'WARN', ROUND(rate * 100, 1),
       IFF(rate BETWEEN 0.70 AND 0.99, 'OK', 'FAIL')
FROM (SELECT AVG(IFF(is_on_time, 1, 0)) AS rate FROM FACT_STOP_EVENT WHERE is_measured);

-- 6. Every loaded operating day has fact rows
INSERT INTO dq_results
SELECT 'days_without_events', 'ERROR', COUNT(*), IFF(COUNT(*) = 0, 'OK', 'FAIL')
FROM (
  SELECT DISTINCT TO_DATE(BETRIEBSTAG, 'DD.MM.YYYY') AS d
  FROM RAILANALYTICS.RAW.RAW_ISTDATEN
) r
LEFT JOIN (SELECT DISTINCT date_key FROM FACT_STOP_EVENT) f
       ON f.date_key = TO_NUMBER(TO_CHAR(r.d, 'YYYYMMDD'))
WHERE f.date_key IS NULL;

-- 7. Stations without frequency data (expected for foreign and small stops)
INSERT INTO dq_results
SELECT 'stations_without_frequency', 'INFO', COUNT(*), 'INFO'
FROM DIM_STATION WHERE NOT has_frequency_data;

-- 8. Share of fact rows with a measured arrival (low share = feed issue)
INSERT INTO dq_results
SELECT 'measured_share_pct', 'WARN', ROUND(share * 100, 1),
       IFF(share >= 0.60, 'OK', 'FAIL')
FROM (SELECT AVG(IFF(is_measured, 1, 0)) AS share FROM FACT_STOP_EVENT);

SELECT * FROM dq_results ORDER BY IFF(status = 'FAIL', 0, 1), check_name;
