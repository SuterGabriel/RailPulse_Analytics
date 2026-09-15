-------------------------------------------------------------------------------
-- 03_mart.sql · Star schema for reporting
--
--   DIM_DATE     --+
--   DIM_STATION  --+-- FACT_STOP_EVENT
--   DIM_OPERATOR --+
--
-- Grain of FACT_STOP_EVENT: one row per scheduled arrival of a trip at a
-- station on an operating day. The first stop of a trip has no scheduled
-- arrival and is therefore not in the fact table.
--
-- KPI definitions (see README):
--   on time        : arrival delay < 3 minutes (180 s), measured arrivals only
--   punctuality    : on-time stops / measured, not cancelled stops
--   cancellation   : cancelled stops / all scheduled stops
-- Measured = arrival_status in (REAL, GESCHAETZT). Forecast-only or unknown
-- arrivals get delay NULL and are excluded from the punctuality rate.
--
-- All tables are rebuilt in full (CREATE OR REPLACE). Surrogate keys are
-- ROW_NUMBER over a stable natural key, so they are deterministic for a given
-- data set. Run 00 to 02 first.
-------------------------------------------------------------------------------
USE ROLE SYSADMIN;
USE WAREHOUSE WH_ANALYTICS;
USE SCHEMA RAILANALYTICS.MART;

SET on_time_threshold_sec = 180;

-------------------------------------------------------------------------------
-- DIM_DATE: every calendar day of the loaded range
-------------------------------------------------------------------------------
CREATE OR REPLACE TABLE DIM_DATE AS
WITH bounds AS (
  SELECT MIN(operating_day) AS d_min, MAX(operating_day) AS d_max
  FROM RAILANALYTICS.STAGING.STG_STOP_EVENT
),
days AS (
  SELECT DATEADD('day', SEQ4(), (SELECT d_min FROM bounds)) AS d
  FROM TABLE(GENERATOR(ROWCOUNT => 400))
)
SELECT
  TO_NUMBER(TO_CHAR(d, 'YYYYMMDD'))         AS date_key,
  d                                         AS date,
  YEAR(d)                                   AS year,
  MONTH(d)                                  AS month,
  MONTHNAME(d)                              AS month_name,
  WEEKISO(d)                                AS iso_week,
  DAYOFWEEKISO(d)                           AS iso_weekday,          -- 1 = Monday
  DECODE(DAYOFWEEKISO(d), 1,'Monday', 2,'Tuesday', 3,'Wednesday', 4,'Thursday',
                          5,'Friday', 6,'Saturday', 7,'Sunday')     AS weekday_name,
  DAYOFWEEKISO(d) >= 6                      AS is_weekend
FROM days
WHERE d <= (SELECT d_max FROM bounds);

-------------------------------------------------------------------------------
-- DIM_OPERATOR
-------------------------------------------------------------------------------
CREATE OR REPLACE TABLE DIM_OPERATOR AS
SELECT
  ROW_NUMBER() OVER (ORDER BY operator_abbr)  AS operator_key,
  operator_abbr,
  operator_name
FROM (
  SELECT operator_abbr, MAX(operator_name) AS operator_name
  FROM RAILANALYTICS.STAGING.STG_STOP_EVENT
  GROUP BY operator_abbr
);

-------------------------------------------------------------------------------
-- DIM_STATION: every station seen in the stop events, enriched with the
-- passenger frequency where a Swiss station record exists.
-------------------------------------------------------------------------------
CREATE OR REPLACE TABLE DIM_STATION AS
WITH seen AS (
  SELECT station_uic,
         MODE(station_name)     AS station_name,
         COUNT(*)               AS stop_events
  FROM RAILANALYTICS.STAGING.STG_STOP_EVENT
  GROUP BY station_uic
)
SELECT
  ROW_NUMBER() OVER (ORDER BY s.station_uic)   AS station_key,
  s.station_uic,
  COALESCE(f.station_name, s.station_name)     AS station_name,
  f.canton,
  f.infrastructure_manager,
  f.passengers_per_day,
  f.passengers_per_weekday,
  f.passengers_per_weekend_day,
  f.reference_year                             AS frequency_year,
  f.latitude,
  f.longitude,
  f.station_uic IS NOT NULL                    AS has_frequency_data,
  s.stop_events
FROM seen s
LEFT JOIN RAILANALYTICS.STAGING.STG_STATION_FREQUENCY f
       ON f.station_uic = s.station_uic;

-------------------------------------------------------------------------------
-- FACT_STOP_EVENT
-------------------------------------------------------------------------------
CREATE OR REPLACE TABLE FACT_STOP_EVENT AS
SELECT
  TO_NUMBER(TO_CHAR(e.operating_day, 'YYYYMMDD'))        AS date_key,
  st.station_key,
  op.operator_key,
  e.trip_id,
  e.line_text,
  e.vehicle_category,
  e.arrival_scheduled,
  e.arrival_actual,
  e.arrival_status,
  HOUR(e.arrival_scheduled)                              AS scheduled_hour,
  e.arrival_status IN ('REAL', 'GESCHAETZT') AND NOT e.is_cancelled
                                                         AS is_measured,
  -- delay only where an actual arrival was measured or estimated
  IFF(e.arrival_status IN ('REAL', 'GESCHAETZT') AND NOT e.is_cancelled,
      DATEDIFF('second', e.arrival_scheduled, e.arrival_actual) / 60.0,
      NULL)                                              AS arrival_delay_min,
  IFF(e.arrival_status IN ('REAL', 'GESCHAETZT') AND NOT e.is_cancelled,
      DATEDIFF('second', e.arrival_scheduled, e.arrival_actual) < $on_time_threshold_sec,
      NULL)                                              AS is_on_time,
  e.is_cancelled,
  e.is_extra_trip,
  e.source_file
FROM RAILANALYTICS.STAGING.STG_STOP_EVENT e
JOIN DIM_STATION  st ON st.station_uic   = e.station_uic
JOIN DIM_OPERATOR op ON op.operator_abbr = e.operator_abbr
WHERE e.arrival_scheduled IS NOT NULL      -- first stop of a trip has none
  AND NOT e.is_pass_through;               -- train does not stop here

-------------------------------------------------------------------------------
-- Result overview
-------------------------------------------------------------------------------
SELECT
  COUNT(*)                                                    AS stop_events,
  COUNT_IF(is_cancelled)                                      AS cancelled,
  COUNT_IF(is_measured)                                       AS measured,
  ROUND(AVG(IFF(is_measured, IFF(is_on_time, 1, 0), NULL)), 4) AS punctuality_rate,
  ROUND(AVG(arrival_delay_min), 2)                            AS avg_delay_min
FROM FACT_STOP_EVENT;
