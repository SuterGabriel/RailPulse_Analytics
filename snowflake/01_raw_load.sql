-------------------------------------------------------------------------------
-- 01_raw_load.sql · File format, internal stage, RAW tables, COPY INTO
--
-- Before running the COPY statements, upload the files to the stage:
--   Snowsight: Data > Databases > RAILANALYTICS > RAW > Stages > STG_FILES
--              > "+ Files", folder "istdaten/" for the daily gzip files and
--              folder "frequency/" for passagierfrequenz.csv
--   CLI:       snow stage copy data/processed/ @RAILANALYTICS.RAW.STG_FILES/istdaten/
--              snow stage copy data/raw/passagierfrequenz.csv @RAILANALYTICS.RAW.STG_FILES/frequency/
-------------------------------------------------------------------------------
USE ROLE SYSADMIN;
USE WAREHOUSE WH_ANALYTICS;
USE SCHEMA RAILANALYTICS.RAW;

CREATE FILE FORMAT IF NOT EXISTS FF_CSV_SEMICOLON
  TYPE = CSV
  FIELD_DELIMITER = ';'
  SKIP_HEADER = 1
  FIELD_OPTIONALLY_ENCLOSED_BY = '"'
  EMPTY_FIELD_AS_NULL = TRUE
  ENCODING = 'UTF8'
  COMPRESSION = AUTO          -- handles .csv and .csv.gz alike
  ERROR_ON_COLUMN_COUNT_MISMATCH = TRUE;

CREATE STAGE IF NOT EXISTS STG_FILES
  FILE_FORMAT = FF_CSV_SEMICOLON
  COMMENT = 'Internal stage for source files (istdaten/, frequency/)';

-------------------------------------------------------------------------------
-- Actual data (Ist-Daten v2): 22 source columns as text + load metadata
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS RAW_ISTDATEN (
  BETRIEBSTAG          STRING,
  FAHRT_BEZEICHNER     STRING,
  BETREIBER_ID         STRING,
  BETREIBER_ABK        STRING,
  BETREIBER_NAME       STRING,
  PRODUKT_ID           STRING,
  LINIEN_ID            STRING,
  LINIEN_TEXT          STRING,
  UMLAUF_ID            STRING,
  VERKEHRSMITTEL_TEXT  STRING,
  ZUSATZFAHRT_TF       STRING,
  FAELLT_AUS_TF        STRING,
  BPUIC                STRING,
  HALTESTELLEN_NAME    STRING,
  ANKUNFTSZEIT         STRING,
  AN_PROGNOSE          STRING,
  AN_PROGNOSE_STATUS   STRING,
  ABFAHRTSZEIT         STRING,
  AB_PROGNOSE          STRING,
  AB_PROGNOSE_STATUS   STRING,
  DURCHFAHRT_TF        STRING,
  SLOID                STRING,
  _SOURCE_FILE         STRING,
  _SOURCE_ROW          NUMBER,
  _LOADED_AT           TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- Idempotent: Snowflake remembers loaded files for 64 days and skips them
-- unless FORCE = TRUE is added. Rerunning after adding a new day loads only
-- the new file.
COPY INTO RAW_ISTDATEN (
  BETRIEBSTAG, FAHRT_BEZEICHNER, BETREIBER_ID, BETREIBER_ABK, BETREIBER_NAME,
  PRODUKT_ID, LINIEN_ID, LINIEN_TEXT, UMLAUF_ID, VERKEHRSMITTEL_TEXT,
  ZUSATZFAHRT_TF, FAELLT_AUS_TF, BPUIC, HALTESTELLEN_NAME,
  ANKUNFTSZEIT, AN_PROGNOSE, AN_PROGNOSE_STATUS,
  ABFAHRTSZEIT, AB_PROGNOSE, AB_PROGNOSE_STATUS, DURCHFAHRT_TF, SLOID,
  _SOURCE_FILE, _SOURCE_ROW
)
FROM (
  SELECT $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14,
         $15, $16, $17, $18, $19, $20, $21, $22,
         METADATA$FILENAME, METADATA$FILE_ROW_NUMBER
  FROM @STG_FILES/istdaten/
)
PATTERN = '.*_istdaten_zug\.csv\.gz'
ON_ERROR = 'ABORT_STATEMENT';

-------------------------------------------------------------------------------
-- Passenger frequency per station and year
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS RAW_PASSAGIERFREQUENZ (
  CODE_CODICE             STRING,
  UIC                     STRING,
  BAHNHOF_GARE_STAZIONE   STRING,
  KT_CT_CANTONE           STRING,
  ISB_GI                  STRING,
  JAHR_ANNEE_ANNO         STRING,
  DTV_TJM_TGM             STRING,
  DWV_TMJO_TFM            STRING,
  DNWV_TMJNO_TMGNL        STRING,
  EVU_EF_ITF              STRING,
  BEMERKUNGEN             STRING,
  REMARQUES               STRING,
  NOTE                    STRING,
  REMARKS                 STRING,
  LOD                     STRING,
  GEOPOS                  STRING,
  _SOURCE_FILE            STRING,
  _SOURCE_ROW             NUMBER,
  _LOADED_AT              TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

COPY INTO RAW_PASSAGIERFREQUENZ (
  CODE_CODICE, UIC, BAHNHOF_GARE_STAZIONE, KT_CT_CANTONE, ISB_GI, JAHR_ANNEE_ANNO,
  DTV_TJM_TGM, DWV_TMJO_TFM, DNWV_TMJNO_TMGNL, EVU_EF_ITF,
  BEMERKUNGEN, REMARQUES, NOTE, REMARKS, LOD, GEOPOS,
  _SOURCE_FILE, _SOURCE_ROW
)
FROM (
  SELECT $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16,
         METADATA$FILENAME, METADATA$FILE_ROW_NUMBER
  FROM @STG_FILES/frequency/
)
ON_ERROR = 'ABORT_STATEMENT';

-------------------------------------------------------------------------------
-- Quick check: rows per source file
-------------------------------------------------------------------------------
SELECT _SOURCE_FILE, COUNT(*) AS ROWS_LOADED, MIN(_LOADED_AT) AS LOADED_AT
FROM RAW_ISTDATEN GROUP BY 1
UNION ALL
SELECT _SOURCE_FILE, COUNT(*), MIN(_LOADED_AT)
FROM RAW_PASSAGIERFREQUENZ GROUP BY 1
ORDER BY 1;
