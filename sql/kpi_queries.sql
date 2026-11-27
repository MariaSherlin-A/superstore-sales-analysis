-- =====================================================================
-- Superstore Sales: KPI queries (SQLite)
-- Each query starts with "-- name: <output_file>" so run_queries.py can
-- save its result to outputs/<output_file>.csv
-- =====================================================================


-- name: 01_overall_kpis
-- Headline KPIs for the whole period
SELECT
    COUNT(DISTINCT order_id)                          AS total_orders,
    COUNT(DISTINCT customer_id)                       AS total_customers,
    ROUND(SUM(sales), 2)                              AS total_sales,
    ROUND(SUM(profit), 2)                             AS total_profit,
    ROUND(100.0 * SUM(profit) / SUM(sales), 2)        AS profit_margin_pct,
    ROUND(SUM(sales) / COUNT(DISTINCT order_id), 2)   AS avg_order_value
FROM fact_sales;


-- name: 02_yearly_yoy_growth
-- Year-over-year growth in sales and profit (CTE + LAG window function)
WITH yearly AS (
    SELECT
        CAST(strftime('%Y', order_date) AS INTEGER) AS order_year,
        SUM(sales)                 AS sales,
        SUM(profit)                AS profit,
        COUNT(DISTINCT order_id)   AS orders
    FROM fact_sales
    GROUP BY order_year
)
SELECT
    order_year,
    ROUND(sales, 2)                                   AS sales,
    ROUND(profit, 2)                                  AS profit,
    orders,
    ROUND(100.0 * profit / sales, 2)                  AS profit_margin_pct,
    ROUND(100.0 * (sales - LAG(sales) OVER (ORDER BY order_year))
          / LAG(sales) OVER (ORDER BY order_year), 2) AS sales_yoy_pct,
    ROUND(100.0 * (profit - LAG(profit) OVER (ORDER BY order_year))
          / LAG(profit) OVER (ORDER BY order_year), 2) AS profit_yoy_pct
FROM yearly
ORDER BY order_year;


-- name: 03_monthly_trend
-- Monthly sales with a running total per year and a 3-month moving average
WITH monthly AS (
    SELECT strftime('%Y-%m', order_date) AS order_month,
           SUM(sales)  AS sales,
           SUM(profit) AS profit
    FROM fact_sales
    GROUP BY order_month
)
SELECT
    order_month,
    ROUND(sales, 2)  AS sales,
    ROUND(profit, 2) AS profit,
    ROUND(SUM(sales) OVER (PARTITION BY substr(order_month, 1, 4)
                           ORDER BY order_month), 2)               AS ytd_sales,
    ROUND(AVG(sales) OVER (ORDER BY order_month
                           ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 2) AS sales_3m_moving_avg
FROM monthly
ORDER BY order_month;


-- name: 04_top10_products
-- Top 10 products by sales (JOIN to the product dimension + RANK)
SELECT *
FROM (
    SELECT
        RANK() OVER (ORDER BY SUM(f.sales) DESC) AS sales_rank,
        p.product_name,
        p.category,
        ROUND(SUM(f.sales), 2)  AS sales,
        ROUND(SUM(f.profit), 2) AS profit,
        SUM(f.quantity)         AS units
    FROM fact_sales f
    JOIN dim_product p ON p.product_id = f.product_id
    GROUP BY p.product_id
)
WHERE sales_rank <= 10
ORDER BY sales_rank;


-- name: 05_top3_subcategories_per_region
-- Top-N within groups: the 3 best-selling sub-categories in every region
WITH region_sub AS (
    SELECT f.region, p.sub_category,
           SUM(f.sales)  AS sales,
           SUM(f.profit) AS profit
    FROM fact_sales f
    JOIN dim_product p ON p.product_id = f.product_id
    GROUP BY f.region, p.sub_category
),
ranked AS (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY region ORDER BY sales DESC) AS rn
    FROM region_sub
)
SELECT region, rn AS rank_in_region, sub_category,
       ROUND(sales, 2) AS sales, ROUND(profit, 2) AS profit
