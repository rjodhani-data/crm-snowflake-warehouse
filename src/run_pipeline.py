"""End-to-end ELT runner: extract -> load raw -> transform -> data quality.

Targets
-------
snowflake : loads CSVs to an internal stage with PUT + COPY INTO, then runs
            the SQL models in Snowflake. Needs a .env (see .env.example).
duckdb    : runs the same SQL models locally in a DuckDB file. Used for
            development and CI, no cloud account needed.

Usage:
    python src/run_pipeline.py --target duckdb
    python src/run_pipeline.py --target snowflake
    python src/run_pipeline.py --target snowflake --skip-extract
"""
from __future__ import annotations

import argparse
import os
import sys
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from extract_fx_rates import extract as extract_fx  # noqa: E402
from generate_crm_data import generate  # noqa: E402

RAW_DIR = ROOT / "data" / "raw"
SQL_DIR = ROOT / "sql"
TABLES = ["accounts", "products", "opportunities", "quote_lines", "contracts", "fx_rates"]
MODEL_STEPS = ["00_setup", "01_raw_tables", None, "02_staging", "03_dim_date",
               "04_dimensions", "05_facts", "06_reporting_views"]  # None = load raw


def sql_file(step: str, target: str) -> Path:
    """Prefer a dialect-specific file (03_dim_date.snowflake.sql) over the shared one."""
    specific = SQL_DIR / f"{step}.{target}.sql"
    return specific if specific.exists() else SQL_DIR / f"{step}.sql"


# --------------------------------------------------------------------------
# Targets
# --------------------------------------------------------------------------
class DuckDBTarget:
    name = "duckdb"

    def __init__(self, path: Path):
        import duckdb
        self.con = duckdb.connect(str(path))

    def run_sql(self, sql: str) -> None:
        self.con.execute(sql)

    def query(self, sql: str) -> list[tuple]:
        return self.con.execute(sql).fetchall()

    def load_csv(self, table: str, csv_path: Path) -> int:
        self.con.execute(f"TRUNCATE TABLE raw.{table}")
        self.con.execute(
            f"INSERT INTO raw.{table} BY NAME "
            f"SELECT * FROM read_csv(?, header = true, all_varchar = true)",
            [str(csv_path)],
        )
        return self.con.execute(f"SELECT COUNT(*) FROM raw.{table}").fetchone()[0]


class SnowflakeTarget:
    name = "snowflake"

    def __init__(self):
        import snowflake.connector
        from dotenv import load_dotenv
        load_dotenv(ROOT / ".env")
        self.con = snowflake.connector.connect(
            account=os.environ["SNOWFLAKE_ACCOUNT"],
            user=os.environ["SNOWFLAKE_USER"],
            password=os.environ["SNOWFLAKE_PASSWORD"],
            role=os.getenv("SNOWFLAKE_ROLE", "SYSADMIN"),
            warehouse=os.getenv("SNOWFLAKE_WAREHOUSE", "CRM_WH"),
        )

    def run_sql(self, sql: str) -> None:
        # execute_string handles files with many statements
        self.con.execute_string(sql, remove_comments=True)
        self.con.cursor().execute("USE DATABASE CRM_DW")

    def query(self, sql: str) -> list[tuple]:
        return self.con.cursor().execute(sql).fetchall()

    def load_csv(self, table: str, csv_path: Path) -> int:
        cur = self.con.cursor()
        cur.execute(f"TRUNCATE TABLE raw.{table}")
        cur.execute(f"PUT 'file://{csv_path.as_posix()}' @raw.landing/{table}/ "
                    f"AUTO_COMPRESS = TRUE OVERWRITE = TRUE")
        cur.execute(
            f"COPY INTO raw.{table} FROM @raw.landing/{table}/ "
            f"FILE_FORMAT = (FORMAT_NAME = raw.csv_ff) "
            f"MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE "
            f"ON_ERROR = ABORT_STATEMENT FORCE = TRUE"
        )
        # COPY leaves columns missing from the file NULL; stamp the load time
        cur.execute(f"UPDATE raw.{table} SET _loaded_at = CURRENT_TIMESTAMP "
                    f"WHERE _loaded_at IS NULL")
        return cur.execute(f"SELECT COUNT(*) FROM raw.{table}").fetchone()[0]


# --------------------------------------------------------------------------
def run_quality_checks(target) -> bool:
    rows = target.query(sql_file("07_data_quality", target.name).read_text())
    print("\nData quality checks")
    print("-" * 78)
    ok = True
    for check, severity, failed in rows:
        status = "PASS" if failed == 0 else ("FAIL" if severity == "error" else "WARN")
        ok &= status != "FAIL"
        print(f"  [{status}] {check:62s} {failed:>6}")
    return ok


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--target", choices=["duckdb", "snowflake"], default="duckdb")
    p.add_argument("--duckdb-path", default=str(ROOT / "data" / "crm_dw.duckdb"))
    p.add_argument("--skip-extract", action="store_true",
                   help="reuse CSVs already in data/raw")
    args = p.parse_args(argv)

    # 1. Extract
    if not args.skip_extract or not (RAW_DIR / "accounts.csv").exists():
        print("Extract")
        for name, n in generate(RAW_DIR).items():
            print(f"  {name:15s} {n:6d} rows")
        n, src = extract_fx(RAW_DIR / "fx_rates.csv", date(2024, 1, 1), date.today())
        print(f"  {'fx_rates':15s} {n:6d} rows (source: {src})")

    target = DuckDBTarget(Path(args.duckdb_path)) if args.target == "duckdb" else SnowflakeTarget()
    print(f"\nTarget: {target.name}")

    # 2. Load + 3. Transform
    for step in MODEL_STEPS:
        if step is None:
            print("  load raw")
            for t in TABLES:
                n = target.load_csv(t, RAW_DIR / f"{t}.csv")
                print(f"    raw.{t:14s} {n:6d} rows")
            continue
        f = sql_file(step, target.name)
        print(f"  run {f.name}")
        target.run_sql(f.read_text())

    # 4. Summary + data quality
    print("\nMarts")
    for t in ["dim_date", "dim_account", "dim_product", "dim_sales_rep",
              "fact_opportunity", "fact_quote_line", "fact_contract"]:
        n = target.query(f"SELECT COUNT(*) FROM marts.{t}")[0][0]
        print(f"  marts.{t:18s} {n:6d} rows")

    ok = run_quality_checks(target)
    target.con.close()
    print("\nPipeline", "succeeded" if ok else "FAILED (see errors above)")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
