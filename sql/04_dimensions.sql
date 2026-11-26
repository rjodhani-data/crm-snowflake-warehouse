-- =====================================================================
-- 04_dimensions: conformed dimensions with hashed surrogate keys.
-- Surrogate keys are MD5 of the business key, so facts can be built
-- independently of the dimension load order.
-- =====================================================================

CREATE OR REPLACE TABLE marts.dim_account AS
SELECT
    MD5(account_id)                 AS account_key,
    account_id,
    account_name,
    industry,
    billing_country,
    segment,
    annual_revenue_usd,
    number_of_employees,
    CASE
        WHEN number_of_employees < 200   THEN '1-199'
        WHEN number_of_employees < 1000  THEN '200-999'
        WHEN number_of_employees < 10000 THEN '1000-9999'
        ELSE '10000+'
    END                             AS employee_band,
    CAST(created_at AS DATE)        AS account_created_date,
    CURRENT_TIMESTAMP               AS _built_at
FROM staging.stg_accounts;

CREATE OR REPLACE TABLE marts.dim_product AS
SELECT
    MD5(product_id)                 AS product_key,
    product_id,
    product_code,
    product_name,
    product_family,
    list_price_usd,
    is_active,
    CURRENT_TIMESTAMP               AS _built_at
FROM staging.stg_products;

CREATE OR REPLACE TABLE marts.dim_sales_rep AS
SELECT
    MD5(owner_name)                 AS sales_rep_key,
    owner_name                      AS sales_rep_name,
    CURRENT_TIMESTAMP               AS _built_at
FROM (SELECT DISTINCT owner_name FROM staging.stg_opportunities WHERE owner_name IS NOT NULL) reps;
