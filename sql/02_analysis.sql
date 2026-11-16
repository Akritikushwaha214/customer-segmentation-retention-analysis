-- =====================================================================
-- Customer Segmentation & Retention (RFM + Cohort)  |  Akriti Kushwaha
-- File 2 of 2: analysis queries (MySQL 8.0+)
-- Currency: GBP. Data: 1 Dec 2009 to 9 Dec 2011.
-- "Sales" are invoices with is_return = 0.
-- Analysis date for recency = 10 Dec 2011 (the day after the last order).
-- December 2011 holds only 9 days, so month-level trend and retention
-- queries stop at 30 Nov 2011.
-- =====================================================================
USE retail_retention;

-- ---------------------------------------------------------------------
-- A. OVERVIEW
-- ---------------------------------------------------------------------

-- Q1. What is in the data? Sales, returns, customers and the date range.
SELECT
    COUNT(*)                                                    AS invoices,
    SUM(CASE WHEN is_return = 0 THEN 1 ELSE 0 END)              AS sales_invoices,
    SUM(is_return)                                              AS return_invoices,
    COUNT(DISTINCT CASE WHEN is_return = 0 THEN customer_id END) AS customers_with_sale,
    MIN(invoice_date)                                           AS first_invoice,
    MAX(invoice_date)                                           AS last_invoice
FROM invoices;

-- Q2. Headline numbers for the dashboard.
SELECT
    COUNT(DISTINCT customer_id)                          AS customers,
    COUNT(*)                                             AS sales_invoices,
    ROUND(SUM(invoice_value), 0)                         AS revenue,
    ROUND(AVG(invoice_value), 2)                         AS avg_order_value,
    ROUND(COUNT(*) * 1.0 / COUNT(DISTINCT customer_id), 1) AS orders_per_customer,
    ROUND(SUM(invoice_value) / COUNT(DISTINCT customer_id), 0) AS revenue_per_customer
FROM invoices
WHERE is_return = 0;

-- Q3. How much do returns cost? Value of cancelled invoices vs sales.
SELECT
    ROUND(SUM(CASE WHEN is_return = 0 THEN invoice_value ELSE 0 END), 0)  AS sales_value,
    ROUND(-SUM(CASE WHEN is_return = 1 THEN invoice_value ELSE 0 END), 0) AS returned_value,
    ROUND(100.0 * -SUM(CASE WHEN is_return = 1 THEN invoice_value ELSE 0 END)
          / SUM(CASE WHEN is_return = 0 THEN invoice_value ELSE 0 END), 1) AS returned_pct_of_sales
FROM invoices;

-- Q4. Which countries matter? Top 5 by revenue with share of total.
SELECT country,
       COUNT(DISTINCT customer_id)                                   AS customers,
       ROUND(SUM(invoice_value), 0)                                  AS revenue,
       ROUND(100.0 * SUM(invoice_value) / SUM(SUM(invoice_value)) OVER (), 1) AS share_pct
FROM invoices
WHERE is_return = 0
GROUP BY country
ORDER BY revenue DESC
LIMIT 5;

-- Q5. Monthly revenue, active customers and month-over-month change.
WITH monthly AS (
    SELECT DATE_FORMAT(invoice_date, '%Y-%m') AS ym,
           SUM(invoice_value)                 AS revenue,
           COUNT(DISTINCT customer_id)        AS active_customers
    FROM invoices
    WHERE is_return = 0 AND invoice_date < '2011-12-01'
    GROUP BY DATE_FORMAT(invoice_date, '%Y-%m')
)
SELECT ym,
       ROUND(revenue, 0) AS revenue,
       active_customers,
       ROUND(100.0 * (revenue - LAG(revenue) OVER (ORDER BY ym))
             / LAG(revenue) OVER (ORDER BY ym), 1) AS mom_pct
FROM monthly
ORDER BY ym;

-- ---------------------------------------------------------------------
-- B. RFM SEGMENTATION
-- Recency   = days since the last purchase (lower is better)
-- Frequency = number of purchase invoices
-- Monetary  = total spend
-- R and M are scored 1 to 5 with NTILE(5) (5 = best). Customers with the
-- same value are ordered by customer_id so results are repeatable.
-- F uses fixed bands because over a quarter of customers have exactly one
-- order, and NTILE would split identical customers into different scores.
-- ---------------------------------------------------------------------

CREATE OR REPLACE VIEW v_rfm_base AS
SELECT customer_id,
       MAX(country)                                         AS country,
       MIN(invoice_date)                                    AS first_order,
       MAX(invoice_date)                                    AS last_order,
       DATEDIFF('2011-12-10', DATE(MAX(invoice_date)))      AS recency_days,
       COUNT(*)                                             AS frequency,
       ROUND(SUM(invoice_value), 2)                         AS monetary
