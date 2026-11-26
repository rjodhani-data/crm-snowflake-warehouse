"""Generate Salesforce-style CRM / CPQ / contract data as CSV files.

The objects mirror the standard Salesforce data model (Account, Product2,
Opportunity, QuoteLineItem, Contract) so the warehouse can be modelled the
same way it would be for a real Salesforce source.

Some rows are deliberately "dirty" (duplicates, stray whitespace, mixed-case
currency codes, missing industries) so the staging layer has real cleaning
work to do.

Usage:
    python src/generate_crm_data.py --out data/raw --seed 42
"""
from __future__ import annotations

import argparse
import csv
import random
import string
from datetime import date, datetime, timedelta
from pathlib import Path

START = date(2024, 1, 1)
END = date(2026, 11, 20)

INDUSTRIES = ["Technology", "Healthcare", "Financial Services", "Manufacturing",
              "Retail", "Legal", "Energy", "Telecommunications", "Education"]
COUNTRIES = {"United States": "USD", "United Kingdom": "GBP", "Germany": "EUR",
             "France": "EUR", "India": "INR", "Netherlands": "EUR"}
SEGMENTS = ["SMB", "Mid-Market", "Enterprise"]
LEAD_SOURCES = ["Web", "Partner", "Event", "Outbound", "Referral"]
OWNERS = ["Aarav Shah", "Meera Iyer", "Daniel Brooks", "Sophie Wagner",
          "Rohan Patel", "Emily Clarke", "Lukas Becker", "Ananya Rao"]
STAGES_OPEN = ["Prospecting", "Qualification", "Proposal", "Negotiation"]
PRODUCT_FAMILIES = {
    "Contract Lifecycle Management": (18000, 90000),
    "CPQ": (12000, 70000),
    "Document Generation": (4000, 25000),
    "eSignature": (1500, 12000),
    "Analytics Add-on": (2500, 15000),
}
# Approximate units of local currency per 1 USD, used only to price deals
# in local currency. Reporting conversion uses the FX table instead.
APPROX_FX = {"USD": 1.0, "EUR": 0.92, "GBP": 0.79, "INR": 83.5}


def sf_id(prefix: str, rnd: random.Random) -> str:
    """Salesforce-style 18-char id with a 3-char object prefix."""
    chars = string.ascii_letters + string.digits
    return prefix + "".join(rnd.choice(chars) for _ in range(15))


def rand_date(rnd: random.Random, start: date, end: date) -> date:
    return start + timedelta(days=rnd.randint(0, (end - start).days))


def ts(d: date, rnd: random.Random) -> str:
    return datetime(d.year, d.month, d.day, rnd.randint(7, 20),
                    rnd.randint(0, 59), rnd.randint(0, 59)).isoformat(sep=" ")


def write_csv(path: Path, rows: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)


