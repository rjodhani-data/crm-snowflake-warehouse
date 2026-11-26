"""Extract daily FX rates from the free Frankfurter API (ECB reference rates).

This is the API step of the ELT pipeline: deal amounts arrive in local
currency (USD, EUR, GBP, INR) and are converted to USD in the warehouse
using the rate for each deal's close date.

The API only publishes rates on ECB working days, so weekends and holidays
are forward-filled to give one row per calendar day.

If the API cannot be reached (offline, CI), the script falls back to a
deterministic sample series and marks those rows source='sample'.

Usage:
    python src/extract_fx_rates.py --start 2024-01-01 --end 2026-12-31
"""
from __future__ import annotations

import argparse
import csv
import json
import math
import urllib.request
from datetime import date, timedelta
from pathlib import Path

API_URL = "https://api.frankfurter.dev/v1/{start}..{end}?base=USD&symbols=EUR,GBP,INR"
CURRENCIES = ["EUR", "GBP", "INR"]


def fetch_from_api(start: date, end: date, timeout: int = 20) -> dict[str, dict[str, float]]:
    url = API_URL.format(start=start.isoformat(), end=end.isoformat())
    req = urllib.request.Request(url, headers={"User-Agent": "crm-snowflake-warehouse"})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        payload = json.load(resp)
    return payload["rates"]  # {"2024-01-02": {"EUR": 0.91, ...}, ...}


def sample_rates(start: date, end: date) -> dict[str, dict[str, float]]:
    """Deterministic, realistic-looking rates for offline runs."""
    base = {"EUR": 0.92, "GBP": 0.79, "INR": 83.5}
    out, d, i = {}, start, 0
    while d <= end:
        if d.weekday() < 5:
            out[d.isoformat()] = {
                c: round(v * (1 + 0.03 * math.sin(i / 45 + n)), 4)
                for n, (c, v) in enumerate(base.items())
            }
        d += timedelta(days=1)
        i += 1
    return out


def forward_fill(rates: dict[str, dict[str, float]], start: date, end: date) -> list[dict]:
    rows, last, d = [], None, start
    while d <= end:
        key = d.isoformat()
        if key in rates:
            last = rates[key]
        if last is not None:
            for c in CURRENCIES:
                rows.append({"rate_date": key, "base_currency": "USD",
                             "quote_currency": c, "rate": last[c],
                             "is_filled": "false" if key in rates else "true"})
        d += timedelta(days=1)
    return rows


def extract(out_file: Path, start: date, end: date) -> tuple[int, str]:
    try:
        rates = fetch_from_api(start, end)
        source = "frankfurter_api"
    except Exception as exc:  # network blocked, API down, etc.
        print(f"FX API unavailable ({exc.__class__.__name__}); using sample rates")
        rates = sample_rates(start, end)
        source = "sample"
    # Make sure the first day has a value to forward-fill from
    first = min(rates)
    rows = forward_fill(rates, min(start, date.fromisoformat(first)), end)
    rows = [r | {"source": source} for r in rows if r["rate_date"] >= start.isoformat()]
    out_file.parent.mkdir(parents=True, exist_ok=True)
    with out_file.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)
    return len(rows), source


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--start", default="2024-01-01")
    p.add_argument("--end", default="2026-12-31")
    p.add_argument("--out", default="data/raw/fx_rates.csv")
    a = p.parse_args()
    end = min(date.fromisoformat(a.end), date.today())
    n, src = extract(Path(a.out), date.fromisoformat(a.start), end)
    print(f"fx_rates        {n:6d} rows (source: {src})")
