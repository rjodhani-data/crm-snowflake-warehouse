-- =====================================================================
-- 07_data_quality: one query, one row per check.
-- severity = 'error' fails the pipeline; 'warn' is reported only.
-- (Known dirty rows in the sample data are expected to show up as warns.)
-- =====================================================================

SELECT 'stg_accounts: duplicate account_id' AS check_name, 'error' AS severity,
       COUNT(*) - COUNT(DISTINCT account_id) AS failed_rows
FROM staging.stg_accounts
UNION ALL
SELECT 'stg_opportunities: duplicate opportunity_id', 'error',
       COUNT(*) - COUNT(DISTINCT opportunity_id)
FROM staging.stg_opportunities
UNION ALL
SELECT 'opportunities: orphan account_id', 'error', COUNT(*)
FROM staging.stg_opportunities o
LEFT JOIN staging.stg_accounts a ON a.account_id = o.account_id
WHERE a.account_id IS NULL
UNION ALL
SELECT 'quote_lines: orphan product_id', 'error', COUNT(*)
FROM staging.stg_quote_lines q
LEFT JOIN staging.stg_products p ON p.product_id = q.product_id
WHERE p.product_id IS NULL
UNION ALL
SELECT 'fact_opportunity: missing FX rate', 'error', COUNT(*)
FROM marts.fact_opportunity WHERE fx_rate_to_usd IS NULL
UNION ALL
SELECT 'fact_opportunity: null or negative amount', 'error', COUNT(*)
FROM marts.fact_opportunity WHERE amount_local IS NULL OR amount_local < 0
UNION ALL
SELECT 'fact_opportunity: close date unknown in dim_date', 'error', COUNT(*)
FROM marts.fact_opportunity f
LEFT JOIN marts.dim_date d ON d.date_key = f.close_date_key
WHERE d.date_key IS NULL
UNION ALL
SELECT 'fact_contract: end_date before start_date', 'error', COUNT(*)
FROM marts.fact_contract WHERE end_date < start_date
UNION ALL
SELECT 'quote_lines: non-positive quantity (excluded from fact)', 'warn', COUNT(*)
FROM staging.stg_quote_lines WHERE quantity <= 0
UNION ALL
SELECT 'accounts: industry unknown', 'warn', COUNT(*)
FROM staging.stg_accounts WHERE industry = 'Unknown'
UNION ALL
SELECT 'raw duplicates removed (accounts + opportunities)', 'warn',
       (SELECT COUNT(*) FROM raw.accounts) - (SELECT COUNT(*) FROM staging.stg_accounts)
     + (SELECT COUNT(*) FROM raw.opportunities) - (SELECT COUNT(*) FROM staging.stg_opportunities)
UNION ALL
-- Reconciliation: opportunity amount should equal the sum of its valid lines
SELECT 'reconciliation: opportunity amount vs quote lines (> 1 unit diff)', 'warn', COUNT(*)
FROM (
    SELECT o.opportunity_id, o.amount_local,
           SUM(q.quantity * q.unit_price_local * (1 - q.discount_pct / 100)) AS lines_total
    FROM staging.stg_opportunities o
    JOIN staging.stg_quote_lines q ON q.opportunity_id = o.opportunity_id
    GROUP BY o.opportunity_id, o.amount_local
) r
WHERE ABS(r.amount_local - r.lines_total) > 1;
