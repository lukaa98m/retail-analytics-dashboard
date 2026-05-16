-- =====================================================================
-- Retail Analytics Dashboard — MySQL Schema
-- =====================================================================
-- Source dataset: Superstore (9,800 transactions, 2015-2018, US)
-- Normalized from a single flat CSV into 5 tables.
--
-- Design notes:
--   - Geography (region, state, city, postal code) lives on ORDERS, not
--     customers. Inspection of the source data shows the same customer
--     can have orders shipped to different states/regions — realistic
--     (customers move, multi-address ordering) and verified empirically.
--     Geography IS consistent within a single order.
--   - regions is a lookup table for the 4 US Census regions used for
--     the map visual and to demonstrate a clean join.
--   - orders holds header-level data (date, customer, geography);
--     order_items holds line-level data (product, sales). Mirrors how
--     real retail schemas are modeled.
-- =====================================================================

DROP DATABASE IF EXISTS retail_analytics;
CREATE DATABASE retail_analytics
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;
USE retail_analytics;

-- ---------------------------------------------------------------------
-- regions — lookup table for the 4 US Census regions
-- ---------------------------------------------------------------------
CREATE TABLE regions (
    region_id       TINYINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
    region_name     VARCHAR(20) NOT NULL UNIQUE
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- customers — one row per unique Customer ID
-- Geography is NOT stored here (see schema design notes).
-- ---------------------------------------------------------------------
CREATE TABLE customers (
    customer_id     VARCHAR(10) PRIMARY KEY,          -- e.g. 'CG-12520'
    customer_name   VARCHAR(100) NOT NULL,
    segment         ENUM('Consumer', 'Corporate', 'Home Office') NOT NULL
) ENGINE=InnoDB;

CREATE INDEX idx_customers_segment ON customers(segment);

-- ---------------------------------------------------------------------
-- products — one row per unique Product ID
-- ---------------------------------------------------------------------
CREATE TABLE products (
    product_id      VARCHAR(20) PRIMARY KEY,          -- e.g. 'FUR-BO-10001798'
    product_name    VARCHAR(255) NOT NULL,
    category        ENUM('Furniture', 'Office Supplies', 'Technology') NOT NULL,
    sub_category    VARCHAR(50) NOT NULL
) ENGINE=InnoDB;

CREATE INDEX idx_products_category     ON products(category);
CREATE INDEX idx_products_sub_category ON products(sub_category);

-- ---------------------------------------------------------------------
-- orders — one row per Order ID (header)
-- Geography lives here (verified consistent per order in source data).
-- ---------------------------------------------------------------------
CREATE TABLE orders (
    order_id        VARCHAR(20) PRIMARY KEY,          -- e.g. 'CA-2017-152156'
    customer_id     VARCHAR(10) NOT NULL,
    order_date      DATE NOT NULL,
    ship_date       DATE NOT NULL,
    ship_mode       ENUM('Standard Class', 'Second Class', 'First Class', 'Same Day') NOT NULL,
    country         VARCHAR(50) NOT NULL,
    city            VARCHAR(100) NOT NULL,
    state           VARCHAR(50) NOT NULL,
    postal_code     VARCHAR(10),                      -- nullable (11 missing in source)
    region_id       TINYINT UNSIGNED NOT NULL,
    CONSTRAINT fk_orders_customer
        FOREIGN KEY (customer_id) REFERENCES customers(customer_id),
    CONSTRAINT fk_orders_region
        FOREIGN KEY (region_id) REFERENCES regions(region_id)
) ENGINE=InnoDB;

CREATE INDEX idx_orders_customer   ON orders(customer_id);
CREATE INDEX idx_orders_order_date ON orders(order_date);
CREATE INDEX idx_orders_region     ON orders(region_id);
CREATE INDEX idx_orders_state      ON orders(state);

-- ---------------------------------------------------------------------
-- order_items — one row per line item (Row ID)
-- ---------------------------------------------------------------------
CREATE TABLE order_items (
    order_item_id   INT UNSIGNED PRIMARY KEY,         -- Row ID from source
    order_id        VARCHAR(20) NOT NULL,
    product_id      VARCHAR(20) NOT NULL,
    sales           DECIMAL(12, 4) NOT NULL,
    CONSTRAINT fk_items_order
        FOREIGN KEY (order_id) REFERENCES orders(order_id),
    CONSTRAINT fk_items_product
        FOREIGN KEY (product_id) REFERENCES products(product_id)
) ENGINE=InnoDB;

CREATE INDEX idx_items_order   ON order_items(order_id);
CREATE INDEX idx_items_product ON order_items(product_id);

-- ---------------------------------------------------------------------
-- Seed regions (the ETL script assumes these IDs)
-- ---------------------------------------------------------------------
INSERT INTO regions (region_id, region_name) VALUES
    (1, 'Central'),
    (2, 'East'),
    (3, 'South'),
    (4, 'West');