FROM invoices
WHERE is_return = 0
GROUP BY customer_id;

CREATE OR REPLACE VIEW v_rfm_customers AS
WITH scored AS (
    SELECT b.*,
           ROUND(monetary / frequency, 2)                           AS avg_order_value,
           NTILE(5) OVER (ORDER BY recency_days DESC, customer_id)   AS r_score,
           CASE WHEN frequency = 1 THEN 1
                WHEN frequency = 2 THEN 2
                WHEN frequency <= 4 THEN 3
                WHEN frequency <= 9 THEN 4
                ELSE 5 END                                          AS f_score,
           NTILE(5) OVER (ORDER BY monetary, customer_id)            AS m_score
    FROM v_rfm_base b
)
SELECT scored.*,
       CASE
           WHEN r_score >= 4 AND f_score >= 4 THEN 'Champions'
           WHEN r_score >= 4 AND f_score = 3  THEN 'Loyal'
           WHEN r_score = 3  AND f_score >= 3 THEN 'Loyal'
           WHEN r_score >= 4                  THEN 'Recent'
           WHEN r_score = 3                   THEN 'Cooling'
           WHEN f_score >= 3                  THEN 'At Risk'
           ELSE 'Hibernating'
       END AS segment
FROM scored;

-- Q6. How do the segments compare? Customers, revenue and typical behaviour.
SELECT segment,
       COUNT(*)                                                  AS customers,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)        AS pct_of_customers,
       ROUND(SUM(monetary), 0)                                   AS revenue,
       ROUND(100.0 * SUM(monetary) / SUM(SUM(monetary)) OVER (), 1) AS pct_of_revenue,
       ROUND(AVG(frequency), 1)                                  AS avg_orders,
       ROUND(AVG(monetary), 0)                                   AS avg_spend,
       ROUND(AVG(recency_days), 0)                               AS avg_days_since_last_order
FROM v_rfm_customers
GROUP BY segment
ORDER BY revenue DESC;

-- Q7. How concentrated is revenue? Share of revenue by customer decile
--     (decile 1 = top 10% of customers by spend).
WITH ranked AS (
    SELECT customer_id, monetary,
           NTILE(10) OVER (ORDER BY monetary DESC, customer_id) AS decile
    FROM v_rfm_base
)
SELECT decile,
       COUNT(*)                                                  AS customers,
       ROUND(SUM(monetary), 0)                                   AS revenue,
       ROUND(100.0 * SUM(monetary) / SUM(SUM(monetary)) OVER (), 1) AS pct_of_revenue,
       ROUND(100.0 * SUM(SUM(monetary)) OVER (ORDER BY decile)
             / SUM(SUM(monetary)) OVER (), 1)                    AS cumulative_pct
FROM ranked
GROUP BY decile
ORDER BY decile;

-- Q8. Who should be contacted first? The 15 highest-spending At Risk customers.
SELECT customer_id, country, DATE(last_order) AS last_order,
       recency_days, frequency AS orders, monetary AS total_spend
FROM v_rfm_customers
WHERE segment = 'At Risk'
ORDER BY monetary DESC
LIMIT 15;

-- ---------------------------------------------------------------------
-- C. RETENTION AND REPEAT BUYING
-- Customers whose first purchase is in December 2009 are left out of the
-- "new customer" measures below, because the data starts that month and
-- they include people who had already been buying before.
-- ---------------------------------------------------------------------

