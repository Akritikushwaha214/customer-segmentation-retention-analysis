-- =====================================================================
-- Customer Segmentation & Retention (RFM + Cohort)  |  Akriti Kushwaha
-- File 1 of 2: create database and table, then load data/invoices.csv
-- Tested for: MySQL 8.0+ (window functions and CTEs need 8.0 or newer)
-- =====================================================================

CREATE DATABASE IF NOT EXISTS retail_retention;
USE retail_retention;

DROP VIEW IF EXISTS v_monthly;
DROP VIEW IF EXISTS v_rfm_customers;
DROP VIEW IF EXISTS v_cohort_retention;
DROP VIEW IF EXISTS v_rfm_base;
DROP TABLE IF EXISTS invoices;

-- One row per invoice (built by prep/prepare_invoices.py).
-- is_return = 1 for cancellation invoices (invoice numbers starting with C).
CREATE TABLE invoices (
    invoice_no     VARCHAR(12)   NOT NULL PRIMARY KEY,
    customer_id    INT           NOT NULL,
    invoice_date   DATETIME      NOT NULL,
    country        VARCHAR(40)   NOT NULL,
    line_count     INT           NOT NULL,
    units          INT           NOT NULL,
    invoice_value  DECIMAL(12,2) NOT NULL,   -- GBP, negative for returns
    is_return      TINYINT       NOT NULL,
    INDEX idx_customer (customer_id),
    INDEX idx_date (invoice_date)
);

-- ---------------------------------------------------------------------
-- LOAD THE DATA
-- Option A (easiest, MySQL Workbench): in the left panel refresh SCHEMAS,
--   open retail_retention > Tables, right-click "invoices" >
--   "Table Data Import Wizard" > choose data/invoices.csv > Next >
--   keep "Use existing table" > Next > Next. It takes a few minutes.
--
-- Option B (script, faster): change the path below and run. If you get
--   error 3948 or 1290, run  SET GLOBAL local_infile = 1;  once and
--   reconnect with the "OPT_LOCAL_INFILE=1" option.
-- ---------------------------------------------------------------------
-- LOAD DATA LOCAL INFILE 'C:/path/to/data/invoices.csv'
-- INTO TABLE invoices FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
-- LINES TERMINATED BY '\n' IGNORE 1 LINES;

-- After loading this should return 43876, 36594, 7282, 5852
SELECT COUNT(*)                                          AS invoices,
       SUM(CASE WHEN is_return = 0 THEN 1 ELSE 0 END)    AS sales,
       SUM(is_return)                                    AS returns_,
       COUNT(DISTINCT CASE WHEN is_return = 0 THEN customer_id END) AS customers_with_sale
FROM invoices;
