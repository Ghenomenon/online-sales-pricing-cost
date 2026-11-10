# Online Sales Pricing and Cost Analysis

Where does an online shop actually make its money? A SQL Server cost model and pricing analysis of 240 online orders across six product categories, with a sensitivity check on every cost assumption.

**[Read the case study and try the scenario explorer](https://chigozie-nkwopara.netlify.app/pricing-cost-case-study)**

> The dataset has no cost data. Product costs, payment fees and shipping are stated benchmark assumptions in `data/cost_assumptions.csv`. The model is built so real costs replace them in one table, and the sensitivity check shows which findings depend on them.

## Business question

Which products and price points carry the business, and where would a discount or a change in shipping cost hurt margin most?

## Findings

| Finding | Robustness across 10,000 cost scenarios |
| --- | --- |
| Revenue fell 40.9% from January–April ($50,653) to May–August ($29,915), driven by fewer high-ticket orders | Not cost-dependent |
| Items under $50 are 39.6% of orders but 8.4% of revenue | Not cost-dependent |
| Electronics brings 43.4% of revenue but 27.9% of contribution (16.2% margin) | Holds in 99.9% |
| A 5% electronics discount cuts its contribution by 19% to 44%, depending on its true product cost | Holds in every case tested |
| Books has one of the two lowest margins; a book order needs about $22 to break even | Holds in 75% |
| Books margin is below 20% | Holds in 54%: fragile |

Electronics product cost moves overall margin from 20.8% to 29.4%, more than every other assumption combined. It is the first real number to collect.

## What is in the repository

| Path | Contents |
| --- | --- |
| `sql/pricing_cost_analysis.sql` | T-SQL for SQL Server: tables and bulk load, five data-quality checks, the `vw_order_costs` cost view, pricing queries, cost and break-even queries, and a one-at-a-time sensitivity query |
| `analysis/sensitivity.py` | The tornado and 10,000-scenario Monte Carlo check |
| `data/cost_assumptions.csv` | The assumed cost rates the view reads |
| `data/order_totals_by_category_month.csv` | Order totals by category and month, as used by the portfolio explorer |
| `docs/power-bi-build-guide.md` | Step-by-step build of the Power BI report on top of the SQL view |

## Method

1. **Load and check.** Two tables, `sales` and `cost_assumptions`. Checks confirm revenue equals units × price on every row, no impossible values, and a cost rate for every category and payment method.
2. **One cost view.** `vw_order_costs` joins each order to the assumptions and adds product cost, payment fee, fulfilment cost and contribution. Every query and the Power BI model read from it.
3. **Pricing.** Price profile by category with medians, orders against revenue by price band, monthly trend, revenue concentration and repeat products sold at different prices.
4. **Cost and margin.** Cost build-up by category, revenue share against contribution share, and break-even order value.
5. **Sensitivity.** One assumption at a time, then all at once, to separate robust findings from fragile ones.

## How to run it

1. Download the [Online Sales Dataset (Popular Marketplace Data)](https://www.kaggle.com/datasets/shreyanshverma27/online-sales-dataset-popular-marketplace-data) from Kaggle and save it as `data/online_sales_data.csv`.
2. Copy both CSVs to `C:\PricingProject\`, open `sql/pricing_cost_analysis.sql` in SQL Server Management Studio and run it step by step.
3. For the sensitivity check: `pip install pandas numpy`, then `python analysis/sensitivity.py data/online_sales_data.csv data/cost_assumptions.csv`.

## Limitations

- Costs are assumed. Margins will move with real supplier prices, fee contracts and shipping rates.
- Each category was sold in one region with one payment method, so category, region and payment effects cannot be separated.
- 240 orders, one per day, over eight months. No returns, customer IDs or marketing spend.

## Data source

Online Sales Dataset (Popular Marketplace Data), published on Kaggle by Shreyansh Verma. The raw file is not redistributed here; download it from the link above.

## Licence

Code: MIT (see `LICENSE`).

## Author

Chigozie Nkwopara · [Portfolio](https://chigozie-nkwopara.netlify.app) · [GitHub](https://github.com/Ghenomenon)