FROM ranked
WHERE rn <= 3
ORDER BY region, rn;


-- name: 06_region_performance
-- Sales, profit, margin and share of total sales by region
SELECT
    region,
    ROUND(SUM(sales), 2)                                        AS sales,
    ROUND(SUM(profit), 2)                                       AS profit,
    ROUND(100.0 * SUM(profit) / SUM(sales), 2)                  AS profit_margin_pct,
    ROUND(100.0 * SUM(sales) / SUM(SUM(sales)) OVER (), 2)      AS share_of_sales_pct
FROM fact_sales
GROUP BY region
ORDER BY sales DESC;


-- name: 07_loss_making_subcategories
-- Sub-categories that lose money overall, with their average discount
SELECT
    p.category,
    p.sub_category,
    ROUND(SUM(f.sales), 2)               AS sales,
    ROUND(SUM(f.profit), 2)              AS profit,
    ROUND(100.0 * AVG(f.discount), 1)    AS avg_discount_pct
FROM fact_sales f
JOIN dim_product p ON p.product_id = f.product_id
GROUP BY p.category, p.sub_category
HAVING SUM(f.profit) < 0
ORDER BY profit;


-- name: 08_discount_vs_margin
-- How discount level affects profitability (CASE bands)
SELECT
    CASE
        WHEN discount = 0     THEN '1. No discount'
        WHEN discount <= 0.2  THEN '2. 1-20%'
        WHEN discount <= 0.4  THEN '3. 21-40%'
        ELSE                       '4. Over 40%'
    END                                          AS discount_band,
    COUNT(*)                                     AS order_lines,
    ROUND(SUM(sales), 2)                         AS sales,
    ROUND(SUM(profit), 2)                        AS profit,
    ROUND(100.0 * SUM(profit) / SUM(sales), 2)   AS profit_margin_pct
FROM fact_sales
GROUP BY discount_band
ORDER BY discount_band;


-- name: 09_segment_performance
-- Customer segments (JOIN to the customer dimension)
SELECT
    c.segment,
    COUNT(DISTINCT c.customer_id)                          AS customers,
    COUNT(DISTINCT f.order_id)                             AS orders,
    ROUND(SUM(f.sales), 2)                                 AS sales,
    ROUND(SUM(f.profit), 2)                                AS profit,
    ROUND(SUM(f.sales) / COUNT(DISTINCT c.customer_id), 2) AS sales_per_customer
FROM fact_sales f
JOIN dim_customer c ON c.customer_id = f.customer_id
GROUP BY c.segment
ORDER BY sales DESC;


-- name: 10_top10_customers
-- Top 10 customers by sales, with their share of total sales
WITH cust AS (
    SELECT c.customer_name, c.segment,
           SUM(f.sales) AS sales, SUM(f.profit) AS profit,
           COUNT(DISTINCT f.order_id) AS orders
    FROM fact_sales f
    JOIN dim_customer c ON c.customer_id = f.customer_id
    GROUP BY c.customer_id
)
SELECT
    DENSE_RANK() OVER (ORDER BY sales DESC)              AS sales_rank,
    customer_name, segment, orders,
    ROUND(sales, 2)                                      AS sales,
    ROUND(profit, 2)                                     AS profit,
    ROUND(100.0 * sales / SUM(sales) OVER (), 2)         AS share_of_sales_pct
FROM cust
ORDER BY sales DESC
LIMIT 10;


-- name: 11_shipping_performance
-- Average days to ship by ship mode
SELECT
    ship_mode,
    COUNT(DISTINCT order_id)     AS orders,
    ROUND(AVG(ship_days), 2)     AS avg_ship_days,
    MAX(ship_days)               AS max_ship_days
FROM fact_sales
GROUP BY ship_mode
ORDER BY avg_ship_days;
