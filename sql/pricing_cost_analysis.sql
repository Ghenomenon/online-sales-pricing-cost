/* =====================================================================
   Online Sales: Pricing and Cost Analysis
   Dialect: T-SQL (SQL Server 2022 Express)
   Data:    online_sales_data.csv (240 orders, 2024-01-01 to 2024-08-27)
            cost_assumptions.csv (assumed cost rates, not actual costs)
   ===================================================================== */

/* ---------- Step 2: Database, tables, load ---------- */
CREATE DATABASE PricingProject;
GO
USE PricingProject;
GO

CREATE TABLE dbo.sales (
    transaction_id   INT            NOT NULL PRIMARY KEY,
    order_date       DATE           NOT NULL,
    product_category VARCHAR(50)    NOT NULL,
    product_name     NVARCHAR(200)  NOT NULL,
    units_sold       INT            NOT NULL,
    unit_price       DECIMAL(10,2)  NOT NULL,
    total_revenue    DECIMAL(12,2)  NOT NULL,
    region           VARCHAR(50)    NOT NULL,
    payment_method   VARCHAR(50)    NOT NULL
);

CREATE TABLE dbo.cost_assumptions (
    cost_type  VARCHAR(20)    NOT NULL,   -- category, payment, fulfilment
    cost_key   VARCHAR(50)    NOT NULL,
    rate       DECIMAL(6,4)   NOT NULL,   -- share of revenue
    fixed_fee  DECIMAL(8,2)   NOT NULL,   -- $ per order
    note       VARCHAR(200)   NULL,
    CONSTRAINT pk_cost PRIMARY KEY (cost_type, cost_key)
);
GO

BULK INSERT dbo.sales
FROM 'C:\PricingProject\online_sales_data.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDQUOTE = '"', ROWTERMINATOR = '0x0a', CODEPAGE = '65001');

BULK INSERT dbo.cost_assumptions
FROM 'C:\PricingProject\cost_assumptions.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDQUOTE = '"', ROWTERMINATOR = '0x0a');
GO

SELECT COUNT(*) AS sales_rows FROM dbo.sales;              -- expect 240
SELECT COUNT(*) AS cost_rows  FROM dbo.cost_assumptions;   -- expect 10

/* ---------- Step 3: Data quality checks ---------- */
-- 1. Date range and row count
SELECT MIN(order_date) AS first_day, MAX(order_date) AS last_day, COUNT(*) AS orders
FROM dbo.sales;

-- 2. Revenue = units x price (expect 0 rows)
SELECT transaction_id, units_sold, unit_price, total_revenue
FROM dbo.sales
WHERE ABS(units_sold * unit_price - total_revenue) > 0.01;

-- 3. Impossible values (expect 0 rows)
SELECT * FROM dbo.sales WHERE units_sold <= 0 OR unit_price <= 0;

-- 4. Missing cost rates (expect 0 rows)
SELECT DISTINCT s.product_category AS missing_key
FROM dbo.sales s
LEFT JOIN dbo.cost_assumptions c ON c.cost_type = 'category' AND c.cost_key = s.product_category
WHERE c.cost_key IS NULL
UNION
SELECT DISTINCT s.payment_method
FROM dbo.sales s
LEFT JOIN dbo.cost_assumptions c ON c.cost_type = 'payment' AND c.cost_key = s.payment_method
WHERE c.cost_key IS NULL;

-- 5. Category / region / payment overlap (6 rows = fully confounded)
SELECT product_category, region, payment_method, COUNT(*) AS orders
FROM dbo.sales
GROUP BY product_category, region, payment_method
ORDER BY product_category;
GO

/* ---------- Step 4: Cost model view ---------- */
CREATE OR ALTER VIEW dbo.vw_order_costs AS
SELECT
    s.transaction_id,
    s.order_date,
    DATEFROMPARTS(YEAR(s.order_date), MONTH(s.order_date), 1) AS order_month,
    s.product_category,
    s.product_name,
    s.region,
    s.payment_method,
    s.units_sold,
    s.unit_price,
    s.total_revenue,
    CASE
        WHEN s.unit_price <= 25   THEN '1. Under $25'
        WHEN s.unit_price <= 50   THEN '2. $25-50'
        WHEN s.unit_price <= 100  THEN '3. $50-100'
        WHEN s.unit_price <= 250  THEN '4. $100-250'
        WHEN s.unit_price <= 500  THEN '5. $250-500'
        WHEN s.unit_price <= 1000 THEN '6. $500-1,000'
        ELSE '7. $1,000+'
    END AS price_band,
    CAST(s.total_revenue * cat.rate AS DECIMAL(12,2))                 AS product_cost,
    CAST(s.total_revenue * pay.rate + pay.fixed_fee AS DECIMAL(12,2)) AS payment_fee,
    CAST(ful.fixed_fee AS DECIMAL(12,2))                              AS fulfilment_cost,
    CAST(s.total_revenue
         - s.total_revenue * cat.rate
         - (s.total_revenue * pay.rate + pay.fixed_fee)
         - ful.fixed_fee AS DECIMAL(12,2))                            AS contribution
