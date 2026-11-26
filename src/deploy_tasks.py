"""Deploy the Snowflake Tasks DAG and (optionally) run it once.

Steps
-----
1. Upload the source extracts to the landing stage (unless --skip-data).
2. Upload the SQL model files to the orchestration.sql_repo stage.
3. Create the data-quality view and the task DAG (sql/08_tasks.snowflake.sql).
4. With --run: trigger the DAG, wait for every task, print each task's
   result, then suspend the daily schedule again (unless --keep-schedule)
   so the trial does not spend credits every day.

Usage:
    python src/deploy_tasks.py --run
    python src/deploy_tasks.py --run --keep-schedule
"""
from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from run_pipeline import RAW_DIR, SQL_DIR, TABLES, SnowflakeTarget, sql_file  # noqa: E402

TASKS = ["T1_LOAD_RAW", "T2_STAGING", "T3_DIM_DATE", "T3_DIMENSIONS",
         "T4_FACTS", "T5_REPORTING_VIEWS", "T6_DATA_QUALITY"]
ROOT_TASK = "orchestration.t1_load_raw"
TERMINAL = {"SUCCEEDED", "FAILED", "CANCELLED", "SKIPPED", "FAILED_AND_AUTO_SUSPENDED"}


def grant_execute_task(sf: SnowflakeTarget) -> None:
    """Task owners need EXECUTE TASK, which only ACCOUNTADMIN can grant."""
    cur = sf.con.cursor()
    role = cur.execute("SELECT CURRENT_ROLE()").fetchone()[0]
    try:
        cur.execute("USE ROLE ACCOUNTADMIN")
        cur.execute(f"GRANT EXECUTE TASK ON ACCOUNT TO ROLE {role}")
        print(f"  granted EXECUTE TASK to {role}")
    except Exception as exc:
        print(f"  could not grant EXECUTE TASK automatically ({exc.__class__.__name__}).")
        print(f"  In Snowsight, as ACCOUNTADMIN, run: GRANT EXECUTE TASK ON ACCOUNT TO ROLE {role};")
    finally:
        cur.execute(f"USE ROLE {role}")
        cur.execute("USE DATABASE CRM_DW")


def wait_for_run(sf: SnowflakeTarget, started_at, timeout_s: int = 900) -> dict[str, tuple]:
    sql = f"""
        SELECT name, state, error_message
        FROM TABLE(CRM_DW.INFORMATION_SCHEMA.TASK_HISTORY(
            SCHEDULED_TIME_RANGE_START => TO_TIMESTAMP_LTZ({int(started_at.timestamp())}),
            RESULT_LIMIT => 1000))
        WHERE database_name = 'CRM_DW' AND schema_name = 'ORCHESTRATION'
        ORDER BY scheduled_time
    """
    deadline = time.time() + timeout_s
    latest: dict[str, tuple] = {}

    def refresh() -> None:
        for name, state, err in sf.query(sql):
            # Resuming the DAG also queues tomorrow's scheduled run of the
            # root task; never let that future entry hide a finished result
            if name in latest and latest[name][0] in TERMINAL and state not in TERMINAL:
                continue
            latest[name] = (state, err)

    while time.time() < deadline:
        refresh()
        failed = [n for n, (s, _) in latest.items() if s in TERMINAL - {"SUCCEEDED"}]
        done = latest.get("T6_DATA_QUALITY", ("",))[0] in TERMINAL
        if done or failed:
            # give the history a moment to record siblings still finishing
            time.sleep(5)
            refresh()
            return latest
        running = ", ".join(f"{n.lower()}={s.lower()}" for n, (s, _) in latest.items())
        print(f"  ... {running or 'waiting for first task'}")
        time.sleep(10)
    print("  timed out waiting for the DAG; check Snowsight > Monitoring > Task History")
    return latest


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--run", action="store_true", help="trigger the DAG once and wait for it")
    p.add_argument("--keep-schedule", action="store_true",
                   help="leave the daily 07:00 IST schedule switched on")
    p.add_argument("--skip-data", action="store_true",
                   help="do not re-upload the CSV extracts")
    args = p.parse_args(argv)

    sf = SnowflakeTarget()
    print("Setup")
    sf.run_sql(sql_file("00_setup", "snowflake").read_text())
    sf.run_sql(sql_file("01_raw_tables", "snowflake").read_text())
    grant_execute_task(sf)

    if not args.skip_data:
        print("Upload extracts to @raw.landing")
        for t in TABLES:
            sf.upload(RAW_DIR / f"{t}.csv", f"raw.landing/{t}/")
            print(f"  {t}.csv")

    print("Upload SQL files to @orchestration.sql_repo")
    for f in sorted(SQL_DIR.glob("*.sql")):
        if f.name.endswith(".duckdb.sql"):
            continue
        sf.upload(f, "orchestration.sql_repo/", compress=False)
        print(f"  {f.name}")

    print("Create data quality view and task DAG")
    dq_sql = sql_file("07_data_quality", "snowflake").read_text().strip().rstrip(";")
    sf.query("CREATE OR REPLACE VIEW orchestration.vw_data_quality AS\n" + dq_sql)
    sf.run_sql(sql_file("08_tasks", "snowflake").read_text())
    print("  " + ", ".join(t.lower() for t in TASKS))

    if not args.run:
        print("\nDeployed. Run it with: python src/deploy_tasks.py --run --skip-data")
        sf.con.close()
        return 0

    print("\nRun DAG")
    # Resume the root and every dependent task, then trigger the root now
    sf.query(f"SELECT SYSTEM$TASK_DEPENDENTS_ENABLE('{ROOT_TASK}')")
    started_at = sf.query("SELECT DATEADD('second', -30, CURRENT_TIMESTAMP())")[0][0]
    sf.query(f"EXECUTE TASK {ROOT_TASK}")
    results = wait_for_run(sf, started_at)

    if not args.keep_schedule:
        sf.query(f"ALTER TASK {ROOT_TASK} SUSPEND")

    print("\nTask results")
    ok = True
    for t in TASKS:
        state, err = results.get(t, ("NOT RUN", None))
        ok &= state == "SUCCEEDED"
        print(f"  [{state:9s}] {t.lower()}" + (f"  -> {err}" if err else ""))

    print("\nLatest data quality log (orchestration.dq_results)")
    for check, severity, failed in sf.query("""
        SELECT check_name, severity, failed_rows FROM orchestration.dq_results
        WHERE run_at = (SELECT MAX(run_at) FROM orchestration.dq_results)
        ORDER BY severity, check_name"""):
        print(f"  {severity:5s} {check:62s} {failed:>6}")

    print("\nSchedule:", "left ON (daily 07:00 IST)" if args.keep_schedule
          else "suspended (run again with --run, or add --keep-schedule)")
    print("DAG", "succeeded" if ok else "FAILED")
    sf.con.close()
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
