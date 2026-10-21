# Snowflake Semantic View Canary

> IMPORTANT: Everything in this repo is public-facing. Never place secrets, credentials, account
> identifiers or personal information in any committed file.

## Project overview

This project keeps a Snowflake Semantic View correct over time. It has two parts:

1. A review of the view's definition (its DDL) that checks keys and relationship direction,
   business-term coverage, whether each metric's SQL matches its name and synonyms, and whether
   the comments say what they should.
2. A canary: a scheduled Task that asks the view for a few validated numbers every morning, a
   log table that keeps every answer, and an Alert that emails the owner when a number moves or
   a check never lands.

Intended users: data and analytics engineers who own a Semantic View in Snowflake.

## Access model

- Read through the Snowflake CLI: `snow sql -q "<query>"`. The default connection
  (`SNOWFLAKE_DEFAULT_CONNECTION_NAME`) uses a read-only role.
- Never run a statement that creates, alters, drops, grants, updates or deletes anything. Write
  those statements to a file under `sql/` instead, numbered in run order
  (`sql/01_...sql`, `sql/02_...sql`), and leave them for the view's owner to review and run.
- Show each query as a formatted SQL block before running it.

## Data

- Source tables: `SNOWFLAKE_SAMPLE_DATA.TPCH_SF1` (`CUSTOMER`, `ORDERS`, `LINEITEM`), a
  read-only sample-data share. `LINEITEM` has about 6M rows.
- The semantic view: `ANALYTICS.SEMANTIC_DEMO.TPCH_SEMANTIC_VIEW`, created by
  `sql/00_create_starting_view.sql`.
- Join `LINEITEM` to `ORDERS` on `L_ORDERKEY = O_ORDERKEY` (many line items per order).

## Snowflake Semantic View reference

Clause order matters: TABLES, RELATIONSHIPS, FACTS, DIMENSIONS, METRICS, COMMENT.

```sql
CREATE [OR REPLACE | OR ALTER] SEMANTIC VIEW <name>
  TABLES (
    <alias> AS <fully_qualified_table>
      PRIMARY KEY (<columns>)
      [WITH SYNONYMS = ('<synonym>', ...)]
      [COMMENT = '<description>']
  )
  [RELATIONSHIPS (
    <name> AS <alias> (<fk_columns>) REFERENCES <ref_alias>
  )]
  [FACTS (...)]
  DIMENSIONS (
    <table>.<dimension> AS <expression> [WITH SYNONYMS = (...)] [COMMENT = '...']
  )
  METRICS (
    <table>.<metric> AS <aggregate_expression> [WITH SYNONYMS = (...)] [COMMENT = '...']
  )
  [COMMENT = '<view-level comment>']
;
```

- Read the definition with `SELECT GET_DDL('SEMANTIC_VIEW', '<db>.<schema>.<view>');`.
- Query it with `SEMANTIC_VIEW(...)`:
  ```sql
  SELECT * FROM SEMANTIC_VIEW(
    ANALYTICS.SEMANTIC_DEMO.TPCH_SEMANTIC_VIEW
    METRICS line_items.total_revenue
    DIMENSIONS customers.market_segment
  );
  ```
- `CREATE OR ALTER SEMANTIC VIEW` redefines an existing view in place and needs OWNERSHIP of it.
  `ALTER SEMANTIC VIEW` only changes properties such as the comment.
- Relationships have no cardinality keyword: the side holding the PRIMARY KEY is the "one" side.

## Scheduling reference

- Tasks and Alerts are created suspended. Each needs `ALTER TASK ... RESUME` /
  `ALTER ALERT ... RESUME` before it runs on its schedule.
- `EXECUTE TASK` starts a run asynchronously. Wait until
  `TABLE(INFORMATION_SCHEMA.TASK_HISTORY(TASK_NAME => '<name>'))` shows the run `SUCCEEDED`
  before reading what it wrote.
- Email from an Alert goes through `SYSTEM$SEND_EMAIL('<notification integration>', '<address>',
  '<subject>', '<body>')`.

## Working principles

- Explain what a metric's SQL actually computes in plain English.
- When a business term could reasonably mean two different things, say so and ask rather than
  picking one.
- Back every claim about the data with a query result, not with the DDL alone.
- Keep generated SQL readable: one clause per line, uppercase keywords, comments only where the
  reason is not obvious.