def generate(out_dir: Path, seed: int = 42, n_accounts: int = 500,
             n_opps: int = 3000) -> dict[str, int]:
    rnd = random.Random(seed)

    # ---- Products --------------------------------------------------------
    products = []
    for family, (lo, hi) in PRODUCT_FAMILIES.items():
        for tier in ["Starter", "Professional", "Enterprise"]:
            products.append({
                "product_id": sf_id("01t", rnd),
                "product_code": f"{''.join(w[0] for w in family.split())}-{tier[:3].upper()}",
                "product_name": f"{family} {tier}",
                "product_family": family,
                "list_price_usd": round(rnd.uniform(lo, hi), 2),
                "is_active": "true" if rnd.random() > 0.05 else "false",
            })

    # ---- Accounts --------------------------------------------------------
    accounts = []
    for i in range(n_accounts):
        country = rnd.choice(list(COUNTRIES))
        created = rand_date(rnd, date(2022, 1, 1), END - timedelta(days=60))
        name = f"{rnd.choice(['Apex','Nova','Blue','Vertex','Lumen','Orion','Summit','Crest','Atlas','Zenith'])} " \
               f"{rnd.choice(['Systems','Health','Capital','Industries','Legal','Retail','Energy','Labs','Group'])} {i:03d}"
        if rnd.random() < 0.05:
            name = f"  {name} "  # stray whitespace, cleaned in staging
        accounts.append({
            "account_id": sf_id("001", rnd),
            "account_name": name,
            "industry": rnd.choice(INDUSTRIES) if rnd.random() > 0.04 else "",
            "billing_country": country,
            "segment": rnd.choice(SEGMENTS),
            "annual_revenue_usd": rnd.randint(2, 5000) * 100000,
            "number_of_employees": rnd.randint(20, 50000),
            "created_date": ts(created, rnd),
            "last_modified_date": ts(rand_date(rnd, created, END), rnd),
        })

    # ---- Opportunities + quote lines --------------------------------------
    opportunities, quote_lines, contracts = [], [], []
    for _ in range(n_opps):
        acct = rnd.choice(accounts)
        currency = COUNTRIES[acct["billing_country"]]
        created = rand_date(rnd, START, END - timedelta(days=5))
        close = created + timedelta(days=rnd.randint(10, 180))
        if close <= END:
            stage = rnd.choices(["Closed Won", "Closed Lost"], weights=[38, 62])[0]
        else:
            stage = rnd.choice(STAGES_OPEN)
        opp_id = sf_id("006", rnd)

        amount = 0.0
        for _ in range(rnd.randint(1, 4)):
            prod = rnd.choice(products)
            qty = rnd.randint(1, 25) if prod["product_family"] == "eSignature" else rnd.randint(1, 3)
            unit_price = round(prod["list_price_usd"] * APPROX_FX[currency], 2)
            discount = rnd.choice([0, 0, 5, 10, 15, 20])
            net = qty * unit_price * (1 - discount / 100)
            amount += net
            quote_lines.append({
                "quote_line_id": sf_id("0QL", rnd),
                "opportunity_id": opp_id,
                "product_id": prod["product_id"],
                "quantity": qty if rnd.random() > 0.003 else -qty,  # rare bad row
                "unit_price": unit_price,
                "discount_pct": discount,
                "currency_iso_code": currency,
            })

        curr_code = currency.lower() if rnd.random() < 0.03 else currency
        opportunities.append({
            "opportunity_id": opp_id,
            "account_id": acct["account_id"],
            "opportunity_name": f"{acct['account_name'].strip()} - {rnd.choice(['New Business','Expansion','Renewal'])}",
            "stage_name": stage,
            "amount": round(amount, 2),
            "currency_iso_code": curr_code,
            "lead_source": rnd.choice(LEAD_SOURCES),
            "owner_name": rnd.choice(OWNERS),
            "created_date": ts(created, rnd),
            "close_date": close.isoformat(),
            "is_closed": "true" if stage.startswith("Closed") else "false",
            "is_won": "true" if stage == "Closed Won" else "false",
            "last_modified_date": ts(min(close, END), rnd),
        })

        if stage == "Closed Won":
            start = close + timedelta(days=rnd.randint(1, 20))
            term = rnd.choice([12, 12, 24, 36])
            end = date(start.year + (start.month - 1 + term) // 12,
                       (start.month - 1 + term) % 12 + 1, 1) - timedelta(days=1)
            status = "Draft" if rnd.random() < 0.04 else ("Expired" if end < END else "Activated")
            contracts.append({
                "contract_id": sf_id("800", rnd),
                "account_id": acct["account_id"],
                "opportunity_id": opp_id,
                "status": status,
                "start_date": start.isoformat(),
                "end_date": end.isoformat(),
                "contract_term_months": term,
                "contract_value": round(amount, 2),
                "currency_iso_code": currency,
                "auto_renew": "true" if rnd.random() < 0.6 else "false",
            })

    # Duplicate a few records with a later modified date (CDC-style re-sends)
    for rows, n in ((accounts, 12), (opportunities, 40)):
        for r in rnd.sample(rows, n):
            dup = dict(r)
            dup["last_modified_date"] = ts(END, rnd)
            rows.append(dup)

    files = {"accounts": accounts, "products": products,
             "opportunities": opportunities, "quote_lines": quote_lines,
             "contracts": contracts}
    for name, rows in files.items():
        write_csv(out_dir / f"{name}.csv", rows)
    return {k: len(v) for k, v in files.items()}


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--out", default="data/raw")
    p.add_argument("--seed", type=int, default=42)
    args = p.parse_args()
    counts = generate(Path(args.out), args.seed)
    for k, v in counts.items():
        print(f"{k:15s} {v:6d} rows")
