# CRM & Contracts Data Warehouse on Snowflake

An ELT pipeline that turns Salesforce-style CRM, CPQ and contract data into a
**Snowflake star schema** for sales and renewals reporting in Power BI / Tableau,
orchestrated inside Snowflake as a scheduled **Snowflake Tasks DAG**.

It covers the full path a data engineering team owns: extracting from files and a
REST API, landing raw data in Snowflake, cleaning and de-duplicating it,
dimensional modelling, currency conversion, reporting views, and automated data
quality checks.

## Tech stack

| Area | Tools |
|---|---|
| Cloud data warehouse | **Snowflake** (warehouse, internal stage, file formats, `COPY INTO`) |
| Orchestration | **Snowflake Tasks** DAG (7 tasks, parallel branches, daily CRON schedule), Snowflake Scripting, `EXECUTE IMMEDIATE FROM` stage |
| Ingestion | **Python** (CSV extracts, REST API client for FX rates), Snowflake Python connector |
| Transformation | **SQL**: CTEs, window functions (`QUALIFY ROW_NUMBER()`), `TRY_CAST` typing, views |
| Modelling | Kimball dimensional model: star schema, MD5 surrogate keys, `YYYYMMDD` date keys |
| Data quality | SQL checks (uniqueness, referential integrity, reconciliation) that fail the run on errors |
| Local dev and testing | **DuckDB** (same SQL models run locally), **pytest** end-to-end test |
| Reporting | BI-ready views for Power BI / Tableau |

## Results

Full run on Snowflake: all six sources loaded, seven mart tables built, every
error-level check passing. The same SQL run locally on DuckDB produces identical
row counts.

| Table | Rows |
|---|---|
| `fact_opportunity` | 3,000 |
| `fact_quote_line` | 7,393 |
| `fact_contract` | 1,053 |
| `dim_account` / `dim_product` / `dim_sales_rep` / `dim_date` | 500 / 15 / 8 / 2,192 |

![Snowflake reporting view](docs/snowflake-rep-performance.png)

## Orchestration: Snowflake Tasks DAG

```mermaid
flowchart TD
    T1[t1_load_raw<br/>daily 07:00 IST] --> T2[t2_staging]
    T2 --> T3a[t3_dim_date]
    T2 --> T3b[t3_dimensions]
    T3a --> T4[t4_facts]
    T3b --> T4
    T4 --> T5[t5_reporting_views]
    T5 --> T6[t6_data_quality]
```

- Each task runs one file from `sql/` directly from a stage with
  `EXECUTE IMMEDIATE FROM`, so the SQL files stay the single source of truth.
- Date and business dimensions build **in parallel**; facts wait for both.
- `t6_data_quality` (Snowflake Scripting) logs every check to
  `orchestration.dq_results` and raises an error if any error-level check fails,
  so a bad load shows up as a failed run in Task History.
- `src/deploy_tasks.py` uploads the files, creates the DAG, triggers a run and
  reports each task's result.

![Snowflake task graph](docs/snowflake-task-dag.png)

## Architecture

```mermaid
flowchart LR
    A[CRM extracts<br/>Account, Product, Opportunity,<br/>Quote Line, Contract CSVs] --> S[(Snowflake stage<br/>raw.landing)]
    B[Frankfurter FX API<br/>daily ECB rates] --> S
    S -->|COPY INTO| R[raw schema<br/>all VARCHAR]
    R --> ST[staging views<br/>typed, trimmed, de-duplicated]
    ST --> M[marts schema<br/>star schema]
    M --> V[reporting views]
    V --> P[Power BI / Tableau]
    M --> Q{data quality<br/>checks}
```

| Layer | What happens |
|---|---|
| **raw** | Files land as-is (every column `VARCHAR`) so a bad value never breaks the load. Loaded with `PUT` + `COPY INTO ... MATCH_BY_COLUMN_NAME`. |
| **staging** | `TRY_CAST` typing, trimming, standardised currency codes, and de-duplication of re-sent records with `QUALIFY ROW_NUMBER()` (latest `last_modified_date` wins). |
| **marts** | Kimball-style star schema with MD5 surrogate keys, integer `YYYYMMDD` date keys and USD conversion using the FX rate on each deal's close date. |
| **reporting views** | Bookings by month and product family, rep win rate and sales cycle, open pipeline, renewals due in 90 days. |

