-- Canary for TPCH_SEMANTIC_VIEW: every morning, ask the view for three validated 1995 numbers,
-- log the answers, and email the owner when a number moves or a check never lands.
-- Run after 02_fix_semantic_view.sql, as a role that can create schemas in ANALYTICS and has
-- EXECUTE TASK and EXECUTE ALERT, USAGE on warehouse COMPUTE_EXTRA_SMALL and on the notification
-- integration CANARY_EMAIL, and SELECT on the semantic view.
--
-- Before running: replace <owner email> below with the address that should receive alerts. It must
-- be in CANARY_EMAIL's ALLOWED_RECIPIENTS and verified in Snowflake. This repo is public, so keep
-- the real address out of the committed copy.

CREATE SCHEMA IF NOT EXISTS ANALYTICS.CANARY;

-- IF NOT EXISTS, not OR REPLACE: rerunning this script must never wipe the check history.
CREATE TABLE IF NOT EXISTS ANALYTICS.CANARY.CANARY_LOG (
    check_date DATE,
    checked_at TIMESTAMP_LTZ,
    metric     STRING,
    actual     NUMBER(38,2),
    expected   NUMBER(38,2),
    ok         BOOLEAN
);

-- One row: what the semantic view returns today for orders placed in 1995.
CREATE OR REPLACE VIEW ANALYTICS.CANARY.REVENUE_1995 AS
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

-- Expected values were computed directly from SNOWFLAKE_SAMPLE_DATA.TPCH_SF1 on 2026-10-11 and
-- confirmed against the fixed view on 2026-10-20. 1995 is a closed period, so they should never move.
-- ok is computed on the unrounded actual, and a NULL actual (view returned nothing) logs ok = FALSE.
CREATE OR REPLACE TASK ANALYTICS.CANARY.CANARY_CHECK
    WAREHOUSE = COMPUTE_EXTRA_SMALL
    SCHEDULE = 'USING CRON 0 7 * * * America/Phoenix'
AS
INSERT INTO ANALYTICS.CANARY.CANARY_LOG (check_date, checked_at, metric, actual, expected, ok)
SELECT
    CONVERT_TIMEZONE('America/Phoenix', CURRENT_TIMESTAMP())::DATE,
    CURRENT_TIMESTAMP(),
    c.metric,
    c.actual,
    c.expected,
    COALESCE(ABS(c.actual - c.expected) <= 0.01, FALSE)
FROM (
    SELECT 'gross_revenue' AS metric, gross_revenue AS actual, 34964401999.53 AS expected
    FROM ANALYTICS.CANARY.REVENUE_1995
    UNION ALL
    SELECT 'net_revenue', net_revenue, 33216895045.83
    FROM ANALYTICS.CANARY.REVENUE_1995
    UNION ALL
    SELECT 'total_orders', total_orders, 228637
    FROM ANALYTICS.CANARY.REVENUE_1995
) AS c;

-- Runs an hour after the Task. Fires when today's check did not land (fewer than three rows, which
-- also covers a failed or skipped Task run) or when any of today's rows is not ok, NULL included.
CREATE OR REPLACE ALERT ANALYTICS.CANARY.CANARY_ALERT
    WAREHOUSE = COMPUTE_EXTRA_SMALL
    SCHEDULE = 'USING CRON 0 8 * * * America/Phoenix'
IF (EXISTS (
    SELECT 1
    WHERE (
        SELECT COUNT(*)
        FROM ANALYTICS.CANARY.CANARY_LOG
        WHERE check_date = CONVERT_TIMEZONE('America/Phoenix', CURRENT_TIMESTAMP())::DATE
    ) < 3
    OR EXISTS (
        SELECT 1
        FROM ANALYTICS.CANARY.CANARY_LOG
        WHERE check_date = CONVERT_TIMEZONE('America/Phoenix', CURRENT_TIMESTAMP())::DATE
          AND ok IS DISTINCT FROM TRUE
    )
))
THEN
    CALL SYSTEM$SEND_EMAIL(
        'CANARY_EMAIL',
        '<owner email>',
        'TPCH_SEMANTIC_VIEW canary failed',
        'Today''s canary check on ANALYTICS.SEMANTIC_DEMO.TPCH_SEMANTIC_VIEW either did not land or returned a number that moved. Inspect with: SELECT * FROM ANALYTICS.CANARY.CANARY_LOG ORDER BY checked_at DESC LIMIT 10;'
    );

-- Tasks and Alerts are created suspended; neither runs on its schedule until resumed.
ALTER TASK ANALYTICS.CANARY.CANARY_CHECK RESUME;
ALTER ALERT ANALYTICS.CANARY.CANARY_ALERT RESUME;
