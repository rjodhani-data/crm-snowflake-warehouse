-- =====================================================================
-- 00_setup (Snowflake): warehouse, database, schemas, file format, stage
-- Run with a role that can create warehouses/databases (SYSADMIN on a
-- trial account works).
-- =====================================================================

CREATE WAREHOUSE IF NOT EXISTS CRM_WH
  WAREHOUSE_SIZE = 'XSMALL'
  AUTO_SUSPEND = 60          -- seconds; keeps trial credits low
  AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE;

CREATE DATABASE IF NOT EXISTS CRM_DW;
USE DATABASE CRM_DW;
USE WAREHOUSE CRM_WH;

CREATE SCHEMA IF NOT EXISTS raw;       -- landed as-is, all VARCHAR
CREATE SCHEMA IF NOT EXISTS staging;   -- typed, cleaned, de-duplicated views
CREATE SCHEMA IF NOT EXISTS marts;     -- star schema + reporting views

-- CSV format that reads the header row so COPY can match columns by name
CREATE OR REPLACE FILE FORMAT raw.csv_ff
  TYPE = CSV
  PARSE_HEADER = TRUE
  FIELD_OPTIONALLY_ENCLOSED_BY = '"'
  EMPTY_FIELD_AS_NULL = TRUE
  NULL_IF = ('')
  TRIM_SPACE = FALSE;        -- keep raw as-is; trimming happens in staging

CREATE STAGE IF NOT EXISTS raw.landing
  FILE_FORMAT = raw.csv_ff
  COMMENT = 'Internal stage for CSV extracts';
