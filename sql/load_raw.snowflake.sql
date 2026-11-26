-- =====================================================================
-- load_raw (Snowflake): reload every raw table from the landing stage.
-- Run by the pipeline script and by the t1_load_raw task.
-- FORCE = TRUE reloads files even if Snowflake has seen them before,
-- because each run replaces the files in the stage.
-- =====================================================================

TRUNCATE TABLE raw.accounts;
COPY INTO raw.accounts FROM @raw.landing/accounts/
  FILE_FORMAT = (FORMAT_NAME = raw.csv_ff) MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
  ON_ERROR = ABORT_STATEMENT FORCE = TRUE;
UPDATE raw.accounts SET _loaded_at = CURRENT_TIMESTAMP WHERE _loaded_at IS NULL;

TRUNCATE TABLE raw.products;
COPY INTO raw.products FROM @raw.landing/products/
  FILE_FORMAT = (FORMAT_NAME = raw.csv_ff) MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
  ON_ERROR = ABORT_STATEMENT FORCE = TRUE;
UPDATE raw.products SET _loaded_at = CURRENT_TIMESTAMP WHERE _loaded_at IS NULL;

TRUNCATE TABLE raw.opportunities;
COPY INTO raw.opportunities FROM @raw.landing/opportunities/
  FILE_FORMAT = (FORMAT_NAME = raw.csv_ff) MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
  ON_ERROR = ABORT_STATEMENT FORCE = TRUE;
UPDATE raw.opportunities SET _loaded_at = CURRENT_TIMESTAMP WHERE _loaded_at IS NULL;

TRUNCATE TABLE raw.quote_lines;
COPY INTO raw.quote_lines FROM @raw.landing/quote_lines/
  FILE_FORMAT = (FORMAT_NAME = raw.csv_ff) MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
  ON_ERROR = ABORT_STATEMENT FORCE = TRUE;
UPDATE raw.quote_lines SET _loaded_at = CURRENT_TIMESTAMP WHERE _loaded_at IS NULL;

TRUNCATE TABLE raw.contracts;
COPY INTO raw.contracts FROM @raw.landing/contracts/
  FILE_FORMAT = (FORMAT_NAME = raw.csv_ff) MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
  ON_ERROR = ABORT_STATEMENT FORCE = TRUE;
UPDATE raw.contracts SET _loaded_at = CURRENT_TIMESTAMP WHERE _loaded_at IS NULL;

TRUNCATE TABLE raw.fx_rates;
COPY INTO raw.fx_rates FROM @raw.landing/fx_rates/
  FILE_FORMAT = (FORMAT_NAME = raw.csv_ff) MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
  ON_ERROR = ABORT_STATEMENT FORCE = TRUE;
UPDATE raw.fx_rates SET _loaded_at = CURRENT_TIMESTAMP WHERE _loaded_at IS NULL;