FROM dbo.sales s
JOIN dbo.cost_assumptions cat
  ON cat.cost_type = 'category' AND cat.cost_key = s.product_category
JOIN dbo.cost_assumptions pay
  ON pay.cost_type = 'payment' AND pay.cost_key = s.payment_method
CROSS JOIN (
    SELECT fixed_fee FROM dbo.cost_assumptions
    WHERE cost_type = 'fulfilment' AND cost_key = 'Per order'
) ful;
GO

/* ---------- Step 5: Pricing analysis ---------- */
-- 5a. Headline figures
SELECT
    SUM(total_revenue)                    AS revenue,          -- 80,567.85
    COUNT(*)                              AS orders,           -- 240
    SUM(units_sold)                       AS units,            -- 518
    SUM(total_revenue) / SUM(units_sold)  AS avg_unit_price,   -- 155.54
    SUM(total_revenue) / COUNT(*)         AS avg_order_value   -- 335.70
FROM dbo.vw_order_costs;

-- 5b. Price profile by category
WITH med AS (
    SELECT DISTINCT product_category,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY unit_price)
            OVER (PARTITION BY product_category) AS median_price
    FROM dbo.vw_order_costs
)
SELECT
    v.product_category,
    MIN(v.region)                                             AS region,
    SUM(v.total_revenue)                                      AS revenue,
    SUM(v.total_revenue) / SUM(SUM(v.total_revenue)) OVER ()  AS revenue_share,
    COUNT(*)                                                  AS orders,
    CAST(SUM(v.units_sold) * 1.0 / COUNT(*) AS DECIMAL(5,2))  AS units_per_order,
    SUM(v.total_revenue) / SUM(v.units_sold)                  AS avg_unit_price,
    MIN(v.unit_price)                                         AS min_price,
    MAX(m.median_price)                                       AS median_price,
    MAX(v.unit_price)                                         AS max_price
FROM dbo.vw_order_costs v
JOIN med m ON m.product_category = v.product_category
GROUP BY v.product_category
ORDER BY revenue DESC;

-- 5c. Orders vs revenue by price band
SELECT
    price_band,
    COUNT(*)                                               AS orders,
    COUNT(*) * 1.0 / SUM(COUNT(*)) OVER ()                 AS order_share,
    SUM(total_revenue)                                     AS revenue,
    SUM(total_revenue) / SUM(SUM(total_revenue)) OVER ()   AS revenue_share,
    CAST(SUM(units_sold) * 1.0 / COUNT(*) AS DECIMAL(5,2)) AS units_per_order
FROM dbo.vw_order_costs
GROUP BY price_band
ORDER BY price_band;

-- 5d. Monthly trend
SELECT order_month,
       SUM(total_revenue)                   AS revenue,
       COUNT(*)                             AS orders,
       SUM(units_sold)                      AS units,
       SUM(total_revenue) / SUM(units_sold) AS avg_unit_price,
       SUM(contribution)                    AS contribution
FROM dbo.vw_order_costs
GROUP BY order_month
ORDER BY order_month;

-- 5d. First vs second half
SELECT
    SUM(CASE WHEN order_month <  '2024-05-01' THEN total_revenue END) AS jan_apr,  -- 50,652.62
    SUM(CASE WHEN order_month >= '2024-05-01' THEN total_revenue END) AS may_aug,  -- 29,915.23
    1 - SUM(CASE WHEN order_month >= '2024-05-01' THEN total_revenue END)
      / SUM(CASE WHEN order_month <  '2024-05-01' THEN total_revenue END) AS drop_pct  -- 0.409
FROM dbo.vw_order_costs;

