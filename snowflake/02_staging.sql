-------------------------------------------------------------------------------
-- 02_staging.sql · Typed, cleaned, deduplicated views on RAW
-- Rules: rename to English snake_case, cast types, remove duplicates.
--        No business logic here (thresholds and KPIs live in MART).
-------------------------------------------------------------------------------
USE ROLE SYSADMIN;
USE WAREHOUSE WH_ANALYTICS;
USE SCHEMA RAILANALYTICS.STAGING;

-------------------------------------------------------------------------------
-- Stop events. Grain: one row per trip, operating day and scheduled stop.
-------------------------------------------------------------------------------
CREATE OR REPLACE VIEW STG_STOP_EVENT AS
SELECT
  TO_DATE(BETRIEBSTAG, 'DD.MM.YYYY')                              AS operating_day,
  FAHRT_BEZEICHNER                                                AS trip_id,
  BETREIBER_ABK                                                   AS operator_abbr,
  BETREIBER_NAME                                                  AS operator_name,
  PRODUKT_ID                                                      AS product,
  LINIEN_TEXT                                                     AS line_text,
  VERKEHRSMITTEL_TEXT                                             AS vehicle_category,
  TRY_TO_NUMBER(BPUIC)                                            AS station_uic,
  HALTESTELLEN_NAME                                               AS station_name,
  TRY_TO_TIMESTAMP_NTZ(ANKUNFTSZEIT, 'DD.MM.YYYY HH24:MI')        AS arrival_scheduled,
  TRY_TO_TIMESTAMP_NTZ(AN_PROGNOSE,  'DD.MM.YYYY HH24:MI:SS')     AS arrival_actual,
  NULLIF(AN_PROGNOSE_STATUS, '')                                  AS arrival_status,
  TRY_TO_TIMESTAMP_NTZ(ABFAHRTSZEIT, 'DD.MM.YYYY HH24:MI')        AS departure_scheduled,
  TRY_TO_TIMESTAMP_NTZ(AB_PROGNOSE,  'DD.MM.YYYY HH24:MI:SS')     AS departure_actual,
  NULLIF(AB_PROGNOSE_STATUS, '')                                  AS departure_status,
  COALESCE(LOWER(FAELLT_AUS_TF)  = 'true', FALSE)                 AS is_cancelled,
  COALESCE(LOWER(DURCHFAHRT_TF)  = 'true', FALSE)                 AS is_pass_through,
  COALESCE(LOWER(ZUSATZFAHRT_TF) = 'true', FALSE)                 AS is_extra_trip,
  _SOURCE_FILE                                                    AS source_file,
  _LOADED_AT                                                      AS loaded_at
FROM RAILANALYTICS.RAW.RAW_ISTDATEN
WHERE TRY_TO_NUMBER(BPUIC) IS NOT NULL
-- A file may be loaded twice (FORCE) or corrected by the publisher:
-- keep the most recently loaded version of each stop event.
QUALIFY ROW_NUMBER() OVER (
  PARTITION BY BETRIEBSTAG, FAHRT_BEZEICHNER, BPUIC, ANKUNFTSZEIT, ABFAHRTSZEIT
  ORDER BY _LOADED_AT DESC
) = 1;

-------------------------------------------------------------------------------
-- Station frequency, latest available year per station.
-------------------------------------------------------------------------------
CREATE OR REPLACE VIEW STG_STATION_FREQUENCY AS
SELECT
  TRY_TO_NUMBER(UIC)::NUMBER(9,0)                                 AS station_uic,  -- 8502113.0 -> 8502113
  BAHNHOF_GARE_STAZIONE                                           AS station_name,
  KT_CT_CANTONE                                                   AS canton,
  ISB_GI                                                          AS infrastructure_manager,
  TRY_TO_NUMBER(JAHR_ANNEE_ANNO)                                  AS reference_year,
  TRY_TO_NUMBER(DTV_TJM_TGM)                                      AS passengers_per_day,
  TRY_TO_NUMBER(DWV_TMJO_TFM)                                     AS passengers_per_weekday,
  TRY_TO_NUMBER(DNWV_TMJNO_TMGNL)                                 AS passengers_per_weekend_day,
  TRY_TO_DOUBLE(TRIM(SPLIT_PART(GEOPOS, ',', 1)))                 AS latitude,
  TRY_TO_DOUBLE(TRIM(SPLIT_PART(GEOPOS, ',', 2)))                 AS longitude
FROM RAILANALYTICS.RAW.RAW_PASSAGIERFREQUENZ
WHERE TRY_TO_NUMBER(UIC) IS NOT NULL
QUALIFY ROW_NUMBER() OVER (
  PARTITION BY TRY_TO_NUMBER(UIC)
  ORDER BY TRY_TO_NUMBER(JAHR_ANNEE_ANNO) DESC, _LOADED_AT DESC
) = 1;

-- Sanity check
SELECT 'STG_STOP_EVENT' AS view_name, COUNT(*) AS row_count,
       MIN(operating_day) AS first_day, MAX(operating_day) AS last_day
FROM STG_STOP_EVENT
UNION ALL
SELECT 'STG_STATION_FREQUENCY', COUNT(*), NULL, NULL FROM STG_STATION_FREQUENCY;
