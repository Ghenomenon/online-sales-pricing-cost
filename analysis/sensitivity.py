"""Sensitivity check for the pricing and cost model.

Tests how far the findings depend on the assumed costs:
1. One assumption at a time (tornado): overall contribution margin when one
   assumption moves across its range and the rest stay at the base case.
2. All assumptions at once (Monte Carlo): 10,000 scenarios in which every
   category's product cost moves independently by up to +/-10 points, shipping
   ranges from $5 to $11 per order and payment fees move by up to +/-0.5 points.

Usage:
    python analysis/sensitivity.py data/online_sales_data.csv data/cost_assumptions.csv
"""
import sys

import numpy as np
import pandas as pd

N_RUNS = 10_000
SEED = 42


def load(sales_path, assumptions_path):
    sales = pd.read_csv(sales_path)
    sales.columns = ["id", "date", "category", "product", "units", "price",
                     "revenue", "region", "payment"]
    a = pd.read_csv(assumptions_path)
    cat_rate = dict(a.loc[a.type == "category", ["key", "rate"]].values)
    pay = {k: (r, f) for k, r, f in a.loc[a.type == "payment", ["key", "rate", "fixed"]].values}
    ship = float(a.loc[a.type == "fulfilment", "fixed"].iloc[0])
    by_cat = sales.groupby("category").agg(
        revenue=("revenue", "sum"), orders=("id", "count"), payment=("payment", "first"))
    return by_cat, cat_rate, pay, ship


def contribution(by_cat, cat_rate, pay, ship, pay_shift=0.0):
    rev = by_cat.revenue.values
    orders = by_cat.orders.values
    cost_rate = np.array([cat_rate[c] for c in by_cat.index])
    pay_rate = np.array([pay[p][0] + pay_shift for p in by_cat.payment])
    pay_fixed = np.array([pay[p][1] for p in by_cat.payment])
    return rev - rev * cost_rate - (rev * pay_rate + orders * pay_fixed) - orders * ship


def main(sales_path, assumptions_path):
    by_cat, cat_rate, pay, ship = load(sales_path, assumptions_path)
    cats = list(by_cat.index)
    rev = by_cat.revenue.values
    total = rev.sum()

    base = contribution(by_cat, cat_rate, pay, ship)
    print(f"Base: contribution ${base.sum():,.0f}, margin {base.sum() / total:.1%}\n")

    print("One assumption at a time (overall margin, low to high)")
    rows = []
    for c in cats:
        lo = contribution(by_cat, {**cat_rate, c: cat_rate[c] + 0.10}, pay, ship).sum()
        hi = contribution(by_cat, {**cat_rate, c: cat_rate[c] - 0.10}, pay, ship).sum()
        rows.append((f"{c} product cost +/-10 pts", lo, hi))
    rows.append(("Shipping $5 to $11 per order",
                 contribution(by_cat, cat_rate, pay, 11).sum(),
                 contribution(by_cat, cat_rate, pay, 5).sum()))
    rows.append(("Payment fees +/-0.5 pts",
                 contribution(by_cat, cat_rate, pay, ship, 0.005).sum(),
                 contribution(by_cat, cat_rate, pay, ship, -0.005).sum()))
    for name, lo, hi in sorted(rows, key=lambda r: r[1] - r[2]):
        print(f"  {name:<40} {lo / total:6.1%} to {hi / total:6.1%}")

    rng = np.random.default_rng(SEED)
    elec = cats.index("Electronics")
    books = cats.index("Books")
    counts = dict(elec_share_below=0, elec_bottom2=0, elec_lowest=0,
                  books_bottom2=0, books_below_20=0, clothing_top=0)
    margins = []
    for _ in range(N_RUNS):
        rates = {c: cat_rate[c] + rng.uniform(-0.10, 0.10) for c in cats}
        con = contribution(by_cat, rates, pay, rng.uniform(5, 11), rng.uniform(-0.005, 0.005))
        m = con / rev
        order = list(np.argsort(m))
        counts["elec_share_below"] += con[elec] / con.sum() < rev[elec] / total
        counts["elec_bottom2"] += elec in order[:2]
        counts["elec_lowest"] += order[0] == elec
        counts["books_bottom2"] += books in order[:2]
        counts["books_below_20"] += m[books] < 0.20
        counts["clothing_top"] += cats[order[-1]] == "Clothing"
        margins.append(con.sum() / total)

    print(f"\nAll assumptions at once ({N_RUNS:,} scenarios)")
    labels = {
        "elec_share_below": "Electronics contribution share below its revenue share",
        "elec_bottom2": "Electronics has one of the two lowest margins",
        "elec_lowest": "Electronics has the lowest margin",
        "books_bottom2": "Books has one of the two lowest margins",
        "clothing_top": "Clothing has the highest margin",
        "books_below_20": "Books margin below 20%",
    }
    for k, label in labels.items():
        print(f"  {label:<58} {counts[k] / N_RUNS:6.1%}")
    p5, p95 = np.percentile(margins, [5, 95])
    print(f"  Overall margin, 5th to 95th percentile: {p5:.1%} to {p95:.1%}")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
