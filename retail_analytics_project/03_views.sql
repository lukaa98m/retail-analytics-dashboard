-- =====================================================================
-- Retail Analytics Dashboard — KPI Views
-- =====================================================================
-- This file defines all business views that Power BI imports.
--
-- Each view demonstrates at least one of:
--   [J] JOINs         — combining customers/orders/products/regions
--   [A] Aggregations  — SUM, COUNT, AVG, MIN, MAX
--   [W] Window fns    — LAG, RANK, ROW_NUMBER, NTILE, SUM() OVER
--
-- Requires MySQL 8.0+ (for window functions).
-- =====================================================================

USE retail_analytics;

-- =====================================================================
-- v_order_revenue  (helper view — reused by others)
-- ---------------------------------------------------------------------
-- Flattens order_items + orders + customers + products + regions into
-- a single wide view. All downstream KPI views build on this.
-- Techniques: [J] 5-way join, [A] SUM per order
-- =====================================================================
DROP VIEW IF EXISTS v_order_revenue;
CREATE VIEW v_order_revenue AS
SELECT
    oi.order_item_id,
    o.order_id,
    o.order_date,
    YEAR(o.order_date)           AS order_year,
    MONTH(o.order_date)          AS order_month,
    DATE_FORMAT(o.order_date, '%Y-%m-01') AS order_month_start,
    c.customer_id,
    c.customer_name,
    c.segment,
    p.product_id,
    p.product_name,
    p.category,
    p.sub_category,
    r.region_name,
    o.state,
    o.city,
    o.ship_mode,
    DATEDIFF(o.ship_date, o.order_date) AS days_to_ship,
    oi.sales
FROM order_items oi
JOIN orders    o ON oi.order_id    = o.order_id
JOIN customers c ON o.customer_id  = c.customer_id
JOIN products  p ON oi.product_id  = p.product_id
JOIN regions   r ON o.region_id    = r.region_id;


-- =====================================================================
-- v_monthly_revenue
-- ---------------------------------------------------------------------
-- KPI: Monthly revenue, order count, and month-over-month growth %.
-- Techniques: [A] SUM/COUNT, [W] LAG window function for MoM growth
-- Feeds: Executive Overview page — revenue trend line chart.
-- =====================================================================
DROP VIEW IF EXISTS v_monthly_revenue;
CREATE VIEW v_monthly_revenue AS
SELECT
    order_year,
    order_month,
    order_month_start AS month_start,
    SUM(sales)                              AS monthly_revenue,
    COUNT(DISTINCT order_id)                AS order_count,
    COUNT(DISTINCT customer_id)             AS active_customers,
    SUM(sales) / COUNT(DISTINCT order_id)   AS avg_order_value,
    -- Month-over-month growth using LAG()
    LAG(SUM(sales)) OVER (ORDER BY order_year, order_month) AS prev_month_revenue,
    ROUND(
        100.0 * (SUM(sales) - LAG(SUM(sales)) OVER (ORDER BY order_year, order_month))
        / NULLIF(LAG(SUM(sales)) OVER (ORDER BY order_year, order_month), 0),
        2
    ) AS mom_growth_pct
FROM v_order_revenue
GROUP BY order_year, order_month, order_month_start;


-- =====================================================================
-- v_top_customers
-- ---------------------------------------------------------------------
-- KPI: Customer lifetime value, rank, and behavior metrics.
-- Techniques: [J] customers x orders x order_items,
--             [A] SUM/COUNT/AVG,
--             [W] RANK() for overall ranking,
--                 DENSE_RANK() within segment.
-- Feeds: Customer page — top customers table, segment comparison.
-- =====================================================================
DROP VIEW IF EXISTS v_top_customers;
CREATE VIEW v_top_customers AS
SELECT
    c.customer_id,
    c.customer_name,
    c.segment,
    COUNT(DISTINCT o.order_id)                     AS total_orders,
    SUM(oi.sales)                                  AS lifetime_value,
    ROUND(AVG(oi.sales), 2)                        AS avg_line_value,
    ROUND(SUM(oi.sales) / COUNT(DISTINCT o.order_id), 2) AS avg_order_value,
    MIN(o.order_date)                              AS first_order_date,
    MAX(o.order_date)                              AS last_order_date,
    RANK()       OVER (ORDER BY SUM(oi.sales) DESC)                      AS overall_rank,
    DENSE_RANK() OVER (PARTITION BY c.segment ORDER BY SUM(oi.sales) DESC) AS rank_within_segment
