-- =====================================================================
-- 08_tasks (Snowflake): orchestrate the pipeline as a Snowflake Tasks DAG.
--
--   t1_load_raw  (daily 07:00 IST)
--        |
--   t2_staging
--     /      \
--  t3_dim_date  t3_dimensions     (run in parallel)
--     \      /
--   t4_facts
--        |
--   t5_reporting_views
--        |
--   t6_data_quality   (logs every check; fails the run on errors)
--
-- Each task runs a SQL file straight from the orchestration.sql_repo
-- stage with EXECUTE IMMEDIATE FROM, so the files in sql/ stay the single
-- source of truth. Deployed by src/deploy_tasks.py.
-- =====================================================================

-- A DAG can only be changed while its root task is suspended
ALTER TASK IF EXISTS orchestration.t1_load_raw SUSPEND;

CREATE TABLE IF NOT EXISTS orchestration.dq_results (
    run_at        TIMESTAMP_LTZ,
    check_name    VARCHAR,
    severity      VARCHAR,
    failed_rows   NUMBER
);

CREATE OR REPLACE TASK orchestration.t1_load_raw
  WAREHOUSE = CRM_WH
  SCHEDULE = 'USING CRON 0 7 * * * Asia/Kolkata'
  COMMENT = 'Root task: reload raw tables from the landing stage'
AS
  EXECUTE IMMEDIATE FROM @orchestration.sql_repo/load_raw.snowflake.sql;

CREATE OR REPLACE TASK orchestration.t2_staging
  WAREHOUSE = CRM_WH
  AFTER orchestration.t1_load_raw
AS
  EXECUTE IMMEDIATE FROM @orchestration.sql_repo/02_staging.sql;

CREATE OR REPLACE TASK orchestration.t3_dim_date
  WAREHOUSE = CRM_WH
  AFTER orchestration.t2_staging
AS
  EXECUTE IMMEDIATE FROM @orchestration.sql_repo/03_dim_date.snowflake.sql;

CREATE OR REPLACE TASK orchestration.t3_dimensions
  WAREHOUSE = CRM_WH
  AFTER orchestration.t2_staging
AS
  EXECUTE IMMEDIATE FROM @orchestration.sql_repo/04_dimensions.sql;

CREATE OR REPLACE TASK orchestration.t4_facts
  WAREHOUSE = CRM_WH
  AFTER orchestration.t3_dim_date, orchestration.t3_dimensions
AS
  EXECUTE IMMEDIATE FROM @orchestration.sql_repo/05_facts.sql;

CREATE OR REPLACE TASK orchestration.t5_reporting_views
  WAREHOUSE = CRM_WH
  AFTER orchestration.t4_facts
AS
  EXECUTE IMMEDIATE FROM @orchestration.sql_repo/06_reporting_views.sql;

CREATE OR REPLACE TASK orchestration.t6_data_quality
  WAREHOUSE = CRM_WH
  AFTER orchestration.t5_reporting_views
AS
  EXECUTE IMMEDIATE
  $$
  DECLARE
    failed_checks INTEGER DEFAULT 0;
    dq_failed EXCEPTION (-20001, 'Data quality checks failed - see orchestration.dq_results');
  BEGIN
    INSERT INTO orchestration.dq_results (run_at, check_name, severity, failed_rows)
      SELECT CURRENT_TIMESTAMP(), check_name, severity, failed_rows
      FROM orchestration.vw_data_quality;
    SELECT COUNT(*) INTO :failed_checks
      FROM orchestration.vw_data_quality
      WHERE severity = 'error' AND failed_rows > 0;
    IF (failed_checks > 0) THEN
      RAISE dq_failed;
    END IF;
    RETURN 'All error-level data quality checks passed';
  END;
  $$;
