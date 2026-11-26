-- =====================================================================
-- 02_staging: typed, cleaned, de-duplicated views over raw.
-- Duplicates (re-sent records) are resolved by keeping the latest
-- last_modified_date per business key.
-- =====================================================================

CREATE OR REPLACE VIEW staging.stg_accounts AS
SELECT
    TRIM(account_id)                                   AS account_id,
    TRIM(account_name)                                 AS account_name,
    COALESCE(NULLIF(TRIM(industry), ''), 'Unknown')    AS industry,
    TRIM(billing_country)                              AS billing_country,
    TRIM(segment)                                      AS segment,
    TRY_CAST(annual_revenue_usd AS DECIMAL(18, 2))     AS annual_revenue_usd,
    TRY_CAST(number_of_employees AS INTEGER)           AS number_of_employees,
    TRY_CAST(created_date AS TIMESTAMP)                AS created_at,
    TRY_CAST(last_modified_date AS TIMESTAMP)          AS last_modified_at
FROM raw.accounts
WHERE account_id IS NOT NULL
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY TRIM(account_id)
    ORDER BY TRY_CAST(last_modified_date AS TIMESTAMP) DESC
) = 1;

CREATE OR REPLACE VIEW staging.stg_products AS
SELECT
    TRIM(product_id)                                   AS product_id,
    TRIM(product_code)                                 AS product_code,
    TRIM(product_name)                                 AS product_name,
    TRIM(product_family)                               AS product_family,
    TRY_CAST(list_price_usd AS DECIMAL(18, 2))         AS list_price_usd,
    LOWER(TRIM(is_active)) = 'true'                    AS is_active
FROM raw.products
WHERE product_id IS NOT NULL
QUALIFY ROW_NUMBER() OVER (PARTITION BY TRIM(product_id) ORDER BY _loaded_at DESC) = 1;

CREATE OR REPLACE VIEW staging.stg_opportunities AS
SELECT
    TRIM(opportunity_id)                               AS opportunity_id,
    TRIM(account_id)                                   AS account_id,
    TRIM(opportunity_name)                             AS opportunity_name,
    TRIM(stage_name)                                   AS stage_name,
    TRY_CAST(amount AS DECIMAL(18, 2))                 AS amount_local,
    UPPER(TRIM(currency_iso_code))                     AS currency_code,
    TRIM(lead_source)                                  AS lead_source,
    TRIM(owner_name)                                   AS owner_name,
    TRY_CAST(TRY_CAST(created_date AS TIMESTAMP) AS DATE) AS created_date,
    TRY_CAST(close_date AS DATE)                       AS close_date,
    LOWER(TRIM(is_closed)) = 'true'                    AS is_closed,
    LOWER(TRIM(is_won)) = 'true'                       AS is_won,
    TRY_CAST(last_modified_date AS TIMESTAMP)          AS last_modified_at
FROM raw.opportunities
WHERE opportunity_id IS NOT NULL
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY TRIM(opportunity_id)
    ORDER BY TRY_CAST(last_modified_date AS TIMESTAMP) DESC
) = 1;

CREATE OR REPLACE VIEW staging.stg_quote_lines AS
SELECT
    TRIM(quote_line_id)                                AS quote_line_id,
    TRIM(opportunity_id)                               AS opportunity_id,
    TRIM(product_id)                                   AS product_id,
    TRY_CAST(quantity AS INTEGER)                      AS quantity,
    TRY_CAST(unit_price AS DECIMAL(18, 2))             AS unit_price_local,
    TRY_CAST(discount_pct AS DECIMAL(5, 2))            AS discount_pct,
    UPPER(TRIM(currency_iso_code))                     AS currency_code
FROM raw.quote_lines
WHERE quote_line_id IS NOT NULL
QUALIFY ROW_NUMBER() OVER (PARTITION BY TRIM(quote_line_id) ORDER BY _loaded_at DESC) = 1;

CREATE OR REPLACE VIEW staging.stg_contracts AS
SELECT
    TRIM(contract_id)                                  AS contract_id,
    TRIM(account_id)                                   AS account_id,
    TRIM(opportunity_id)                               AS opportunity_id,
    TRIM(status)                                       AS status,
    TRY_CAST(start_date AS DATE)                       AS start_date,
    TRY_CAST(end_date AS DATE)                         AS end_date,
    TRY_CAST(contract_term_months AS INTEGER)          AS term_months,
    TRY_CAST(contract_value AS DECIMAL(18, 2))         AS contract_value_local,
    UPPER(TRIM(currency_iso_code))                     AS currency_code,
    LOWER(TRIM(auto_renew)) = 'true'                   AS auto_renew
FROM raw.contracts
WHERE contract_id IS NOT NULL
QUALIFY ROW_NUMBER() OVER (PARTITION BY TRIM(contract_id) ORDER BY _loaded_at DESC) = 1;

-- One row per day per currency, USD included at rate 1.0
-- rate = units of quote currency per 1 USD, so amount_usd = amount_local / rate
CREATE OR REPLACE VIEW staging.stg_fx_rates AS
WITH typed AS (
    SELECT
        TRY_CAST(rate_date AS DATE)           AS rate_date,
        UPPER(TRIM(quote_currency))           AS currency_code,
        TRY_CAST(rate AS DECIMAL(18, 6))      AS rate,
        TRIM(source)                          AS source
    FROM raw.fx_rates
)
SELECT rate_date, currency_code, rate, source FROM typed
UNION ALL
SELECT DISTINCT rate_date, 'USD', CAST(1 AS DECIMAL(18, 6)), source FROM typed;
