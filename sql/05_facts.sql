-- =====================================================================
-- 05_facts: fact tables at explicit grains, amounts converted to USD.
-- FX rate = rate on the business date (close / start date). For future
-- dates (open pipeline) the latest available rate is used.
-- Date keys are integers in YYYYMMDD form, joining to marts.dim_date.
-- =====================================================================

-- Grain: one row per opportunity
CREATE OR REPLACE TABLE marts.fact_opportunity AS
WITH fx_bounds AS (
    SELECT MAX(rate_date) AS max_rate_date FROM staging.stg_fx_rates
),
lines AS (
    SELECT opportunity_id, COUNT(*) AS line_count, SUM(quantity) AS total_quantity
    FROM staging.stg_quote_lines
    GROUP BY opportunity_id
)
SELECT
    MD5(o.opportunity_id)                                          AS opportunity_key,
    o.opportunity_id,
    MD5(o.account_id)                                              AS account_key,
    MD5(o.owner_name)                                              AS sales_rep_key,
    YEAR(o.created_date) * 10000 + MONTH(o.created_date) * 100 + DAY(o.created_date) AS created_date_key,
    YEAR(o.close_date) * 10000 + MONTH(o.close_date) * 100 + DAY(o.close_date)       AS close_date_key,
    o.opportunity_name,
    o.stage_name,
    o.lead_source,
    o.is_closed,
    o.is_won,
    o.currency_code,
    o.amount_local,
    fx.rate                                                        AS fx_rate_to_usd,
    ROUND(o.amount_local / fx.rate, 2)                             AS amount_usd,
    o.close_date - o.created_date                                  AS days_to_close,
    COALESCE(l.line_count, 0)                                      AS line_count,
    COALESCE(l.total_quantity, 0)                                  AS total_quantity,
    CURRENT_TIMESTAMP                                              AS _built_at
FROM staging.stg_opportunities o
CROSS JOIN fx_bounds b
LEFT JOIN staging.stg_fx_rates fx
       ON fx.currency_code = o.currency_code
      AND fx.rate_date = LEAST(o.close_date, b.max_rate_date)
LEFT JOIN lines l
       ON l.opportunity_id = o.opportunity_id;

-- Grain: one row per quote line (product on an opportunity)
CREATE OR REPLACE TABLE marts.fact_quote_line AS
WITH fx_bounds AS (
    SELECT MAX(rate_date) AS max_rate_date FROM staging.stg_fx_rates
)
SELECT
    MD5(q.quote_line_id)                                           AS quote_line_key,
    q.quote_line_id,
    MD5(q.opportunity_id)                                          AS opportunity_key,
    MD5(o.account_id)                                              AS account_key,
    MD5(q.product_id)                                              AS product_key,
    YEAR(o.close_date) * 10000 + MONTH(o.close_date) * 100 + DAY(o.close_date) AS close_date_key,
    o.is_won,
    q.quantity,
    q.unit_price_local,
    q.discount_pct,
    q.currency_code,
    ROUND(q.quantity * q.unit_price_local * (1 - q.discount_pct / 100), 2)            AS net_amount_local,
    ROUND(q.quantity * q.unit_price_local * (1 - q.discount_pct / 100) / fx.rate, 2)  AS net_amount_usd,
    ROUND(q.quantity * q.unit_price_local * (q.discount_pct / 100) / fx.rate, 2)      AS discount_amount_usd,
    CURRENT_TIMESTAMP                                              AS _built_at
FROM staging.stg_quote_lines q
JOIN staging.stg_opportunities o
  ON o.opportunity_id = q.opportunity_id
CROSS JOIN fx_bounds b
LEFT JOIN staging.stg_fx_rates fx
       ON fx.currency_code = q.currency_code
      AND fx.rate_date = LEAST(o.close_date, b.max_rate_date)
WHERE q.quantity > 0;   -- invalid lines are reported by the data quality checks

-- Grain: one row per contract
CREATE OR REPLACE TABLE marts.fact_contract AS
WITH fx_bounds AS (
    SELECT MAX(rate_date) AS max_rate_date FROM staging.stg_fx_rates
)
SELECT
    MD5(c.contract_id)                                             AS contract_key,
    c.contract_id,
    MD5(c.account_id)                                              AS account_key,
    MD5(c.opportunity_id)                                          AS opportunity_key,
    YEAR(c.start_date) * 10000 + MONTH(c.start_date) * 100 + DAY(c.start_date) AS start_date_key,
    YEAR(c.end_date) * 10000 + MONTH(c.end_date) * 100 + DAY(c.end_date)       AS end_date_key,
    c.start_date,
    c.end_date,
    c.status,
    c.term_months,
    c.auto_renew,
    c.currency_code,
    c.contract_value_local,
    ROUND(c.contract_value_local / fx.rate, 2)                     AS contract_value_usd,
    ROUND(c.contract_value_local / fx.rate * 12 / c.term_months, 2) AS annual_contract_value_usd,
    c.status = 'Activated' AND c.end_date >= CURRENT_DATE          AS is_active,
    CURRENT_TIMESTAMP                                              AS _built_at
FROM staging.stg_contracts c
CROSS JOIN fx_bounds b
LEFT JOIN staging.stg_fx_rates fx
       ON fx.currency_code = c.currency_code
      AND fx.rate_date = LEAST(c.start_date, b.max_rate_date);
