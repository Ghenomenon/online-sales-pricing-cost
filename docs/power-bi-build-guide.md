# Power BI Build Guide

How to build the pricing and cost report in Power BI Desktop on top of the SQL Server view. Run `sql/pricing_cost_analysis.sql` (steps 2 to 4 at least) first.

## 1. Connect to SQL Server

1. **Home** > **Get data** > **SQL Server**. Server: `localhost\SQLEXPRESS`. Database: `PricingProject`. Mode: **Import**.
2. Choose **Windows** > **Use my current credentials**.
3. In Navigator, tick `vw_order_costs` and `cost_assumptions`, then **Transform Data**.
4. Rename them **Orders** and **Cost Assumptions**.
5. Check types: dates as Date, money columns as Fixed decimal number, `units_sold` as Whole number.
6. Add a display column: **Add Column** > **Custom Column**, name `Price Band`, formula `Text.AfterDelimiter([price_band], ". ")`.
7. **Close & Apply**.

## 2. Data model

Create a date table (**Modeling** > **New table**):

```dax
Calendar =
ADDCOLUMNS (
    CALENDAR ( DATE ( 2024, 1, 1 ), DATE ( 2024, 8, 31 ) ),
    "Month Start", DATE ( YEAR ( [Date] ), MONTH ( [Date] ), 1 ),
    "Month", FORMAT ( [Date], "mmm yyyy" ),
    "Month Number", YEAR ( [Date] ) * 100 + MONTH ( [Date] ),
    "Period", IF ( MONTH ( [Date] ) <= 4, "Jan-Apr", "May-Aug" )
)
```

- Mark `Calendar` as a date table on `Date`. Sort `Month` by `Month Number`. Sort `Price Band` by `price_band`.
- Relationship: `Calendar[Date]` 1 to many `Orders[order_date]`, single direction.
- `Cost Assumptions` stays unrelated; it feeds the assumptions table visual.

## 3. Measures

Keep measures in an empty `_Measures` table (**Home** > **Enter data**).

```dax
Revenue = SUM ( Orders[total_revenue] )
Order Count = COUNTROWS ( Orders )
Units = SUM ( Orders[units_sold] )
Avg Unit Price = DIVIDE ( [Revenue], [Units] )
Avg Order Value = DIVIDE ( [Revenue], [Order Count] )
Units per Order = DIVIDE ( [Units], [Order Count] )
Median Price = MEDIAN ( Orders[unit_price] )

Revenue Share = DIVIDE ( [Revenue], CALCULATE ( [Revenue], ALLSELECTED ( Orders ) ) )
Order Share = DIVIDE ( [Order Count], CALCULATE ( [Order Count], ALLSELECTED ( Orders ) ) )

Revenue Jan-Apr = CALCULATE ( [Revenue], Calendar[Period] = "Jan-Apr" )
Revenue May-Aug = CALCULATE ( [Revenue], Calendar[Period] = "May-Aug" )
Revenue Drop % = 1 - DIVIDE ( [Revenue May-Aug], [Revenue Jan-Apr] )

Product Cost = SUM ( Orders[product_cost] )
Payment Fees = SUM ( Orders[payment_fee] )
Fulfilment Cost = SUM ( Orders[fulfilment_cost] )
Total Cost = [Product Cost] + [Payment Fees] + [Fulfilment Cost]
Contribution = [Revenue] - [Total Cost]
Margin % = DIVIDE ( [Contribution], [Revenue] )
Contribution per Order = DIVIDE ( [Contribution], [Order Count] )
Contribution Share = DIVIDE ( [Contribution], CALCULATE ( [Contribution], ALLSELECTED ( Orders ) ) )

Products for 80% Revenue =
VAR TotalRev = [Revenue]
VAR ByProduct = ADDCOLUMNS ( VALUES ( Orders[product_name] ), "@Rev", [Revenue] )
VAR WithRunning =
    ADDCOLUMNS (
        ByProduct,
        "@Before", SUMX ( FILTER ( ByProduct, [@Rev] > EARLIER ( [@Rev] ) ), [@Rev] )
    )
RETURN COUNTROWS ( FILTER ( WithRunning, [@Before] < 0.8 * TotalRev ) )
```

## 4. What-if parameters

**Modeling** > **New parameter** > **Numeric range**:

- `Discount %`: 0 to 0.3, increment 0.01, default 0
- `Shipping per Order`: 0 to 15, increment 0.5, default 8
- `Product Cost Shift`: -0.1 to 0.1, increment 0.01, default 0

```dax
Scenario Revenue = [Revenue] * ( 1 - [Discount % Value] )
Scenario Product Cost =
    SUMX ( Orders, Orders[product_cost] + Orders[total_revenue] * [Product Cost Shift Value] )
Scenario Payment Fees = [Payment Fees] * ( 1 - [Discount % Value] )  -- approximation: also scales the fixed fee
Scenario Fulfilment = [Order Count] * [Shipping per Order Value]
Scenario Contribution =
    [Scenario Revenue] - [Scenario Product Cost] - [Scenario Payment Fees] - [Scenario Fulfilment]
Scenario Margin % = DIVIDE ( [Scenario Contribution], [Scenario Revenue] )
Contribution Change % = DIVIDE ( [Scenario Contribution] - [Contribution], [Contribution] )
```

## 5. Report pages

| Page | Question | Visuals |
| --- | --- | --- |
| Overview | How are we doing? | Cards: Revenue, Avg Unit Price, Avg Order Value, Total Cost, Contribution, Margin %. Column chart of Revenue and Contribution by `Calendar[Month]`. Card: Revenue Drop %. Category slicer |
| Pricing | Where does revenue come from? | Bar chart of Order Share and Revenue Share by `Price Band`. Category table with price spread. Card: Products for 80% Revenue |
| Cost and margin | Where do we make money? | Bar chart of Revenue Share and Contribution Share by category. Margin % by category, red below 20%. Cost build-up matrix. Assumptions table titled "Assumed costs, not actuals" |
| Scenarios | What if? | The three parameter slicers, scenario cards, Scenario Margin % by category |

## 6. Check the numbers

| Check | Expected |
| --- | --- |
| Revenue | $80,568 |
| Orders / Units | 240 / 518 |
| Avg Unit Price / Avg Order Value | $155.54 / $335.70 |
| Revenue Drop % | 40.9% |
| Contribution / Margin % | $20,221 / 25.1% |
| Margin %: Electronics / Books / Clothing | 16.2% / 19.3% / 44.5% |
| Electronics, 5% discount | Contribution Change % about −30% |
| Products for 80% Revenue | About 84 of 232 |