## Data model

```mermaid
erDiagram
    dim_account   ||--o{ fact_opportunity : ""
    dim_sales_rep ||--o{ fact_opportunity : ""
    dim_date      ||--o{ fact_opportunity : "close_date_key"
    dim_account   ||--o{ fact_quote_line  : ""
    dim_product   ||--o{ fact_quote_line  : ""
    dim_date      ||--o{ fact_quote_line  : "close_date_key"
    dim_account   ||--o{ fact_contract    : ""
    dim_date      ||--o{ fact_contract    : "start/end_date_key"
```

| Table | Grain |
|---|---|
| `fact_opportunity` | one row per opportunity (amount in local currency and USD, stage, days to close) |
| `fact_quote_line` | one row per product on an opportunity (quantity, discount, net amount) |
| `fact_contract` | one row per contract (term, status, total and annual contract value) |
| `dim_account`, `dim_product`, `dim_sales_rep`, `dim_date` | conformed dimensions |

## Data quality

`sql/07_data_quality.sql` runs after every build. **Errors** fail the pipeline;
**warnings** are reported:

- duplicate business keys after de-duplication
- orphan foreign keys (opportunity → account, quote line → product)
- missing FX rates, null or negative amounts, unknown dates
- contracts ending before they start
- reconciliation of opportunity amount against the sum of its quote lines

The source data deliberately contains duplicates, whitespace, lowercase currency
codes, missing industries and invalid quantities, so the checks have real issues
to catch.

## Run it

```bash
python -m venv .venv
# Windows: .venv\Scripts\activate    macOS/Linux: source .venv/bin/activate
pip install -r requirements.txt

# Local run (no cloud account): same SQL models on DuckDB
python src/run_pipeline.py --target duckdb

# Snowflake run: copy .env.example to .env and fill in your account
python src/run_pipeline.py --target snowflake

# Deploy the Snowflake Tasks DAG and run it once
python src/deploy_tasks.py --run

# Tests
pytest -q
```

## Project structure

```
src/
  generate_crm_data.py   Salesforce-style source extracts (CSV)
  extract_fx_rates.py    REST API extract with forward-fill for non-trading days
  run_pipeline.py        extract -> load -> transform -> data quality
  deploy_tasks.py        deploy + run the Snowflake Tasks DAG
sql/
  00_setup.*.sql         warehouse, database, schemas, file format, stage
  01_raw_tables.sql      landing tables
  02_staging.sql         typed, cleaned, de-duplicated views
  03_dim_date.*.sql      calendar dimension (Snowflake GENERATOR / DuckDB range)
  04_dimensions.sql      account, product, sales rep
  05_facts.sql           opportunity, quote line, contract facts
  06_reporting_views.sql BI-ready views
  07_data_quality.sql    checks
  load_raw.snowflake.sql COPY INTO from the landing stage
  08_tasks.snowflake.sql Snowflake Tasks DAG
tests/
  test_pipeline.py       end-to-end test on DuckDB
```

## Notes

- Source records are synthetic but follow the standard Salesforce object model
  (Account, Product2, Opportunity, QuoteLineItem, Contract), so the same model
  applies to a real Salesforce extract.
- FX rates come from the free [Frankfurter API](https://frankfurter.dev). If the
  API is unreachable, the pipeline falls back to sample rates and marks them
  `source = 'sample'`.

## Author

**Rajvi Jodhani**: data engineer and analyst, M.Sc. Web and Data Science
(University of Koblenz, Germany). ETL pipelines, SQL data modelling and Power BI /
Tableau reporting.

[LinkedIn](https://linkedin.com/in/rajvi-jodhani) ·
[Portfolio](https://rjodhani-data.github.io) ·
[GitHub](https://github.com/rjodhani-data)
