-- =====================================================================
-- 06_reporting_views: business-ready views that Power BI / Tableau
-- connect to. Keeps report logic in the warehouse, not in each report.
-- =====================================================================

-- Pipeline and bookings by month, stage and product family
CREATE OR REPLACE VIEW marts.vw_bookings_by_month AS
SELECT
    d.year_month,
    d.year,
    d.quarter_label,
    p.product_family,
    a.segment,
    a.billing_country,
    ROUND(SUM(CASE WHEN f.is_won THEN f.net_amount_usd ELSE 0 END), 2) AS bookings_usd,
    ROUND(SUM(CASE WHEN f.is_won THEN f.discount_amount_usd ELSE 0 END), 2) AS discount_given_usd,
    COUNT(DISTINCT CASE WHEN f.is_won THEN f.opportunity_key END) AS won_deals
FROM marts.fact_quote_line f
JOIN marts.dim_date d    ON d.date_key = f.close_date_key
JOIN marts.dim_product p ON p.product_key = f.product_key
JOIN marts.dim_account a ON a.account_key = f.account_key
GROUP BY d.year_month, d.year, d.quarter_label, p.product_family, a.segment, a.billing_country;

-- Win rate and sales cycle by rep (closed opportunities only)
CREATE OR REPLACE VIEW marts.vw_rep_performance AS
SELECT
    r.sales_rep_name,
    COUNT(*)                                                     AS closed_deals,
    SUM(CASE WHEN f.is_won THEN 1 ELSE 0 END)                    AS won_deals,
    ROUND(100.0 * SUM(CASE WHEN f.is_won THEN 1 ELSE 0 END) / COUNT(*), 1) AS win_rate_pct,
    ROUND(AVG(f.days_to_close), 1)                               AS avg_days_to_close,
    ROUND(SUM(CASE WHEN f.is_won THEN f.amount_usd ELSE 0 END), 2) AS won_amount_usd
FROM marts.fact_opportunity f
JOIN marts.dim_sales_rep r ON r.sales_rep_key = f.sales_rep_key
WHERE f.is_closed
GROUP BY r.sales_rep_name;

-- Open pipeline by stage
CREATE OR REPLACE VIEW marts.vw_open_pipeline AS
SELECT
    f.stage_name,
    a.segment,
    COUNT(*)              AS open_deals,
    ROUND(SUM(f.amount_usd), 2) AS pipeline_usd
FROM marts.fact_opportunity f
JOIN marts.dim_account a ON a.account_key = f.account_key
WHERE NOT f.is_closed
GROUP BY f.stage_name, a.segment;

-- Contracts up for renewal in the next 90 days
CREATE OR REPLACE VIEW marts.vw_upcoming_renewals AS
SELECT
    a.account_name,
    a.segment,
    a.billing_country,
    c.contract_id,
    c.end_date,
    c.end_date - CURRENT_DATE  AS days_to_renewal,
    c.auto_renew,
    c.annual_contract_value_usd
FROM marts.fact_contract c
JOIN marts.dim_account a ON a.account_key = c.account_key
WHERE c.status = 'Activated'
  AND c.end_date BETWEEN CURRENT_DATE AND CURRENT_DATE + 90;