-- Q9. Do new customers come back? Share who buy again on a later day
--     within 90 days of their first order (first orders from Jan 2010 to
--     10 Sep 2011, so every customer has a full 90 days to return).
WITH firsts AS (
    SELECT customer_id, MIN(invoice_date) AS first_date
    FROM invoices
    WHERE is_return = 0
    GROUP BY customer_id
),
later AS (
    SELECT i.customer_id, MIN(i.invoice_date) AS next_date
    FROM invoices i
    JOIN firsts f ON f.customer_id = i.customer_id
    WHERE i.is_return = 0 AND DATE(i.invoice_date) > DATE(f.first_date)
    GROUP BY i.customer_id
)
SELECT COUNT(*) AS new_customers,
       SUM(CASE WHEN l.next_date IS NOT NULL
                 AND DATEDIFF(DATE(l.next_date), DATE(f.first_date)) <= 90
                THEN 1 ELSE 0 END) AS came_back_within_90_days,
       ROUND(100.0 * SUM(CASE WHEN l.next_date IS NOT NULL
                 AND DATEDIFF(DATE(l.next_date), DATE(f.first_date)) <= 90
                THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_came_back
FROM firsts f
LEFT JOIN later l ON l.customer_id = f.customer_id
WHERE f.first_date >= '2010-01-01' AND DATE(f.first_date) <= '2011-09-10';

-- Q10. Cohort retention, long format (one row per cohort and month).
--      month_index 0 is the cohort's first month, 1 is the month after, etc.
CREATE OR REPLACE VIEW v_cohort_retention AS
WITH first_order AS (
    SELECT customer_id, DATE_FORMAT(MIN(invoice_date), '%Y-%m-01') AS cohort_month
    FROM invoices
    WHERE is_return = 0
    GROUP BY customer_id
),
activity AS (
    SELECT DISTINCT customer_id, DATE_FORMAT(invoice_date, '%Y-%m-01') AS active_month
    FROM invoices
    WHERE is_return = 0 AND invoice_date < '2011-12-01'
),
cohort AS (
    SELECT f.cohort_month,
           (YEAR(a.active_month) - YEAR(f.cohort_month)) * 12
             + MONTH(a.active_month) - MONTH(f.cohort_month) AS month_index,
           COUNT(DISTINCT a.customer_id)                     AS active_customers
    FROM first_order f
    JOIN activity a ON a.customer_id = f.customer_id
    GROUP BY f.cohort_month, month_index
)
SELECT cohort_month,
       month_index,
       active_customers,
       FIRST_VALUE(active_customers) OVER (PARTITION BY cohort_month ORDER BY month_index) AS cohort_size,
       ROUND(100.0 * active_customers /
             FIRST_VALUE(active_customers) OVER (PARTITION BY cohort_month ORDER BY month_index), 1) AS retention_pct
FROM cohort
WHERE cohort_month > '2009-12-01';

SELECT * FROM v_cohort_retention
WHERE month_index <= 3 AND cohort_month <= '2010-06-01'
ORDER BY cohort_month, month_index;

-- Q11. Average retention curve: what share of a cohort is still buying
--      1 to 12 months after its first month? Only cohorts that have
--      reached that many months are counted.
WITH sizes AS (
    SELECT cohort_month, active_customers AS cohort_size
    FROM v_cohort_retention
    WHERE month_index = 0
)
SELECT i.month_index,
       COUNT(*)                                                       AS cohorts_counted,
       SUM(s.cohort_size)                                             AS customers_in_cohorts,
       SUM(COALESCE(c.active_customers, 0))                           AS still_buying,
       ROUND(100.0 * SUM(COALESCE(c.active_customers, 0)) / SUM(s.cohort_size), 1) AS retention_pct
FROM sizes s
CROSS JOIN (SELECT 1 AS month_index UNION ALL SELECT 2 UNION ALL SELECT 3
            UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6
            UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9
            UNION ALL SELECT 10 UNION ALL SELECT 11 UNION ALL SELECT 12) i
LEFT JOIN v_cohort_retention c
       ON c.cohort_month = s.cohort_month AND c.month_index = i.month_index
WHERE (2011 - YEAR(s.cohort_month)) * 12 + 11 - MONTH(s.cohort_month) >= i.month_index
GROUP BY i.month_index
ORDER BY i.month_index;

-- Q12. How much revenue comes from repeat orders? Compare each customer's
--      first invoice with all later invoices.
WITH numbered AS (
    SELECT invoice_value,
           ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY invoice_date, invoice_no) AS order_no
    FROM invoices
    WHERE is_return = 0
)
SELECT CASE WHEN order_no = 1 THEN 'First order' ELSE 'Repeat order' END AS order_type,
       COUNT(*)                                                   AS invoices,
       ROUND(SUM(invoice_value), 0)                               AS revenue,
       ROUND(100.0 * SUM(invoice_value) / SUM(SUM(invoice_value)) OVER (), 1) AS pct_of_revenue
FROM numbered
GROUP BY CASE WHEN order_no = 1 THEN 'First order' ELSE 'Repeat order' END;

-- ---------------------------------------------------------------------
-- D. MONTHLY VIEW FOR POWER BI
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_monthly AS
SELECT DATE_FORMAT(invoice_date, '%Y-%m-01')        AS month_start,
       ROUND(SUM(invoice_value), 2)                 AS revenue,
       COUNT(*)                                     AS invoices,
       COUNT(DISTINCT customer_id)                  AS active_customers
FROM invoices
WHERE is_return = 0 AND invoice_date < '2011-12-01'
GROUP BY DATE_FORMAT(invoice_date, '%Y-%m-01');
