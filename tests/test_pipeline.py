"""Runs the full pipeline against a temporary DuckDB file and checks the marts."""
import sys
from pathlib import Path

import duckdb

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))
from run_pipeline import main  # noqa: E402


def test_pipeline_builds_marts_and_passes_quality_checks(tmp_path):
    db = tmp_path / "test.duckdb"
    assert main(["--target", "duckdb", "--duckdb-path", str(db)]) == 0

    con = duckdb.connect(str(db))
    # Duplicates removed: one row per business key
    assert con.execute("SELECT COUNT(*) = COUNT(DISTINCT opportunity_id) FROM marts.fact_opportunity").fetchone()[0]
    assert con.execute("SELECT COUNT(*) = COUNT(DISTINCT account_id) FROM marts.dim_account").fetchone()[0]
    # Every fact row joins to its dimensions
    orphans = con.execute("""
        SELECT COUNT(*) FROM marts.fact_quote_line f
        LEFT JOIN marts.dim_product p ON p.product_key = f.product_key
        LEFT JOIN marts.dim_account a ON a.account_key = f.account_key
        WHERE p.product_key IS NULL OR a.account_key IS NULL
    """).fetchone()[0]
    assert orphans == 0
    # USD conversion applied
    assert con.execute("SELECT COUNT(*) FROM marts.fact_opportunity WHERE amount_usd IS NULL").fetchone()[0] == 0