FROM customers c
JOIN orders      o  ON c.customer_id = o.customer_id
JOIN order_items oi ON o.order_id    = oi.order_id
GROUP BY c.customer_id, c.customer_name, c.segment;


-- =====================================================================
-- v_category_performance
-- ---------------------------------------------------------------------
-- KPI: Category-level revenue with running total and share of total.
-- Techniques: [J] products x order_items, [A] SUM,
--             [W] SUM() OVER for running totals and window-based share.
-- Feeds: Product page — category bars, running-total line.
-- =====================================================================
DROP VIEW IF EXISTS v_category_performance;
CREATE VIEW v_category_performance AS
SELECT
    p.category,
    p.sub_category,
    COUNT(DISTINCT oi.order_id)                AS orders_containing,
    COUNT(oi.order_item_id)                    AS line_items_sold,
    SUM(oi.sales)                              AS revenue,
    ROUND(AVG(oi.sales), 2)                    AS avg_line_value,
    -- Running total of revenue within the category, ordered by sub-category revenue desc
    SUM(SUM(oi.sales)) OVER (
        PARTITION BY p.category
        ORDER BY SUM(oi.sales) DESC
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS running_revenue_in_category,
    -- Share of the sub-category's revenue relative to its parent category
    ROUND(
        100.0 * SUM(oi.sales)
        / SUM(SUM(oi.sales)) OVER (PARTITION BY p.category),
        2
    ) AS pct_of_category
FROM products p
JOIN order_items oi ON p.product_id = oi.product_id
GROUP BY p.category, p.sub_category;


-- =====================================================================
-- v_regional_sales
-- ---------------------------------------------------------------------
-- KPI: Sales, orders, and customers by region + state (for map visual).
-- Techniques: [J] regions x orders x order_items,
--             [A] SUM / COUNT DISTINCT,
--             [W] RANK() states within region,
--                 share of national revenue via window SUM.
-- Feeds: Geography page — filled map, regional bars.
-- =====================================================================
DROP VIEW IF EXISTS v_regional_sales;
CREATE VIEW v_regional_sales AS
SELECT
    r.region_name,
    o.state,
    COUNT(DISTINCT o.order_id)             AS order_count,
    COUNT(DISTINCT o.customer_id)          AS unique_customers,
    SUM(oi.sales)                          AS revenue,
    ROUND(SUM(oi.sales)
          / COUNT(DISTINCT o.order_id), 2) AS avg_order_value,
    -- State rank within its region by revenue
    RANK() OVER (PARTITION BY r.region_name ORDER BY SUM(oi.sales) DESC) AS state_rank_in_region,
    -- State's share of the national revenue
    ROUND(
        100.0 * SUM(oi.sales)
        / SUM(SUM(oi.sales)) OVER (),
        3
    ) AS pct_of_national_revenue
FROM regions r
JOIN orders      o  ON r.region_id  = o.region_id
JOIN order_items oi ON o.order_id   = oi.order_id
GROUP BY r.region_name, o.state;


-- =====================================================================
-- v_customer_rfm
-- ---------------------------------------------------------------------
-- KPI: RFM (Recency, Frequency, Monetary) customer segmentation.
--   R = days since last order  (lower = better)
--   F = number of distinct orders  (higher = better)
--   M = total sales  (higher = better)
-- Each dimension is bucketed 1–5 with NTILE; combined label drives
-- segment strategy (Champions, Loyal, At-Risk, etc.).
--
-- Techniques: [J] customers x orders x order_items,
--             [A] MAX/COUNT/SUM,
--             [W] NTILE(5) across all customers per dimension.
-- Feeds: Customer page — RFM heatmap, segment strategy table.
-- =====================================================================
DROP VIEW IF EXISTS v_customer_rfm;
CREATE VIEW v_customer_rfm AS
WITH base AS (
    SELECT
        c.customer_id,
        c.customer_name,
        c.segment,
        DATEDIFF(
            (SELECT MAX(order_date) FROM orders),
            MAX(o.order_date)
        ) AS recency_days,
        COUNT(DISTINCT o.order_id) AS frequency,
        SUM(oi.sales)              AS monetary
    FROM customers c
    JOIN orders      o  ON c.customer_id = o.customer_id
    JOIN order_items oi ON o.order_id    = oi.order_id
    GROUP BY c.customer_id, c.customer_name, c.segment
)
SELECT
    customer_id,
    customer_name,
    segment,
    recency_days,
    frequency,
    ROUND(monetary, 2) AS monetary,
    -- Recency: lower days = better, so reverse the order
    NTILE(5) OVER (ORDER BY recency_days DESC) AS r_score,
    NTILE(5) OVER (ORDER BY frequency    ASC)  AS f_score,
    NTILE(5) OVER (ORDER BY monetary     ASC)  AS m_score,
    -- Combined RFM label, e.g. '545'
    CONCAT(
        NTILE(5) OVER (ORDER BY recency_days DESC),
        NTILE(5) OVER (ORDER BY frequency    ASC),
        NTILE(5) OVER (ORDER BY monetary     ASC)
    ) AS rfm_cell,
    -- High-level segment based on average of the three scores
    CASE
        WHEN (NTILE(5) OVER (ORDER BY recency_days DESC)
            + NTILE(5) OVER (ORDER BY frequency    ASC)
            + NTILE(5) OVER (ORDER BY monetary     ASC)) / 3.0 >= 4.5 THEN 'Champions'
        WHEN (NTILE(5) OVER (ORDER BY recency_days DESC)
            + NTILE(5) OVER (ORDER BY frequency    ASC)
            + NTILE(5) OVER (ORDER BY monetary     ASC)) / 3.0 >= 3.5 THEN 'Loyal'
        WHEN (NTILE(5) OVER (ORDER BY recency_days DESC)
            + NTILE(5) OVER (ORDER BY frequency    ASC)
            + NTILE(5) OVER (ORDER BY monetary     ASC)) / 3.0 >= 2.5 THEN 'Potential'
        WHEN (NTILE(5) OVER (ORDER BY recency_days DESC)
            + NTILE(5) OVER (ORDER BY frequency    ASC)
            + NTILE(5) OVER (ORDER BY monetary     ASC)) / 3.0 >= 1.5 THEN 'At Risk'
        ELSE 'Hibernating'
    END AS rfm_segment
FROM base;


-- =====================================================================
-- v_top_products_per_category
-- ---------------------------------------------------------------------
-- KPI: Top N products within each category.
-- Techniques: [J] products x order_items, [A] SUM,
--             [W] ROW_NUMBER() OVER (PARTITION BY category ORDER BY revenue DESC).
-- Power BI filters this to rank <= 10 for a "top products" visual.
-- =====================================================================
DROP VIEW IF EXISTS v_top_products_per_category;
CREATE VIEW v_top_products_per_category AS
SELECT
    p.category,
    p.sub_category,
    p.product_id,
    p.product_name,
    COUNT(oi.order_item_id) AS line_items_sold,
    SUM(oi.sales)           AS revenue,
    ROW_NUMBER() OVER (PARTITION BY p.category ORDER BY SUM(oi.sales) DESC) AS rank_in_category
FROM products p
JOIN order_items oi ON p.product_id = oi.product_id
GROUP BY p.category, p.sub_category, p.product_id, p.product_name;


-- =====================================================================
-- v_kpi_summary
-- ---------------------------------------------------------------------
-- KPI: Single-row headline metrics for the dashboard's KPI cards.
-- Feeds: Executive Overview page — 4 KPI cards at the top.
-- =====================================================================
DROP VIEW IF EXISTS v_kpi_summary;
CREATE VIEW v_kpi_summary AS
SELECT
    ROUND(SUM(oi.sales), 2)          AS total_revenue,
    COUNT(DISTINCT o.order_id)       AS total_orders,
    COUNT(DISTINCT c.customer_id)    AS total_customers,
    COUNT(DISTINCT p.product_id)     AS total_products,
    ROUND(SUM(oi.sales)
          / COUNT(DISTINCT o.order_id), 2) AS avg_order_value,
    MIN(o.order_date)                AS first_order_date,
    MAX(o.order_date)                AS last_order_date
FROM order_items oi
JOIN orders    o ON oi.order_id    = o.order_id
JOIN customers c ON o.customer_id  = c.customer_id
JOIN products  p ON oi.product_id  = p.product_id;
