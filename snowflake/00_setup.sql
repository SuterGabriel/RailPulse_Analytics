-------------------------------------------------------------------------------
-- 00_setup.sql · Warehouse, database, schemas, reporting role
-- Run once as SYSADMIN / SECURITYADMIN (both available on a trial account).
-------------------------------------------------------------------------------
USE ROLE SYSADMIN;

-- Smallest warehouse, suspends after 60 s idle: a demo must not burn credits.
CREATE WAREHOUSE IF NOT EXISTS WH_ANALYTICS
  WAREHOUSE_SIZE = 'XSMALL'
  AUTO_SUSPEND   = 60
  AUTO_RESUME    = TRUE
  INITIALLY_SUSPENDED = TRUE
  COMMENT = 'Loading, transformation and reporting for RailPulse Analytics';

CREATE DATABASE IF NOT EXISTS RAILANALYTICS
  COMMENT = 'Swiss rail punctuality demo: RAW -> STAGING -> MART';

CREATE SCHEMA IF NOT EXISTS RAILANALYTICS.RAW
  COMMENT = 'Source files 1:1, all columns as text, never edited manually';
CREATE SCHEMA IF NOT EXISTS RAILANALYTICS.STAGING
  COMMENT = 'Typed, cleaned, deduplicated views on RAW; no business logic';
CREATE SCHEMA IF NOT EXISTS RAILANALYTICS.MART
  COMMENT = 'Star schema for reporting; the only schema exposed to tools';

-------------------------------------------------------------------------------
-- Least privilege for Power BI and Streamlit: read MART, nothing else.
-------------------------------------------------------------------------------
USE ROLE SECURITYADMIN;

CREATE ROLE IF NOT EXISTS ROLE_REPORTING
  COMMENT = 'Read-only access to RAILANALYTICS.MART for reporting tools';

GRANT USAGE  ON WAREHOUSE WH_ANALYTICS            TO ROLE ROLE_REPORTING;
GRANT USAGE  ON DATABASE  RAILANALYTICS           TO ROLE ROLE_REPORTING;
GRANT USAGE  ON SCHEMA    RAILANALYTICS.MART      TO ROLE ROLE_REPORTING;
GRANT SELECT ON ALL    TABLES IN SCHEMA RAILANALYTICS.MART TO ROLE ROLE_REPORTING;
GRANT SELECT ON FUTURE TABLES IN SCHEMA RAILANALYTICS.MART TO ROLE ROLE_REPORTING;
GRANT SELECT ON ALL    VIEWS  IN SCHEMA RAILANALYTICS.MART TO ROLE ROLE_REPORTING;
GRANT SELECT ON FUTURE VIEWS  IN SCHEMA RAILANALYTICS.MART TO ROLE ROLE_REPORTING;

-- Role hierarchy: SYSADMIN can see what the reporting role sees.
GRANT ROLE ROLE_REPORTING TO ROLE SYSADMIN;

-- Technical user for the reporting tools. Set a real password interactively,
-- never store it in this repository.
-- CREATE USER IF NOT EXISTS SVC_REPORTING
--   PASSWORD = '<set-in-snowsight>'
--   DEFAULT_ROLE = ROLE_REPORTING
--   DEFAULT_WAREHOUSE = WH_ANALYTICS
--   MUST_CHANGE_PASSWORD = FALSE;
-- GRANT ROLE ROLE_REPORTING TO USER SVC_REPORTING;
