-- =====================================================================
-- 01_raw_tables: landing tables. Everything is VARCHAR so a bad value
-- never fails the load; typing and validation happen in staging.
-- =====================================================================

CREATE TABLE IF NOT EXISTS raw.accounts (
    account_id            VARCHAR,
    account_name          VARCHAR,
    industry              VARCHAR,
    billing_country       VARCHAR,
    segment               VARCHAR,
    annual_revenue_usd    VARCHAR,
    number_of_employees   VARCHAR,
    created_date          VARCHAR,
    last_modified_date    VARCHAR,
    _loaded_at            TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS raw.products (
    product_id            VARCHAR,
    product_code          VARCHAR,
    product_name          VARCHAR,
    product_family        VARCHAR,
    list_price_usd        VARCHAR,
    is_active             VARCHAR,
    _loaded_at            TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS raw.opportunities (
    opportunity_id        VARCHAR,
    account_id            VARCHAR,
    opportunity_name      VARCHAR,
    stage_name            VARCHAR,
    amount                VARCHAR,
    currency_iso_code     VARCHAR,
    lead_source           VARCHAR,
    owner_name            VARCHAR,
    created_date          VARCHAR,
    close_date            VARCHAR,
    is_closed             VARCHAR,
    is_won                VARCHAR,
    last_modified_date    VARCHAR,
    _loaded_at            TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS raw.quote_lines (
    quote_line_id         VARCHAR,
    opportunity_id        VARCHAR,
    product_id            VARCHAR,
    quantity              VARCHAR,
    unit_price            VARCHAR,
    discount_pct          VARCHAR,
    currency_iso_code     VARCHAR,
    _loaded_at            TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS raw.contracts (
    contract_id           VARCHAR,
    account_id            VARCHAR,
    opportunity_id        VARCHAR,
    status                VARCHAR,
    start_date            VARCHAR,
    end_date              VARCHAR,
    contract_term_months  VARCHAR,
    contract_value        VARCHAR,
    currency_iso_code     VARCHAR,
    auto_renew            VARCHAR,
    _loaded_at            TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS raw.fx_rates (
    rate_date             VARCHAR,
    base_currency         VARCHAR,
    quote_currency        VARCHAR,
    rate                  VARCHAR,
    is_filled             VARCHAR,
    source                VARCHAR,
    _loaded_at            TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
