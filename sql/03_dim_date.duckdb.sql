-- 03_dim_date (DuckDB local mode): same columns as the Snowflake version
CREATE OR REPLACE TABLE marts.dim_date AS
WITH spine AS (
    SELECT CAST(range AS DATE) AS date_day
    FROM range(DATE '2023-01-01', DATE '2029-01-01', INTERVAL 1 DAY)
)
SELECT
    CAST(strftime(date_day, '%Y%m%d') AS INTEGER) AS date_key,
    date_day,
    year(date_day)                                AS year,
    quarter(date_day)                             AS quarter,
    'Q' || quarter(date_day)                      AS quarter_label,
    month(date_day)                               AS month,
    strftime(date_day, '%b')                      AS month_name,
    strftime(date_day, '%Y-%m')                   AS year_month,
    isodow(date_day)                              AS iso_day_of_week,
    isodow(date_day) IN (6, 7)                    AS is_weekend
FROM spine;