-- 5e. Products sold at more than one price (expect 5)
WITH ranked AS (
    SELECT product_name, product_category, order_date, unit_price,
           ROW_NUMBER() OVER (PARTITION BY product_name ORDER BY order_date)      AS first_rn,
           ROW_NUMBER() OVER (PARTITION BY product_name ORDER BY order_date DESC) AS last_rn,
           COUNT(*)     OVER (PARTITION BY product_name)                          AS sales
    FROM dbo.vw_order_costs
)
SELECT f.product_name,
       f.order_date AS first_sale, f.unit_price AS first_price,
       l.order_date AS last_sale,  l.unit_price AS last_price,
       l.unit_price / f.unit_price - 1 AS price_change
FROM ranked f
JOIN ranked l ON l.product_name = f.product_name AND l.last_rn = 1
WHERE f.first_rn = 1 AND f.sales > 1 AND f.unit_price <> l.unit_price
ORDER BY price_change;

/* ---------- Step 6: Cost and margin ---------- */
-- 6a. Cost build-up by category
SELECT
    product_category,
    MIN(payment_method)                                  AS payment_method,
    SUM(total_revenue)                                   AS revenue,
    SUM(product_cost)                                    AS product_cost,
    SUM(payment_fee)                                     AS payment_fees,
    SUM(fulfilment_cost)                                 AS fulfilment,
    SUM(contribution)                                    AS contribution,
    SUM(contribution) / SUM(total_revenue)               AS margin_pct,
    SUM(contribution) / COUNT(*)                         AS contribution_per_order,
    SUM(total_revenue) / SUM(SUM(total_revenue)) OVER () AS revenue_share,
    SUM(contribution)  / SUM(SUM(contribution))  OVER () AS contribution_share
FROM dbo.vw_order_costs
GROUP BY product_category
ORDER BY revenue DESC;

-- 6b. Break-even order value: R = (pay_fixed + fulfilment) / (1 - cat_rate - pay_rate)
SELECT
    cat.cost_key AS product_category,
    pay.cost_key AS payment_method,
    CAST((pay.fixed_fee + ful.fixed_fee) / (1 - cat.rate - pay.rate) AS DECIMAL(8,2)) AS breakeven_order_value
FROM (SELECT DISTINCT product_category, payment_method FROM dbo.sales) s
JOIN dbo.cost_assumptions cat ON cat.cost_type = 'category' AND cat.cost_key = s.product_category
JOIN dbo.cost_assumptions pay ON pay.cost_type = 'payment'  AND pay.cost_key = s.payment_method
CROSS JOIN (SELECT fixed_fee FROM dbo.cost_assumptions WHERE cost_type = 'fulfilment') ful
ORDER BY breakeven_order_value DESC;

/* ---------- Step 7: Sensitivity check ---------- */
-- One assumption at a time: shift one category's product cost by -10 / +10 points,
-- or set shipping to $5 / $11, keep everything else at the base case,
-- and see how far overall contribution margin moves (base = 25.1%).
WITH scenarios AS (
    SELECT c.cost_key AS driver, v.shift AS cost_shift, CAST(NULL AS DECIMAL(8,2)) AS ship_fee
    FROM dbo.cost_assumptions c
    CROSS JOIN (VALUES (-0.10), (0.10)) v(shift)
    WHERE c.cost_type = 'category'
    UNION ALL
    SELECT 'Shipping per order', 0, v.fee
    FROM (VALUES (5.00), (11.00)) v(fee)
),
results AS (
    SELECT
        sc.driver,
        sc.cost_shift,
        sc.ship_fee,
        SUM(v.total_revenue) AS revenue,
        SUM(v.total_revenue
            - v.total_revenue * (cat.rate + CASE WHEN sc.driver = v.product_category THEN sc.cost_shift ELSE 0 END)
            - v.payment_fee
            - COALESCE(sc.ship_fee, v.fulfilment_cost)) AS contribution
    FROM scenarios sc
    CROSS JOIN dbo.vw_order_costs v
    JOIN dbo.cost_assumptions cat
      ON cat.cost_type = 'category' AND cat.cost_key = v.product_category
    GROUP BY sc.driver, sc.cost_shift, sc.ship_fee
)
SELECT
    driver,
    MIN(contribution / revenue) AS low_margin,
    MAX(contribution / revenue) AS high_margin,
    MAX(contribution / revenue) - MIN(contribution / revenue) AS swing
FROM results
GROUP BY driver
ORDER BY swing DESC;
-- Expected: Electronics swings margin from about 20.8% to 29.4%, the widest range.
