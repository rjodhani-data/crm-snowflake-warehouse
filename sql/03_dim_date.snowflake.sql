-- 03_dim_date (Snowflake): calendar dimension 2023-01-01 .. 2028-12-31
CREATE OR REPLACE TABLE marts.dim_date AS
WITH spine AS (
    SELECT DATEADD(day, ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1, '2023-01-01'::DATE) AS date_day
    FROM TABLE(GENERATOR(ROWCOUNT => 2192))
)
SELECT
    TO_NUMBER(TO_CHAR(date_day, 'YYYYMMDD'))  AS date_key,
    date_day,
    YEAR(date_day)                            AS year,
    QUARTER(date_day)                         AS quarter,
    'Q' || QUARTER(date_day)                  AS quarter_label,
    MONTH(date_day)                           AS month,
    MONTHNAME(date_day)                       AS month_name,
    TO_CHAR(date_day, 'YYYY-MM')              AS year_month,
    DAYOFWEEKISO(date_day)                    AS iso_day_of_week,
    DAYOFWEEKISO(date_day) IN (6, 7)          AS is_weekend
FROM spine;
