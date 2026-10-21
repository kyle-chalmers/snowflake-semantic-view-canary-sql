-- Fix the review findings on TPCH_SEMANTIC_VIEW:
--   * tables now read ANALYTICS.TPCH_COPY (created by 01_copy_tpch.sql) instead of the sample share
--   * total_revenue is renamed gross_revenue and keeps only gross synonyms
--   * new net_revenue (after discount) takes 'revenue', 'sales' and 'total sales'
--   * comments describe only what the view exposes and say which revenue metric is which
-- Both revenue metrics keep returned lines and unfulfilled orders, matching the previous behavior.
-- Run after 01_copy_tpch.sql, as a role with OWNERSHIP of the view.
-- Renaming total_revenue breaks any query that still asks for line_items.total_revenue.

CREATE OR ALTER SEMANTIC VIEW ANALYTICS.SEMANTIC_DEMO.TPCH_SEMANTIC_VIEW
  TABLES (
    customers AS ANALYTICS.TPCH_COPY.CUSTOMER
      PRIMARY KEY (C_CUSTKEY)
      WITH SYNONYMS = ('customer', 'buyers')
      COMMENT = 'Customer master data including market segment classification. Each customer belongs to one of five market segments: AUTOMOBILE, BUILDING, FURNITURE, HOUSEHOLD, or MACHINERY.',
    orders AS ANALYTICS.TPCH_COPY.ORDERS
      PRIMARY KEY (O_ORDERKEY)
      WITH SYNONYMS = ('order', 'purchases')
      COMMENT = 'Order headers with the date each order was placed. One customer can have many orders.',
    line_items AS ANALYTICS.TPCH_COPY.LINEITEM
      PRIMARY KEY (L_ORDERKEY, L_LINENUMBER)
      WITH SYNONYMS = ('line item', 'order lines')
      COMMENT = 'Order line items. Each order has one or more line items. L_EXTENDEDPRICE is the gross line price before discount; L_DISCOUNT is the discount as a fraction of that price.'
  )
  RELATIONSHIPS (
    orders_to_customers AS orders (O_CUSTKEY) REFERENCES customers,
    line_items_to_orders AS line_items (L_ORDERKEY) REFERENCES orders
  )
  DIMENSIONS (
    customers.market_segment AS C_MKTSEGMENT
      WITH SYNONYMS = ('segment', 'customer segment', 'business segment', 'mktsegment')
      COMMENT = 'Customer market segment: AUTOMOBILE, BUILDING, FURNITURE, HOUSEHOLD, or MACHINERY',
    orders.order_date AS O_ORDERDATE
      WITH SYNONYMS = ('date', 'order date', 'purchase date')
      COMMENT = 'Date the order was placed'
  )
  METRICS (
    line_items.gross_revenue AS SUM(L_EXTENDEDPRICE)
      WITH SYNONYMS = ('gross revenue', 'gross sales')
      COMMENT = 'Gross revenue: sum of line item extended prices before discount. Use only when the question asks for gross. For revenue or sales without a qualifier, use net_revenue.',
    line_items.net_revenue AS SUM(L_EXTENDEDPRICE * (1 - L_DISCOUNT))
      WITH SYNONYMS = ('net revenue', 'sales', 'total sales', 'revenue')
      COMMENT = 'Net revenue: sum of line item extended prices after discount. This is the default meaning of revenue and sales.',
    orders.total_orders AS COUNT(DISTINCT O_ORDERKEY)
      WITH SYNONYMS = ('order count', 'number of orders', 'orders')
      COMMENT = 'Total number of distinct orders'
  )
  COMMENT = 'Governed semantic layer for TPCH revenue analysis: revenue, orders, and market segments. Revenue and sales mean net_revenue (extended price after discount). gross_revenue (before discount) answers only questions that ask for gross. Both include returned line items and orders of every status.'
;

-- Check: for orders placed in 1995 this should return gross 34,964,401,999.53,
-- net 33,216,895,045.8295 and 228,637 orders, the values computed from the source tables
-- on 2026-10-11.
SELECT
    SUM(gross_revenue) AS gross_revenue,
    SUM(net_revenue)   AS net_revenue,
    SUM(total_orders)  AS total_orders
FROM SEMANTIC_VIEW(
    ANALYTICS.SEMANTIC_DEMO.TPCH_SEMANTIC_VIEW
    METRICS line_items.gross_revenue, line_items.net_revenue, orders.total_orders
    DIMENSIONS orders.order_date
)
WHERE order_date >= '1995-01-01'
  AND order_date <  '1996-01-01';
